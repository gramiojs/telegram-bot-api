#!/bin/sh
# GramIO — Telegram Bot API server entrypoint.
# Maps TELEGRAM_* environment variables to telegram-bot-api CLI flags,
# supports Docker/K8s secrets via *_FILE, then execs the server as PID 1's child.
set -eu

COMMAND="telegram-bot-api"

# --- helpers ---------------------------------------------------------------

# file_env VAR — allow "VAR" or "VAR_FILE" (read from a file, e.g. a Docker secret).
file_env() {
	var="$1"
	file_var="${var}_FILE"
	val_var="$(eval printf '%s' "\"\${$var:-}\"")"
	val_file="$(eval printf '%s' "\"\${$file_var:-}\"")"

	if [ -n "$val_var" ] && [ -n "$val_file" ]; then
		echo "error: both $var and $file_var are set — use only one." >&2
		exit 1
	fi

	if [ -n "$val_file" ]; then
		val_var="$(cat "$val_file")"
	fi

	export "$var"="$val_var"
	unset "$file_var" 2>/dev/null || true
}

require_env() {
	val="$(eval printf '%s' "\"\${$1:-}\"")"
	if [ -z "$val" ]; then
		echo "error: $1 is required." >&2
		echo "       Obtain api_id / api_hash at https://my.telegram.org and set" >&2
		echo "       TELEGRAM_API_ID and TELEGRAM_API_HASH (or *_FILE)." >&2
		exit 1
	fi
}

# append "--flag=value" when the env var is non-empty (with optional default).
arg_from_env() {
	flag="$1"
	val="$(eval printf '%s' "\"\${$2:-}\"")"
	default="${3:-}"
	[ -z "$val" ] && val="$default"
	if [ -n "$val" ]; then
		COMMAND="$COMMAND --$flag=$val"
	fi
	return 0
}

# --- secrets ---------------------------------------------------------------

file_env TELEGRAM_API_ID
file_env TELEGRAM_API_HASH
require_env TELEGRAM_API_ID
require_env TELEGRAM_API_HASH

# --- flags -----------------------------------------------------------------

arg_from_env api-id   TELEGRAM_API_ID
arg_from_env api-hash TELEGRAM_API_HASH

arg_from_env dir       TELEGRAM_WORK_DIR "/var/lib/telegram-bot-api"
arg_from_env temp-dir  TELEGRAM_TEMP_DIR "/tmp/telegram-bot-api"
arg_from_env http-port      TELEGRAM_HTTP_PORT "8081"
# stat port is always on — the container HEALTHCHECK depends on it.
arg_from_env http-stat-port TELEGRAM_STAT_PORT "8082"

# Local mode is ON by default — it is the reason to self-host
# (2 GB uploads, unlimited downloads, file:// uploads, local getFile paths).
# Set TELEGRAM_LOCAL=0 to keep the cloud-style URL download flow.
if [ "${TELEGRAM_LOCAL:-1}" != "0" ]; then
	COMMAND="$COMMAND --local"
	echo "telegram-bot-api: --local enabled. getFile returns absolute paths — see" >&2
	echo "  https://gramio.dev/bot-api/local#downloading-files for how to serve them." >&2
fi

# every remaining telegram-bot-api option, mapped 1:1 from TELEGRAM_<UPPER_SNAKE>
arg_from_env filter                   TELEGRAM_FILTER
arg_from_env max-webhook-connections  TELEGRAM_MAX_WEBHOOK_CONNECTIONS
arg_from_env max-connections          TELEGRAM_MAX_CONNECTIONS
arg_from_env http-ip-address          TELEGRAM_HTTP_IP_ADDRESS
arg_from_env http-stat-ip-address     TELEGRAM_HTTP_STAT_IP_ADDRESS
arg_from_env log                      TELEGRAM_LOG_FILE
arg_from_env log-max-file-size        TELEGRAM_LOG_MAX_FILE_SIZE
arg_from_env verbosity                TELEGRAM_VERBOSITY
arg_from_env memory-verbosity         TELEGRAM_MEMORY_VERBOSITY
arg_from_env username                 TELEGRAM_USERNAME
arg_from_env groupname                TELEGRAM_GROUPNAME
arg_from_env cpu-affinity             TELEGRAM_CPU_AFFINITY
arg_from_env main-thread-affinity     TELEGRAM_MAIN_THREAD_AFFINITY
arg_from_env proxy                    TELEGRAM_PROXY

# any extra args passed to the container are appended verbatim
COMMAND="$COMMAND $*"

# log the command with secrets masked
echo "telegram-bot-api: starting" >&2
echo "$COMMAND" | sed -E 's/(--api-(id|hash)=)[^ ]+/\1***/g' >&2

# shellcheck disable=SC2086
exec $COMMAND
