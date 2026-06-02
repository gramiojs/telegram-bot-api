#!/bin/sh
# Tests for docker-entrypoint.sh — pure POSIX sh, no Docker required.
#
#   sh tests/entrypoint.test.sh
#
# A stub `telegram-bot-api` on PATH prints its argv as "ARGS: ..." so we can
# assert how environment variables are translated into CLI flags.
set -u

HERE=$(cd -- "$(dirname -- "$0")/.." && pwd)
ENTRY="$HERE/docker-entrypoint.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# stub binary: echo argv, so `exec telegram-bot-api ...` is observable
printf '#!/bin/sh\necho "ARGS: $*"\n' > "$WORK/telegram-bot-api"
chmod +x "$WORK/telegram-bot-api"
PATH="$WORK:$PATH"
export PATH

PASS=0
FAIL=0

# run <description>; caller exports env beforehand and passes args after `--`
# captures stdout -> $WORK/out, stderr -> $WORK/err, exit code -> $CODE
run() {
	sh "$ENTRY" "$@" > "$WORK/out" 2> "$WORK/err"
	CODE=$?
}

assert_code() { # want desc
	if [ "$CODE" -eq "$1" ]; then
		PASS=$((PASS + 1)); printf 'ok   - %s\n' "$2"
	else
		FAIL=$((FAIL + 1)); printf 'FAIL - %s (exit %s, wanted %s)\n' "$2" "$CODE" "$1"
	fi
}

assert_out() { # pattern desc  (stdout = the exec'd command's argv)
	if grep -q -- "$1" "$WORK/out"; then
		PASS=$((PASS + 1)); printf 'ok   - %s\n' "$2"
	else
		FAIL=$((FAIL + 1)); printf 'FAIL - %s (stdout missing: %s)\n' "$2" "$1"
		sed 's/^/       out> /' "$WORK/out"
	fi
}

refute_out() { # pattern desc
	if grep -q -- "$1" "$WORK/out"; then
		FAIL=$((FAIL + 1)); printf 'FAIL - %s (stdout unexpectedly has: %s)\n' "$2" "$1"
	else
		PASS=$((PASS + 1)); printf 'ok   - %s\n' "$2"
	fi
}

assert_err() { # pattern desc
	if grep -q -- "$1" "$WORK/err"; then
		PASS=$((PASS + 1)); printf 'ok   - %s\n' "$2"
	else
		FAIL=$((FAIL + 1)); printf 'FAIL - %s (stderr missing: %s)\n' "$2" "$1"
	fi
}

# --- missing credentials -----------------------------------------------------
unset TELEGRAM_API_ID TELEGRAM_API_HASH TELEGRAM_API_HASH_FILE TELEGRAM_LOCAL
run
assert_code 1 "missing credentials exits non-zero"
assert_err "TELEGRAM_API_ID is required" "missing credentials reports a clear error"

# --- happy path --------------------------------------------------------------
export TELEGRAM_API_ID=123 TELEGRAM_API_HASH=abc
run --foo=bar
assert_code 0 "valid credentials start the server"
assert_out "ARGS: " "server is exec'd"
assert_out "--api-id=123" "maps TELEGRAM_API_ID"
assert_out "--api-hash=abc" "maps TELEGRAM_API_HASH"
assert_out "--http-stat-port=8082" "stat port always set (healthcheck depends on it)"
assert_out "--local" "local mode on by default"
assert_out "--foo=bar" "extra args are passed through"

# regression: an unset optional var must NOT abort the script under `set -e`
unset TELEGRAM_MAX_CONNECTIONS
run
assert_code 0 "empty optional var does not abort startup (set -e regression)"
assert_out "ARGS: " "reaches exec with optional vars unset"

# --- optional flags ----------------------------------------------------------
export TELEGRAM_MAX_CONNECTIONS=100 TELEGRAM_MEMORY_VERBOSITY=2 \
	TELEGRAM_HTTP_STAT_IP_ADDRESS=127.0.0.1 TELEGRAM_LOG_MAX_FILE_SIZE=1000000
run
assert_out "--max-connections=100" "maps TELEGRAM_MAX_CONNECTIONS"
assert_out "--memory-verbosity=2" "maps TELEGRAM_MEMORY_VERBOSITY"
assert_out "--http-stat-ip-address=127.0.0.1" "maps TELEGRAM_HTTP_STAT_IP_ADDRESS"
assert_out "--log-max-file-size=1000000" "maps TELEGRAM_LOG_MAX_FILE_SIZE"
unset TELEGRAM_MAX_CONNECTIONS TELEGRAM_MEMORY_VERBOSITY \
	TELEGRAM_HTTP_STAT_IP_ADDRESS TELEGRAM_LOG_MAX_FILE_SIZE

# --- local mode toggle -------------------------------------------------------
export TELEGRAM_LOCAL=0
run
refute_out "--local" "TELEGRAM_LOCAL=0 disables --local"
unset TELEGRAM_LOCAL

# --- secret via _FILE --------------------------------------------------------
unset TELEGRAM_API_HASH
printf 'hash_from_file' > "$WORK/hash.txt"
export TELEGRAM_API_HASH_FILE="$WORK/hash.txt"
run
assert_code 0 "_FILE secret is accepted"
assert_out "--api-hash=hash_from_file" "reads secret from *_FILE"

# both var and _FILE set is an error
export TELEGRAM_API_HASH=abc
run
assert_code 1 "both TELEGRAM_API_HASH and _FILE is rejected"
assert_err "use only one" "explains the both-set conflict"
unset TELEGRAM_API_HASH_FILE

# --- secret masking ----------------------------------------------------------
export TELEGRAM_API_HASH=supersecret
run
assert_err "--api-hash=\*\*\*" "logged command masks the api hash"
if grep -q "supersecret" "$WORK/err"; then
	FAIL=$((FAIL + 1)); printf 'FAIL - secret is not leaked to logs\n'
else
	PASS=$((PASS + 1)); printf 'ok   - secret is not leaked to logs\n'
fi
unset TELEGRAM_API_HASH

# --- bundled file server (FILE_SERVER) ---------------------------------------
# stub nginx so the entrypoint's `nginx -c ... &` is observable
printf '#!/bin/sh\necho "NGINX $*" >> "%s/nginx.log"\n' "$WORK" > "$WORK/nginx"
chmod +x "$WORK/nginx"

export TELEGRAM_API_HASH=abc
# default OFF: nginx must not be invoked
rm -f "$WORK/nginx.log"
run
if [ -f "$WORK/nginx.log" ]; then
	FAIL=$((FAIL + 1)); printf 'FAIL - FILE_SERVER off by default (nginx should not start)\n'
else
	PASS=$((PASS + 1)); printf 'ok   - FILE_SERVER off by default (nginx not started)\n'
fi

# ON: nginx started, config generated, server still exec'd
rm -f "$WORK/nginx.log" /tmp/nginx/nginx.conf
export FILE_SERVER=1 FILE_SERVER_PORT=9090
run
assert_code 0 "FILE_SERVER=1 still starts the server"
assert_out "ARGS: " "server is exec'd alongside nginx"
sleep 1 # nginx is backgrounded; give the stub a moment to write its marker
if [ -f "$WORK/nginx.log" ]; then
	PASS=$((PASS + 1)); printf 'ok   - nginx started when FILE_SERVER=1\n'
else
	FAIL=$((FAIL + 1)); printf 'FAIL - nginx started when FILE_SERVER=1\n'
fi
if grep -q "listen 9090;" /tmp/nginx/nginx.conf 2>/dev/null; then
	PASS=$((PASS + 1)); printf 'ok   - nginx config honors FILE_SERVER_PORT\n'
else
	FAIL=$((FAIL + 1)); printf 'FAIL - nginx config honors FILE_SERVER_PORT\n'
fi
unset FILE_SERVER FILE_SERVER_PORT

# --- summary -----------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
