# Architecture

This document describes how the portal is put together and why the main
decisions were made the way they were.

## Shape of the system

```
                    ┌──────────────────────────┐
   Browser ────────▶│ Reverse proxy (TLS)      │
   Share recipient  │ nginx / Traefik / Caddy  │
                    └────────────┬─────────────┘
                                 │ HTTP, X-Forwarded-Proto
                    ┌────────────▼─────────────┐
                    │ Thruster                 │  asset caching + compression
                    ├──────────────────────────┤
                    │ Puma (threads)           │
                    ├──────────────────────────┤
                    │ Rack::Attack             │  throttling
                    ├──────────────────────────┤
                    │ Rails 8.1                │
                    └──────┬────────────┬──────┘
                           │            │
              ┌────────────▼───┐   ┌────▼──────────────────┐
              │ PostgreSQL     │   │ Local disk  or        │
              │ metadata       │   │ S3-compatible storage │
              └────────────────┘   └───────────────────────┘
```

One container serves the whole application. PostgreSQL holds all metadata;
uploaded bytes live in Active Storage, backed either by a directory on disk or
by an S3-compatible bucket. Which one is used is decided by a single
environment variable, and nothing in the application code depends on the answer.

## Stack choices

| Concern | Choice | Why |
| --- | --- | --- |
| Framework | Rails 8.1 | The brief asked for the common, maintainable Rails stack |
| Front-end | Hotwire + Tailwind, import maps, Propshaft | Rails defaults; no Node build step to maintain |
| Authentication | `has_secure_password` with server-side sessions | The modern Rails-native approach; fewer moving parts than a full auth gem and easier to audit |
| Authorisation | Association scoping | See below |
| Background jobs | Active Job with the async adapter | The only jobs are Active Storage analysis and purge. A durable queue would mean another service for very little gain |
| Cache | In-memory, or Redis when `REDIS_URL` is set | Single-process by default keeps rate limits accurate without another dependency |
| Throttling | Rack::Attack | The community standard, and it sits in front of the whole app |

Deliberately **not** included: Kamal, Solid Queue, Solid Cache, Solid Cable and
Action Cable. Each would have added a moving part that this application does
not need, and the brief asked to avoid unnecessary complexity.

## Domain model

```
User ──┬── Session            signed-in browsers, revocable
       ├── Folder ────────┐   self-referential tree, soft deletable
       ├── StoredFile ────┤   metadata for an Active Storage blob
       └── ShareLink ─────┘   polymorphic: points at a StoredFile or a Folder
                 │
              Download        one recorded fetch, by an account or a link
```

### User

Holds the account, an `admin` flag, a nullable `disabled_at`, and an optional
`storage_quota_bytes`. Disabling an account sets `disabled_at` **and** destroys
its sessions in the same transaction, so revocation is immediate rather than
eventual.

### Session

One row per signed-in browser. The browser only ever holds the row's id, inside
a signed HttpOnly cookie; every request looks the row up again. That is what
makes "sign out this device", "disable this account" and "password changed"
take effect at once instead of waiting for a token to expire.

### Folder

A per-user tree. A null `parent_id` means the folder sits at the root. Three
things keep the tree sane:

- **Uniqueness** — names are unique per parent, case insensitively. PostgreSQL
  treats NULL values as distinct, so two partial unique indexes are needed: one
  for `parent_id IS NOT NULL` and one for the root level.
- **No cycles** — a move is rejected if the destination is the folder itself or
  one of its descendants. The subtree is resolved with a recursive CTE, scoped
  to the owner, in one query.
- **Depth** — capped at 20 levels, which keeps breadcrumb rendering and
  recursive deletes bounded.

### StoredFile

Metadata for one uploaded file. Size and content type are denormalised off the
Active Storage blob so that listings, search and the dashboard never join the
`active_storage_*` tables. The display name is the sanitised form of whatever
the client sent, and it is re-sanitised on every save, so a rename cannot
smuggle a path in either.

### ShareLink

Polymorphic, pointing at either a `StoredFile` or a `Folder`. Carries an
unguessable token, and optionally an expiry, a download limit and a password
digest. `ShareLink#contains?` is the single gate that every public request goes
through: it decides whether a given record is inside what was actually shared.
Concentrating that decision in one method is what makes the traversal
protection auditable.

### Download

One row per download, linked to the file and to either the account or the share
link that fetched it. This is what feeds "last downloaded", the per-file
history, the dashboard and the administration statistics.

## Soft delete

Files and folders carry a `deleted_at`. Deleting a folder stamps the same
timestamp on the folder, every descendant folder and every file inside them, in
one transaction. Restoring reverses exactly that set, by matching the
timestamp — so an item that was already in the trash beforehand stays there.

If a restored item's parent is still in the trash, it comes back to the root
rather than into an unreachable place. That keeps restore total: it always
succeeds and never strands data.

`bin/rails portal:purge_trash` removes items deleted longer ago than
`TRASH_RETENTION_DAYS`, for operators who want the trash to drain by itself.

## Serving files

Active Storage's own routes are **disabled** (`config.active_storage.draw_routes
= false`). Every byte leaves through one of two controllers:

- `FileTransfersController` — the owner downloading or previewing their own file
- `Public::DownloadsController` — a recipient using a share link

Both include `BlobStreaming`, which pulls in `ActionController::Live` and
streams the blob in chunks, so memory stays flat regardless of file size. They
are separate from the controllers that render HTML precisely because `Live`
runs every action of its controller in its own thread, and only the actions
that move bytes need that.

The consequence that matters: there is no URL anywhere that serves a file
without first checking ownership or share link validity, and no storage path or
object key ever reaches a client.

## Authorisation

There is no policy layer. Instead, every lookup starts from the signed-in
user's own associations:

```ruby
current_user.stored_files.kept.find(params[:id])
```

A record belonging to somebody else raises `RecordNotFound` and is answered
with a 404. It is never loaded and then rejected, which means an authorisation
bug has to be an omission of the whole query rather than a subtle mistake in a
condition. It also avoids confirming that a record exists.

The one place that needs more than scoping is the administration area, gated by
a single `before_action` on `Admin::BaseController`.

## Request pipeline

1. **Rack::Attack** throttles by IP and, for authentication endpoints, by the
   targeted account.
2. **`ApplicationController`** resolves the session from the signed cookie,
   rejects it if the account has been disabled, and sets `Current`.
3. The controller loads records through the owner's associations.
4. Responses carry the security headers and a Content Security Policy with a
   fresh per-response nonce.

## Configuration

Everything comes from the environment, read once at boot into
`Rails.application.config.x.portal`. Rails credentials are not used at all: an
encrypted file whose key is not shared is useless to a self-hoster, and the
brief called for environment variables. `.env.example` is the authoritative
list.

## Front-end

Server-rendered ERB with Turbo Drive for navigation. Two small Stimulus
controllers cover the only genuinely interactive bits: summarising the files
picked in the upload form, and copying a share URL to the clipboard. Tailwind
provides the styling, with a short component layer in
`app/assets/tailwind/application.css` so templates stay readable.

There is no JavaScript build step. Import maps serve the modules directly, which
is one less toolchain to keep working.

## Scaling

The default is a single Puma process with several threads. That keeps the
in-memory rate limit counters shared and accurate without another service.

To scale beyond one process, set `REDIS_URL` and raise `WEB_CONCURRENCY`. The
cache store switches to Redis automatically, so throttling stays exact across
workers and containers. Storage should move to S3 at that point, since a local
disk is not shared between containers.
