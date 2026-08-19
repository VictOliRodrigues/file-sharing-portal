# Development

## Requirements

Either Docker, or a local toolchain:

- Ruby 3.4 (the exact version is pinned in `.ruby-version`)
- PostgreSQL 14 or newer
- libvips, for image previews
- A C toolchain and `libpq-dev`, for the `pg` and `bcrypt` native extensions

## Getting started

### With Docker

Nothing to install beyond Docker itself:

```bash
docker compose -f docker-compose.dev.yml up --build
```

This starts PostgreSQL, prepares the database, and runs the Rails server
together with the Tailwind watcher. The source tree is bind-mounted, so edits
on the host take effect immediately. The application is on
<http://localhost:3000>.

Run commands inside the container:

```bash
docker compose -f docker-compose.dev.yml exec web bin/rails console
docker compose -f docker-compose.dev.yml exec web bin/rails test
```

### Without Docker

```bash
bin/setup
```

That installs gems, prepares the database and starts the server. To do it step
by step:

```bash
bundle install
bin/rails db:prepare
bin/dev
```

`bin/dev` runs the processes in `Procfile.dev`: the Rails server and the
Tailwind watcher.

Database connection settings come from the environment and default to
`localhost:5432` as the `postgres` user with no password. Override them if your
setup differs:

```bash
export POSTGRES_USER=myuser
export POSTGRES_PASSWORD=mypassword
```

## First account

The first account registered on an empty installation automatically becomes an
administrator. Just open <http://localhost:3000/sign_up>.

To create one from the command line instead:

```bash
ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD=a-long-enough-password bin/rails db:seed
```

## Everyday commands

```bash
bin/rails test                          # the whole suite
bin/rails test test/models              # one directory
bin/rails test test/integration/share_link_test.rb        # one file
bin/rails test test/integration/share_link_test.rb:42     # one test, by line

bin/rubocop                             # style
bin/rubocop -a                          # fix what can be fixed automatically

bin/brakeman --no-pager                 # static security analysis
bin/bundler-audit                       # gem advisories
bin/importmap audit                     # JavaScript advisories

bin/ci                                  # everything above, in the CI order

bin/rails portal:stats                  # usage statistics
bin/rails portal:purge_trash            # empty old trash
bin/rails portal:purge_orphan_blobs     # remove unattached blobs
```

## Project layout

```
app/
  controllers/
    admin/            administration area, gated by Admin::BaseController
    concerns/         Authentication, Authorization, ShareLinkAccess, BlobStreaming
    profile/          password change and session management
    public/           the only controllers reachable without an account
  models/
    safe_filename.rb  turns a client filename into something safe to store
    upload_policy.rb  the configurable extension allow and block lists
    file_search.rb    the search query object
    system_statistics.rb  aggregates for the administration dashboard
  views/
    folders/browse    shared by the root listing and by a single folder
    public/shares/    what a share link recipient sees
config/
  initializers/
    file_sharing_portal.rb    settings read from the environment
    rack_attack.rb            throttling rules
    content_security_policy.rb
    security_headers.rb
lib/tasks/portal.rake         maintenance tasks
test/
  models/           validations, scopes, domain logic
  integration/      full request cycles, where security behaviour is covered
  mailers/
```

## Conventions

- Keep controllers thin. Load records through the signed-in user's own
  associations so authorisation falls out of the query rather than being
  checked afterwards.
- Put anything reusable in a model or a concern rather than a helper.
- Comments explain **why**, not what. Skip the comment if the code already says
  it.
- Every new setting goes in `.env.example` and in the README table, in the same
  change.

## Testing notes

The suite runs in parallel across processes. A few tests deliberately flip
global state and restore it in `teardown`:

- `rate_limiting_test.rb` switches `Rack::Attack.enabled` on, since it is off
  for the rest of the suite.
- `csrf_protection_test.rb` switches `ActionController::Base.allow_forgery_protection`
  on, since Rails turns it off in the test environment.
- `upload_policy_test.rb` sets and clears the `UPLOAD_*` environment variables.

Helpers available in integration tests, defined in `test/test_helper.rb`:

```ruby
sign_in_as(users(:alice))     # signs in through the real form
sign_out
uploaded_file(filename: "report.txt", content: "hello")
```

User fixtures live in `test/fixtures/users.yml` and all share the password in
`ActiveSupport::TestCase::TEST_PASSWORD`.

To create a file in a test:

```ruby
stored_file = user.stored_files.new(folder: folder)
stored_file.attachment.attach(
  io: StringIO.new("content"), filename: "notes.txt", content_type: "text/plain"
)
stored_file.save!
```

Note that Active Storage sanitises filenames itself before the application sees
them, replacing characters such as `%` and `/`. `SafeFilename` is a second
layer, and the one that also covers renames, where the name arrives straight
from a form.

## Working on the S3 storage path

Run MinIO locally:

```bash
docker run -d --name minio -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin -e MINIO_ROOT_PASSWORD=minioadmin \
  quay.io/minio/minio server /data --console-address ":9001"
```

Create a bucket at <http://localhost:9001>, then:

```bash
export ACTIVE_STORAGE_SERVICE=s3
export S3_BUCKET=portal
export S3_REGION=us-east-1
export S3_ACCESS_KEY_ID=minioadmin
export S3_SECRET_ACCESS_KEY=minioadmin
export S3_ENDPOINT=http://localhost:9000
export S3_FORCE_PATH_STYLE=true
bin/dev
```

## Working on emails

With `SMTP_ADDRESS` unset, development writes messages to the log. To read them
in a browser, run a catcher such as Mailpit and point the portal at it:

```bash
docker run -d -p 1025:1025 -p 8025:8025 axllent/mailpit
export SMTP_ADDRESS=localhost
export SMTP_PORT=1025
export SMTP_ENABLE_STARTTLS=false
```

## Database changes

```bash
bin/rails generate migration AddSomethingToStoredFiles
bin/rails db:migrate
```

Commit the updated `db/schema.rb` along with the migration. The project must
always start cleanly on an empty database, so avoid migrations that depend on
data already being there.

## Debugging

The `debug` gem is available in development and test. Drop `debugger` into the
code and the server pauses there. Under `bin/dev` the console is attached, so
you can interact with it directly.
