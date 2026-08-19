# File Sharing Portal

A self-hosted file sharing platform built with Ruby on Rails. Upload, organize
and share files from your own server, with public share links that recipients
can use without an account.

> Work in progress. See the roadmap at the bottom of this file.

## Requirements

- Docker and Docker Compose, or
- Ruby 3.4, PostgreSQL 14+ and libvips for a local installation

## Quick start

```bash
cp .env.example .env
docker compose -f docker-compose.dev.yml up --build
```

The application will be available on <http://localhost:3000>.

## License

Released under the [MIT License](LICENSE).
