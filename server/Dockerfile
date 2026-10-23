# invoiso API server. Build context = repository root (the server depends on
# packages/invoiso_core and packages/invoiso_pg):
#   docker build -f server/Dockerfile -t invoiso-server .
# Railway uses this via railway.toml; docker-compose.yml builds it too.

# Dart version matches the Flutter SDK the app is built with (3.32.8).
FROM dart:3.8.1 AS build
WORKDIR /src

# Resolve dependencies first so code edits don't bust the pub cache layer.
COPY packages/invoiso_core/pubspec.yaml packages/invoiso_core/
COPY packages/invoiso_pg/pubspec.yaml packages/invoiso_pg/
COPY server/pubspec.yaml server/pubspec.lock server/
RUN cd server && dart pub get

COPY packages/invoiso_core packages/invoiso_core
COPY packages/invoiso_pg packages/invoiso_pg
COPY server server
RUN mkdir -p /out && cd server && dart pub get --offline \
    && dart compile exe bin/server.dart -o /out/invoiso-server

FROM debian:bookworm-slim
# libsqlite3: the importer reads uploaded desktop .db files and the schema is
# derived from an in-memory SQLite copy at startup.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-dev ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 invoiso
COPY --from=build /out/invoiso-server /app/invoiso-server
USER invoiso
ENV PORT=8080
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD curl -fsS "http://localhost:${PORT}/health" || exit 1
CMD ["/app/invoiso-server"]
