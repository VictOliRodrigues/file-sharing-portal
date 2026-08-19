# Security

This document describes the threats the portal is designed to resist, the
mechanism used against each one, where it lives in the code, and the trade-offs
that were deliberately accepted.

To report a vulnerability, see [SECURITY.md](../SECURITY.md).

## Threat model

The portal is a multi-tenant file store with a public sharing surface. The
attackers worth designing against are:

1. **An anonymous visitor** who can reach the sign in page and any share link
   URL they can find or guess.
2. **A recipient of one share link** who tries to reach anything beyond what
   was actually shared.
3. **A signed-in account holder** who tries to reach another account's files.
4. **A signed-in account holder** who tries to reach the administration area.

Administrators are trusted. They can see usage statistics and delete accounts
by design, so "an administrator can see how much storage a user has" is not a
vulnerability.

## Authentication

**Passwords** are hashed with bcrypt through `has_secure_password`, so the
cost factor and salting come from a maintained implementation rather than
anything hand-rolled. The minimum length is 12 characters; there are no
composition rules, because they mostly push people towards predictable
patterns.

**Sessions** are rows in the `sessions` table. The browser holds only the row's
id, in a cookie that is signed, `HttpOnly`, `SameSite=Lax`, and `Secure`
whenever the request arrived over HTTPS. Every request looks the row up again
(`Authentication#find_session_by_cookie`), which is what makes revocation
immediate:

- signing out destroys the row
- disabling an account destroys all of its rows, inside the same transaction
  that sets `disabled_at`
- changing a password destroys every row except the current one
- resetting a password destroys all of them

**Session fixation** is handled by `reset_session` before a new session is
created on sign in, so the pre-authentication session identifier is never
reused.

**Account enumeration** is avoided by making the responses identical whichever
way they fail. A wrong password and an unknown address produce the same message.
A password reset request produces the same confirmation whether or not the
address is registered, and no email is sent for an unknown or disabled account.
The only place the portal is specific is when a *correct* password is supplied
for a disabled account — at that point the requester has proved they own it.

**Password reset tokens** come from `generates_token_for`, keyed on the
password digest. A token therefore stops working the moment the password
changes, which makes it single-use in practice, and it expires after 30 minutes
regardless.

## Authorisation

There is no policy layer. Every lookup begins at the signed-in user's own
associations:

```ruby
current_user.stored_files.kept.find(params[:id])
current_user.folders.kept.find(params[:id])
current_user.share_links.find_by!(token: params[:id])
```

A record owned by somebody else raises `RecordNotFound` and is answered with a
404. It is never loaded and then rejected. This matters for two reasons: an
authorisation bug has to be an omission of the entire query rather than a
subtle mistake in a condition, and the response does not confirm that the
record exists.

Cross-account access is covered by
`test/integration/file_authorization_test.rb` and by the ownership tests in the
folder, share link and admin suites.

The administration area is the only place that needs more, and it is gated by a
single `before_action :require_administrator` on `Admin::BaseController`.

**Mass assignment** is constrained everywhere it matters. Registration and the
profile form cannot set `admin` or `disabled_at`. The administration form can
set only `admin` and `storage_quota_bytes` — an administrator cannot change
another person's password, name or address. Renaming a file permits only
`:name` and `:folder_id`, and a `folder_id` outside the owner's tree fails
validation.

## File handling

**Filenames are never trusted.** `SafeFilename` strips directory components
(both `/` and `\`), removes control characters and null bytes, replaces
characters that are unsafe in paths or in headers, rejects names made only of
dots, collapses whitespace and truncates to 180 characters while keeping the
extension. It runs on upload *and* on every save, so a rename cannot smuggle a
path in either.

Active Storage applies its own sanitisation first, which already removes `/`
and a handful of other characters. `SafeFilename` is a second, independent
layer, and it is the only one that covers the rename path, where the name
arrives straight from a form.

**Storage keys are never derived from user input.** Active Storage generates
them, so there is no path for a filename to influence where bytes land on disk
or in a bucket. Traversal attempts are covered by
`test/models/safe_filename_test.rb` and exercised end to end in
`test/integration/file_upload_test.rb`.

**Content types come from the bytes**, not from the client. Active Storage
sniffs the first few kilobytes with Marcel and that is what gets stored. A file
declared as `text/html` but containing a PDF is recorded as a PDF, and the
reverse also holds.

**Size and quota** are enforced before anything is written. Validation runs on
an unsaved record, so an oversized upload never reaches storage at all.
`MAX_UPLOAD_SIZE_MB` bounds a single file and `DEFAULT_STORAGE_QUOTA_MB` (or a
per-account override) bounds the total.

**Type policy** is configurable through `UPLOAD_ALLOWED_EXTENSIONS` and
`UPLOAD_BLOCKED_EXTENSIONS`. Both default to empty, because a general purpose
file portal has to accept arbitrary files. This is an operator policy control,
not a security control — the security comes from never executing an upload and
never serving one as an active document.

## Serving files

This is the part most likely to go wrong in a file sharing application, so it
is deliberately narrow.

**Active Storage's routes are disabled** (`config.active_storage.draw_routes =
false`). There is no `/rails/active_storage/...` endpoint at all, which is
asserted by a test. Without that, anybody holding a signed blob id could
download the bytes, bypassing ownership checks, share link expiry and download
accounting.

**Every byte goes through a controller** — `FileTransfersController` for owners
and `Public::DownloadsController` for share links. Both resolve the record
through the owner's associations or through the share link before streaming
anything. Storage paths, object keys and signed blob ids never reach a client.

**Downloads are always attachments.** `Content-Disposition: attachment` is set
for everything except a short allowlist of raster image types
(`image/png`, `image/jpeg`, `image/gif`, `image/webp`) used for previews.

**Dangerous types are downgraded.** `text/html`, `image/svg+xml`, XML and
JavaScript are served as `application/octet-stream` regardless, so that a
browser tricked into rendering one cannot execute it on the application's own
origin. Combined with `X-Content-Type-Options: nosniff`, this closes the stored
XSS path that uploading an HTML file would otherwise open.

**Streaming** keeps memory flat regardless of file size, and means a large
upload cannot be used to exhaust the process.

## Share links

A share link is a bearer credential: whoever holds the URL can use it. That is
the point, so the design focuses on making the token unguessable and on
bounding what it reaches.

**Tokens** are 48 base58 characters from `generate_unique_secure_token`, well
over 200 bits of entropy, with a unique index. Links are addressed by token
everywhere, never by database id.

**Containment** is the important part. `ShareLink#contains?` is the single gate
every public request goes through. It rejects a record that:

- is `nil`
- has been moved to the trash
- belongs to a different account than the link's creator
- for a file share, is not exactly the shared file
- for a folder share, is not inside the shared folder's subtree

The subtree is resolved with a recursive CTE scoped to the owner. A folder link
therefore cannot be walked upwards into a parent, sideways into a sibling, or
across into another account. Breadcrumbs are trimmed at the shared root, so a
recipient does not even learn the names of the folders above it. All of this is
covered by the containment tests in
`test/integration/share_link_test.rb`.

**Restrictions** are optional and combinable: an expiry date, a download limit
and a password. The limit is re-checked immediately before streaming, not only
in the `before_action`, so a concurrent request cannot slip past it.

**Passwords** on links are bcrypt digests. Unlocking stores the link's id in
the visitor's session, so unlocking one link never unlocks another. Guessing is
throttled.

**Unknown, revoked and expired tokens all produce the same 404**, so probing
cannot confirm that a token exists.

**Public pages** are marked `noindex, nofollow, noarchive` and send
`referrer: no-referrer`, so a share URL does not leak through a search engine
or through the `Referer` header of an outbound link.

## Transport and headers

- **HSTS and HTTPS redirect** through `config.force_ssl`, with `/up` exempt so
  health checks work over plain HTTP.
- **Content Security Policy** with `default-src 'self'`, `object-src 'none'`,
  `frame-ancestors 'none'`, `base-uri 'self'` and `form-action 'self'`. No
  `unsafe-inline` and no `unsafe-eval`. Inline scripts and styles are permitted
  only through a nonce that is **regenerated for every response** — the Rails
  default of deriving it from the session id is both empty before a session
  exists and stable for the life of one.
- **`X-Frame-Options: DENY`**, `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: strict-origin-when-cross-origin`,
  `Cross-Origin-Opener-Policy: same-origin`,
  `X-Permitted-Cross-Domain-Policies: none`, and a `Permissions-Policy` that
  turns off every device API.
- **Host authorisation** via `ALLOWED_HOSTS`, which protects against DNS
  rebinding when set.

Asserted by `test/integration/security_headers_test.rb`.

## Cross-site request forgery

Rails' forgery protection is enabled with `protect_from_forgery with:
:exception`, so a failure is visible rather than silently resetting the session.
Per-form tokens are on, which means a token minted for one form cannot be
replayed against a different action. Session cookies are `SameSite=Lax`.

`test/integration/csrf_protection_test.rb` turns protection back on — Rails
disables it in the test environment — and checks that uploads, deletions, sign
in and share link unlocking are all rejected without a valid token.

## Injection

**SQL.** Every query is built with Active Record. The two places that take raw
input handle it explicitly: search terms go through `sanitize_sql_like` before
being interpolated into a `LIKE` pattern, so `%` and `_` are matched literally
rather than as wildcards; and the file type filter is validated against a fixed
list of categories, so an unknown value is ignored rather than trusted. Both
are covered by tests, including one that submits a `DROP TABLE` payload.

**Cross-site scripting.** ERB escapes by default and the templates never call
`html_safe` or `raw` on user data. The Content Security Policy is a second
layer, and the download rules described above close the stored-XSS route that
uploading an HTML file would otherwise open.

**Command injection.** The application shells out to nothing.

## Rate limiting

Rack::Attack throttles:

| Endpoint | Limit |
| --- | --- |
| Sign in, per address | 10 per minute |
| Sign in, per targeted account | 5 per 20 minutes |
| Sign up, per address | 5 per hour |
| Password reset, per address | 5 per hour |
| Password reset, per targeted account | 3 per hour |
| Share link unlock, per address | 10 per 10 minutes |
| Share link access, per address | 60 per minute |
| Everything, per address | `RATE_LIMIT_REQUESTS` per 5 minutes (300 by default) |

Throttling by targeted account as well as by source address is what makes
password spraying — one attempt against each of many accounts, from rotating
addresses — expensive rather than free.

Counters live in the Rails cache. With the default single Puma process that
cache is shared by every thread, so the limits are exact. Running more than one
worker or container without setting `REDIS_URL` would give each process its own
counters and multiply every limit; this is documented in `.env.example`, in the
Puma configuration and in the deployment guide.

The health check and static assets are never throttled. Throttled requests are
logged so an operator can spot abuse.

## Secrets

Nothing is stored in source. Everything comes from the environment, and Rails
credentials are not used at all — an encrypted file whose key is not shared is
useless to a self-hoster. `.env` is git-ignored, excluded from the Docker build
context, and CI fails the build if one is ever committed.

`SECRET_KEY_BASE` must be set in production and must be unique per deployment.
Rotating it invalidates every session, signed cookie and outstanding password
reset link.

Rails' parameter filtering keeps passwords, tokens, secrets and email addresses
out of the logs.

## Container hardening

The production image is a multi-stage build: the compiler toolchain and the
development and test gems stay in the build stage and are not present in the
final image. The application runs as an unprivileged user (uid 1000), and only
`/rails/storage`, `/rails/tmp` and `/rails/log` are writable.

## Accepted trade-offs

These were considered and deliberately left as they are.

**Share links are bearer credentials.** Anyone with the URL can use it. That is
what makes them useful to a recipient without an account. The mitigations are
an unguessable token, optional expiry, optional download limit, optional
password, revocation, `noindex` and `no-referrer`.

**Sequential database ids in authenticated URLs.** `/files/42` is guessable,
but guessing it gains nothing: every lookup is scoped to the owner, so another
account's id returns a 404. Random public identifiers were not worth the extra
complexity given that the genuinely public surface — share links — already uses
random tokens.

**No virus scanning.** Uploads are stored as opaque bytes and never executed.
An integration with ClamAV is on the roadmap for deployments that need it.

**Background jobs run in-process.** The only jobs are Active Storage analysis
and purge. If the process dies at exactly the wrong moment a blob can be
orphaned; `bin/rails portal:purge_orphan_blobs` cleans those up. A durable
queue would have meant another service for very little benefit.

**Trashed files still occupy quota.** Their bytes are still stored, so counting
them is the honest answer. `portal:purge_trash` drains the trash on a schedule.

**Administrators can delete any account and all of its files.** They are
trusted by definition. What they deliberately *cannot* do is change somebody
else's password, which would let them impersonate that person.

## Verifying a deployment

```bash
# Headers and policy
curl -sI https://files.example.com/sign_in | grep -iE 'strict-transport|x-frame|content-security'

# Active Storage routes must not exist
curl -so /dev/null -w '%{http_code}\n' https://files.example.com/rails/active_storage/blobs/redirect/x/y   # 404

# The drive must require authentication
curl -so /dev/null -w '%{http_code}\n' https://files.example.com/files    # 302 to /sign_in

# An unknown share token must be indistinguishable from a revoked one
curl -so /dev/null -w '%{http_code}\n' https://files.example.com/s/nope   # 404
```

And from the source tree:

```bash
bin/rails test
bin/brakeman --no-pager --exit-on-warn
bin/bundler-audit
bin/importmap audit
```
