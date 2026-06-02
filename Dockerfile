# syntax=docker/dockerfile:1
#
# GramIO — Telegram Bot API server image.
# Multi-stage Alpine build from https://github.com/tdlib/telegram-bot-api
#
ARG ALPINE_VERSION=3.21

# ---------------------------------------------------------------------------
# Build stage — clone + compile telegram-bot-api
# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS build
WORKDIR /src
RUN apk add --no-cache \
      alpine-sdk linux-headers git cmake gperf \
      zlib-dev openssl-dev
# CI passes the resolved upstream SHA/tag for reproducible builds.
ARG TELEGRAM_BOT_API_REF=master
RUN git clone --recursive https://github.com/tdlib/telegram-bot-api.git . \
 && git checkout "${TELEGRAM_BOT_API_REF}" \
 && git submodule update --init --recursive
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/out \
 && cmake --build build --target install -j"$(nproc)" \
 && strip /out/bin/telegram-bot-api

# ---------------------------------------------------------------------------
# Runtime stage
# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS alpine
ENV TELEGRAM_WORK_DIR=/var/lib/telegram-bot-api \
    TELEGRAM_TEMP_DIR=/tmp/telegram-bot-api \
    TELEGRAM_HTTP_PORT=8081 \
    TELEGRAM_STAT_PORT=8082
RUN apk add --no-cache openssl libstdc++ curl tini \
 && addgroup -g 101 -S telegram-bot-api \
 && adduser -S -D -H -u 101 -h "$TELEGRAM_WORK_DIR" -s /sbin/nologin \
      -G telegram-bot-api telegram-bot-api
COPY --from=build /out/bin/telegram-bot-api /usr/local/bin/telegram-bot-api
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh \
 && mkdir -p "$TELEGRAM_WORK_DIR" "$TELEGRAM_TEMP_DIR" \
 && chown telegram-bot-api:telegram-bot-api "$TELEGRAM_WORK_DIR" "$TELEGRAM_TEMP_DIR"
USER telegram-bot-api
WORKDIR /var/lib/telegram-bot-api
EXPOSE 8081/tcp 8082/tcp
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${TELEGRAM_STAT_PORT}/" >/dev/null || exit 1
ENTRYPOINT ["/sbin/tini", "--", "/docker-entrypoint.sh"]
