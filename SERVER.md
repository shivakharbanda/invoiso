# invoiso server

The desktop app (Windows/Linux) keeps its data on an invoiso server — a small
Dart API in `server/` backed by Postgres (one schema per company). The app's
login screen has a **Server** button to set the server address.

## Layout

| Path | What |
|---|---|
| `packages/invoiso_core` | Pure-Dart data layer shared by app and server (models, SQL services, repositories, generated RPC client/handlers) |
| `packages/invoiso_pg` | Runs the core services on Postgres (SQL dialect translation, schema sync, SQLite import) |
| `server/` | HTTP API (`shelf`); built by the root `Dockerfile` |
| `tool/gen_rpc.py` | Regenerates `packages/invoiso_core/lib/rpc/*.g.dart` — run after changing any repository interface |

## Run locally (docker compose)

```sh
cp .env.example .env      # set POSTGRES_PASSWORD, TOKEN_SECRET (openssl rand -hex 32)
docker compose up -d --build
```

The API is on `http://<machine>:8080`. On first start a company is created
with user `admin` and `INITIAL_ADMIN_PASSWORD` (or a random password printed
once in `docker compose logs server`).

## Deploy on Railway

1. New project → add a **Postgres** service.
2. Add a service from this GitHub repo. `railway.toml` makes Railway build
   the root `Dockerfile` and health-check `/health`.
3. Variables on the server service:
   - `DATABASE_URL` = `${{Postgres.DATABASE_URL}}?sslmode=disable` (private network)
   - `TOKEN_SECRET` = 32+ random characters
   - `INITIAL_ADMIN_PASSWORD` = first admin password (optional)
4. Generate a public domain for the server service and enter it in the app
   (login screen → Server).
5. Enable backups on the Postgres service.

## Moving desktop data to the server

In the app: Settings → **Server & data** → upload the old `invoice_manager*.db`
(found automatically on that computer). It becomes a new company; users and
passwords come with it.

## Development

```sh
# local Postgres for tests
docker run -d --name invoiso-pg -e POSTGRES_PASSWORD=invoiso -e POSTGRES_DB=invoiso \
  -p 127.0.0.1:55432:5432 postgres:16
cd packages/invoiso_pg && dart test   # SQLite vs Postgres vs RPC parity + spend maths
flutter test                          # app tests
```

Build the original offline (local SQLite) app with
`flutter build windows --dart-define=LOCAL_MODE=true`.
