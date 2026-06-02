# `gramiojs/telegram-bot-api`

A best-in-class Docker image of the [Telegram Bot API server](https://github.com/tdlib/telegram-bot-api), maintained by [GramIO](https://gramio.dev).

- 🐳 **Multi-arch** — `linux/amd64` + `linux/arm64`, built on native runners.
- 🪶 **Small** — Alpine multi-stage build (~50 MB).
- 🔒 **Secure by default** — non-root, `tini` init, healthcheck, signed with [cosign](https://github.com/sigstore/cosign), ships SBOM + build provenance.
- 🔁 **Auto-updating** — rebuilt automatically when a new `tdlib/telegram-bot-api` commit lands.
- 🔑 **Docker/K8s secrets** — `TELEGRAM_API_ID_FILE` / `TELEGRAM_API_HASH_FILE`.

> Why self-host? 2 GB uploads (vs 50 MB), unlimited downloads (vs 20 MB), `file://` local uploads, HTTP webhooks on any port. See the [GramIO guide](https://gramio.dev/bot-api/local).

## Images

| Registry | Reference |
| --- | --- |
| GHCR | `ghcr.io/gramiojs/telegram-bot-api:latest` |
| Docker Hub | `gramiojs/telegram-bot-api:latest` |

| Tag | Description |
| --- | --- |
| `latest`, `alpine` | latest build (Alpine, ~50 MB) |
| `sha-<short>` | pinned to an upstream commit |

## Quick start

```sh
docker run -d --name telegram-bot-api \
  -e TELEGRAM_API_ID=123456 \
  -e TELEGRAM_API_HASH=your_api_hash \
  -p 8081:8081 \
  -v telegram-bot-api-data:/var/lib/telegram-bot-api \
  ghcr.io/gramiojs/telegram-bot-api:latest
```

Get `api_id` / `api_hash` at <https://my.telegram.org>. **Log out of the cloud API first** (`bot.api.logOut()`) before pointing a bot at a local server.

Then point GramIO at it (note the required `/bot` suffix):

```ts
import { Bot } from "gramio";

const bot = new Bot(process.env.BOT_TOKEN, {
  api: { baseURL: "http://localhost:8081/bot" },
});
```

## Compose

```sh
cp .env.example .env   # fill in TELEGRAM_API_ID / TELEGRAM_API_HASH / BOT_TOKEN
docker compose -f docker-compose.example.yml up -d
```

### Downloading files (when bot and server don't share a disk)

In `--local` mode `getFile` returns an **absolute path on the server's disk**, not a URL. If your bot can't read that disk, let this image serve the files for you.

**Easiest — bundled file server (`FILE_SERVER=1`):** one container does both the Bot API and downloads. nginx serves the working dir over HTTP at **token-less, path-based** URLs (`http://host:8080/<bot_id>/documents/file.jpg`). Off by default, one flag to enable — ideal for Coolify/Dokploy/Railway where you deploy a single image:

```sh
docker run -d \
  -e TELEGRAM_API_ID=… -e TELEGRAM_API_HASH=… \
  -e FILE_SERVER=1 \
  -p 8081:8081 -p 8080:8080 \
  -v telegram-bot-api-data:/var/lib/telegram-bot-api \
  ghcr.io/gramiojs/telegram-bot-api:latest
```

Then in the bot, build the download URL by swapping the working-dir prefix for `http://host:8080`. (Separate nginx sidecar — `docker-compose.nginx.yml` — also available if you prefer one process per container.)

See the [GramIO guide → Downloading files](https://gramio.dev/bot-api/local#downloading-files).

## Environment variables

| Variable | Default | Flag |
| --- | --- | --- |
| `TELEGRAM_API_ID` *(required)* | — | `--api-id` |
| `TELEGRAM_API_HASH` *(required)* | — | `--api-hash` |
| `TELEGRAM_LOCAL` | `1` | `--local` (set `0` to disable) |
| `FILE_SERVER` | `0` | bundled nginx file server (`1` to enable) |
| `FILE_SERVER_PORT` | `8080` | port for the bundled file server |
| `TELEGRAM_WORK_DIR` | `/var/lib/telegram-bot-api` | `--dir` |
| `TELEGRAM_TEMP_DIR` | `/tmp/telegram-bot-api` | `--temp-dir` |
| `TELEGRAM_HTTP_PORT` | `8081` | `--http-port` |
| `TELEGRAM_STAT_PORT` | `8082` | `--http-stat-port` |
| `TELEGRAM_FILTER` | — | `--filter` |
| `TELEGRAM_MAX_WEBHOOK_CONNECTIONS` | — | `--max-webhook-connections` |
| `TELEGRAM_MAX_CONNECTIONS` | — | `--max-connections` |
| `TELEGRAM_HTTP_IP_ADDRESS` | — | `--http-ip-address` |
| `TELEGRAM_HTTP_STAT_IP_ADDRESS` | — | `--http-stat-ip-address` |
| `TELEGRAM_LOG_FILE` | — | `--log` |
| `TELEGRAM_LOG_MAX_FILE_SIZE` | — | `--log-max-file-size` |
| `TELEGRAM_VERBOSITY` | — | `--verbosity` |
| `TELEGRAM_MEMORY_VERBOSITY` | — | `--memory-verbosity` |
| `TELEGRAM_USERNAME` | — | `--username` |
| `TELEGRAM_GROUPNAME` | — | `--groupname` |
| `TELEGRAM_CPU_AFFINITY` | — | `--cpu-affinity` |
| `TELEGRAM_MAIN_THREAD_AFFINITY` | — | `--main-thread-affinity` |
| `TELEGRAM_PROXY` | — | `--proxy` |

Every `telegram-bot-api` option is exposed (each `--some-option` maps to `TELEGRAM_SOME_OPTION`). Any extra arguments passed to the container are also appended verbatim.

`TELEGRAM_API_ID` / `TELEGRAM_API_HASH` also accept a `_FILE` suffix to read the value from a file (Docker/K8s secrets).

## Verifying the image

```sh
cosign verify ghcr.io/gramiojs/telegram-bot-api:latest \
  --certificate-identity-regexp "https://github.com/gramiojs/telegram-bot-api/.*" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

docker buildx imagetools inspect ghcr.io/gramiojs/telegram-bot-api:latest
```

## Development

The entrypoint logic is covered by a dependency-free POSIX-sh test suite (a stub `telegram-bot-api` on `PATH` lets it assert how env vars become CLI flags):

```sh
sh tests/entrypoint.test.sh   # + shellcheck in CI (.github/workflows/test.yml)
```

## License

MIT for the image tooling; the bundled `telegram-bot-api` binary is under the Boost Software License 1.0. See [LICENSE](./LICENSE).
