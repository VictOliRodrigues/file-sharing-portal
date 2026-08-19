# Deployment

The portal is an ordinary Dockerfile application: one container, a PostgreSQL
database, and either a writable volume or an S3 bucket. Nothing below is tied to
a particular hosting platform.

## What you need

- PostgreSQL 14 or newer
- Somewhere to keep uploads: a persistent volume, or an S3-compatible bucket
- A reverse proxy terminating TLS in front of the application
- A long random `SECRET_KEY_BASE`

Generate the secret with:

```bash
docker run --rm file-sharing-portal bin/rails secret
```

## Docker Compose on a VPS

This is the simplest complete deployment.

```bash
git clone https://github.com/VictOliRodrigues/file-sharing-portal.git
cd file-sharing-portal
cp .env.example .env
```

Edit `.env`. At minimum:

```dotenv
SECRET_KEY_BASE=<output of bin/rails secret>
POSTGRES_PASSWORD=<a strong password>
APP_HOST=files.example.com
ALLOWED_HOSTS=files.example.com
ALLOW_REGISTRATION=false
MAIL_FROM=no-reply@example.com
```

Then:

```bash
docker compose up -d --build
docker compose logs -f web
```

The stack exposes the application on `${PORT:-3000}`. Migrations run
automatically on boot, so it comes up cleanly on an empty database.

Create the first administrator either by registering through the interface —
the first account on an empty installation is automatically an administrator —
or by setting `ADMIN_EMAIL` and `ADMIN_PASSWORD` and running:

```bash
docker compose exec web bin/rails db:seed
```

Remove those two variables from `.env` afterwards.

## Reverse proxy and TLS

The application expects TLS to be terminated in front of it. Keep
`ASSUME_SSL=true` so it trusts `X-Forwarded-Proto`, and `FORCE_SSL=true` so it
redirects plain HTTP, sends HSTS and marks cookies secure.

The health check on `/up` is deliberately exempt from the HTTPS redirect so
that container orchestrators can probe it over plain HTTP.

### Caddy

```
files.example.com {
    reverse_proxy localhost:3000
}
```

### nginx

```nginx
server {
    listen 443 ssl http2;
    server_name files.example.com;

    ssl_certificate     /etc/letsencrypt/live/files.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/files.example.com/privkey.pem;

    # Uploads are large; do not let nginx cut them short.
    client_max_body_size 512M;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Downloads stream; disable buffering so they start immediately.
        proxy_buffering off;
        proxy_read_timeout 300s;
    }
}
```

Set `client_max_body_size` (or the Traefik/Caddy equivalent) to at least
`MAX_UPLOAD_SIZE_MB`, otherwise the proxy rejects large uploads before the
application ever sees them.

### Traefik

Traefik has no request body limit by default, so only the usual router and
service labels are needed. Point the service at port 80 of the container.

## Coolify

Coolify runs the project as a plain Dockerfile application. Nothing
Coolify-specific is required, and the same image runs unchanged elsewhere.

1. **New resource** → *Dockerfile* (or *Docker Compose*), pointing at your fork.
2. Add a **PostgreSQL** resource. Copy its connection string into `DATABASE_URL`.
3. Set the environment variables from `.env.example`. At minimum
   `SECRET_KEY_BASE`, `DATABASE_URL`, `APP_HOST`, `ALLOWED_HOSTS`.
4. When using local storage, add a **persistent volume** mounted at
   `/rails/storage`. Skip this if `ACTIVE_STORAGE_SERVICE=s3`.
5. Set the exposed port to **80**. Coolify terminates TLS, so keep
   `ASSUME_SSL=true` and `FORCE_SSL=true`.
6. Deploy. The health check on `/up` tells Coolify when the container is ready.

Coolify supplies `DATABASE_URL` for its managed databases, and the application
prefers it over the individual `POSTGRES_*` variables, so no further wiring is
needed.

## Storage backends

### Local disk

```dotenv
ACTIVE_STORAGE_SERVICE=local
STORAGE_PATH=/rails/storage
```

Mount a volume at `STORAGE_PATH`. Without one, uploads disappear when the
container is replaced. This is the right choice for a single-host deployment.

### S3-compatible

```dotenv
ACTIVE_STORAGE_SERVICE=s3
S3_BUCKET=my-portal-bucket
S3_REGION=us-east-1
S3_ACCESS_KEY_ID=...
S3_SECRET_ACCESS_KEY=...
```

For anything that is not AWS — MinIO, Cloudflare R2, Backblaze B2, Wasabi,
Hetzner Object Storage — also set:

```dotenv
S3_ENDPOINT=https://s3.example.com
S3_FORCE_PATH_STYLE=true
```

The bucket should be **private**. The portal never issues public object URLs;
it streams every download through the application so that authorisation is
always checked. A public bucket would quietly undo that.

### Moving from local to S3

```bash
docker compose exec web bin/rails runner '
  ActiveStorage::Blob.find_each do |blob|
    next if blob.service_name == "s3"
    blob.open { |file| ActiveStorage::Blob.service.upload(blob.key, file, checksum: blob.checksum) }
  end
'
```

Take a backup first, switch `ACTIVE_STORAGE_SERVICE` afterwards, and verify a
few downloads before deleting anything from the old location.

## Scaling

The default is one Puma process with `RAILS_MAX_THREADS` threads. That keeps
rate limit counters in a single shared in-memory cache, which is what makes the
limits exact.

To run more than one worker or more than one container:

```dotenv
WEB_CONCURRENCY=2
REDIS_URL=redis://redis:6379/0
```

The cache store switches to Redis automatically, so throttling stays accurate.
Move storage to S3 at the same time, because a local disk is not shared between
containers.

## Backups

Two things need backing up, and restoring one without the other leaves metadata
and bytes out of step.

**Database**

```bash
docker compose exec -T db pg_dump -U portal file_sharing_portal_production \
  | gzip > portal-$(date +%F).sql.gz
```

**File storage** — back up the volume behind `STORAGE_PATH`, or rely on
versioning and replication on the S3 bucket.

Restore:

```bash
gunzip -c portal-2026-01-31.sql.gz \
  | docker compose exec -T db psql -U portal file_sharing_portal_production
```

## Maintenance

```bash
# Permanently delete trash older than TRASH_RETENTION_DAYS
docker compose exec web bin/rails portal:purge_trash

# Remove blobs that are no longer attached to anything
docker compose exec web bin/rails portal:purge_orphan_blobs

# Print usage statistics
docker compose exec web bin/rails portal:stats
```

A weekly cron entry is enough:

```cron
0 3 * * 0 cd /srv/file-sharing-portal && docker compose exec -T web bin/rails portal:purge_trash
```

## Upgrading

```bash
git pull
docker compose up -d --build
```

Migrations run on boot. Back up the database first; there is no automatic
rollback.

## Troubleshooting

**The container restarts in a loop.** Check `docker compose logs web`. The
usual cause is a missing `SECRET_KEY_BASE` or a database it cannot reach. The
entrypoint waits up to 60 seconds for PostgreSQL before giving up.

**Uploads fail for large files but work for small ones.** The reverse proxy is
cutting the request short. Raise `client_max_body_size` (nginx) or the
equivalent, and check `MAX_UPLOAD_SIZE_MB`.

**Blocked by host authorisation.** `ALLOWED_HOSTS` does not include the
hostname being used. Add it, or leave the variable empty to accept any host.

**Downloads are slow to start or arrive truncated.** Turn off response
buffering in the proxy (`proxy_buffering off` in nginx). Downloads are streamed.

**Rate limits trigger too easily behind a proxy.** The application must see the
real client address. Make sure the proxy sets `X-Forwarded-For`.

**Emails are not arriving.** With `SMTP_ADDRESS` empty, messages are written to
the log instead of being sent. Configure the `SMTP_*` variables to deliver them.
