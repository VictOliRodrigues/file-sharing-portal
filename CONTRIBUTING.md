# Contributing

Thanks for taking the time to help. This document covers everything you need to
get a change merged.

## Ground rules

- The whole project is written in **English** — code, interface text,
  documentation, comments and commit messages.
- Follow Rails conventions. When there is an idiomatic Rails way to do
  something, use it.
- Prefer the simple version. Extra layers of indirection need to earn their
  place.
- Anything security-sensitive needs a test that would fail without the fix.

## Getting set up

With Docker, which needs nothing installed beyond Docker itself:

```bash
git clone https://github.com/VictOliRodrigues/file-sharing-portal.git
cd file-sharing-portal
docker compose -f docker-compose.dev.yml up --build
```

Without Docker, you need Ruby 3.4, PostgreSQL 14 or newer and libvips:

```bash
bin/setup
```

See [docs/development.md](docs/development.md) for the details, including how to
run a single test and how to work on the S3 storage path locally.

## Before you open a pull request

Run everything CI runs:

```bash
bin/ci
```

Or the individual checks:

```bash
bin/rails test                                     # tests
bin/rubocop                                        # style
bin/brakeman --no-pager --exit-on-warn             # static security analysis
bin/bundler-audit                                  # gem advisories
bin/importmap audit                                # JavaScript advisories
```

All of them have to pass. `bin/rubocop -a` fixes most style complaints for you.

## Tests

The suite is Minitest, and lives in `test/`:

- `test/models/` — validations, scopes and domain logic
- `test/integration/` — full request cycles, which is where authorisation,
  sharing and security behaviour is covered
- `test/mailers/` — outgoing email

Write the test at the level where the behaviour actually lives. Authorisation
belongs in an integration test, because that is where a real request would be
rejected. Name tests as sentences describing the behaviour, matching the style
already in the files.

If you touch anything under `app/controllers/concerns/`, `app/models/safe_filename.rb`,
`app/models/share_link.rb` or `config/initializers/`, expect to be asked for
tests covering the security implications.

## Commit messages

The project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add resumable uploads
fix: reject share links whose folder was moved to the trash
test: cover folder cycle prevention
docs: explain the S3 endpoint setting
ci: cache gems between workflow runs
refactor: extract the share link containment check
chore: bump the Ruby version
build: keep test gems out of the production image
perf: avoid an N+1 in the file listing
```

Keep the subject line in the imperative mood and under about 72 characters.
Use the body to explain **why**, not what — the diff already says what. Group
related changes into one commit rather than committing every file separately.

## Pull requests

- Branch from `main` and keep the branch focused on one thing.
- Describe what changes and why. If it changes behaviour anybody could notice,
  say so explicitly.
- Update the documentation in the same pull request. A new environment variable
  belongs in `.env.example` and in the README table, in the same change.
- Add a screenshot for anything that alters the interface.

## Reporting bugs

Open an issue with the version or commit, how the deployment is configured
(storage backend, whether it is behind a proxy), what you expected, what
happened, and the steps to reproduce.

For anything security-sensitive, do **not** open a public issue. Follow
[SECURITY.md](SECURITY.md) instead.

## License

By contributing you agree that your work is licensed under the
[MIT License](LICENSE) that covers this project.
