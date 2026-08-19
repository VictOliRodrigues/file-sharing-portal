# Security policy

## Supported versions

This project is developed on the `main` branch. Security fixes land there
first, and only the latest release is supported. If you are running an older
build, upgrade before reporting an issue.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub's
[private vulnerability reporting](https://github.com/VictOliRodrigues/file-sharing-portal/security/advisories/new)
on this repository. If that is unavailable to you, open a regular issue that
says only that you have found a security problem and asks for a private
channel — no details.

Please include:

- What the problem is and why it matters
- The steps needed to reproduce it, ideally with a minimal example
- The version or commit you tested, and how the deployment was configured
- Any suggested fix, if you have one

### What to expect

- An acknowledgement within **3 working days**
- An initial assessment, with a severity judgement, within **7 working days**
- Regular updates until the issue is resolved
- Credit in the release notes, unless you prefer to stay anonymous

Please give us a reasonable window to ship a fix before disclosing publicly.
Ninety days is the usual expectation, shorter if the issue is already being
exploited.

## Scope

In scope:

- Authentication and session handling
- Authorisation between accounts, including anything reachable through a share
  link
- Share link tokens, expiry, download limits and password protection
- File upload, storage and download paths, including filename handling
- Injection of any kind, cross-site scripting, cross-site request forgery
- Privilege escalation into the administration area
- Anything that exposes storage paths, object keys or another account's data

Out of scope:

- Vulnerabilities that require an attacker to already have administrator
  access, since administrators are trusted by design
- Missing hardening on a deployment that has deliberately turned protections
  off, for example `FORCE_SSL=false` or `RATE_LIMIT_ENABLED=false`
- Denial of service through sheer volume; rate limits are tunable and the
  reverse proxy is expected to help
- Findings from automated scanners with no demonstrated impact
- Social engineering, physical access, or issues in third-party services

## For operators

A deployment is only as safe as its configuration. The checklist that matters
most:

- Set a strong, unique `SECRET_KEY_BASE`. Rotating it invalidates every session
  and password reset link.
- Keep `FORCE_SSL=true` and terminate TLS in front of the application.
- Set `ALLOWED_HOSTS` to the hostnames you actually serve.
- Set `ALLOW_REGISTRATION=false` unless you really want anybody to sign up.
- Keep `RATE_LIMIT_ENABLED=true`. If you run more than one worker or container,
  set `REDIS_URL` so the limits are shared and therefore accurate.
- Back up both the database and the file storage. One without the other is not
  a backup.
- Never commit `.env`.

The reasoning behind the application's own defences, and the trade-offs that
were deliberately accepted, is documented in [docs/security.md](docs/security.md).
