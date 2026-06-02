#!/bin/sh
# Integration test for the nginx file-serving design (nginx/telegram-files.conf).
# Proves a file in the working dir is served over HTTP at a path-based, token-less
# URL — exactly what the bot's prefix-swap produces. Needs Docker; no Telegram
# credentials required.
#
#   sh tests/fileserving.test.sh
set -u

if ! docker info >/dev/null 2>&1; then
	echo "SKIP - Docker not available"
	exit 0
fi

HERE=$(cd -- "$(dirname -- "$0")/.." && pwd)
CONF="$HERE/nginx/telegram-files.conf"
WORK=$(mktemp -d)
NAME="tbapi-fileserving-test-$$"
PORT=18080

cleanup() {
	docker rm -f "$NAME" >/dev/null 2>&1 || true
	rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

# Plant a file the way the local server lays them out: <bot_id>/<type>/<name>
mkdir -p "$WORK/123456/documents"
CONTENT="hello from the local bot api server"
printf '%s' "$CONTENT" > "$WORK/123456/documents/report.txt"

docker run -d --name "$NAME" -p "$PORT:80" \
	-v "$WORK:/var/lib/telegram-bot-api:ro" \
	-v "$CONF:/etc/nginx/conf.d/default.conf:ro" \
	nginx:alpine >/dev/null

# wait for nginx
i=0
while [ "$i" -lt 30 ]; do
	if curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then break; fi
	i=$((i + 1)); sleep 1
done

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }

# the path-based URL the bot builds from file_path (no bot token anywhere)
URL="http://127.0.0.1:$PORT/123456/documents/report.txt"

if [ "$(curl -fsS "$URL")" = "$CONTENT" ]; then
	ok "serves the planted file at its path-based URL"
else
	no "serves the planted file at its path-based URL"
fi

case "$URL" in
	*bot[0-9]*|*"$(printf '\072')token"*) no "URL must not contain a bot token" ;;
	*) ok "URL contains no bot token" ;;
esac

# range requests (resumable large downloads)
if curl -fsS -r 0-4 "$URL" | grep -q "hello"; then
	ok "supports HTTP range requests"
else
	no "supports HTTP range requests"
fi

# path traversal must not escape the root
CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/../../etc/passwd")
case "$CODE" in
	2*) no "rejects path traversal (got $CODE)" ;;
	*) ok "does not serve files outside the working dir" ;;
esac

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
