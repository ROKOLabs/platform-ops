#!/bin/sh

# Report a successful deployment to Roko. Reporting is best-effort unless
# --strict is supplied or ROKO_STRICT=1 is set.

log() {
	printf '%s\n' "roko-adapter: $*"
}

strict_exit() {
	code=$1
	if [ "$strict" = "1" ]; then
		exit "$code"
	fi
	exit 0
}

require_value() {
	name=$1
	value=$2
	if [ -z "$value" ]; then
		log "missing $name"
		strict_exit 2
	fi
}

generate_deploy_id() {
	if [ -r /dev/urandom ] && command -v od > /dev/null 2>&1 && command -v tr > /dev/null 2>&1; then
		generated_id=$(od -An -N16 -tx1 /dev/urandom 2> /dev/null | tr -d '[:space:]')
		if [ -n "$generated_id" ]; then
			printf '%s' "$generated_id"
			return
		fi
	fi

	printf '%s-%s-%s' "$sha" "$(date -u +%Y%m%dT%H%M%SZ)" "$$"
}

json_escape() {
	printf '%s' "$1" | awk '
        BEGIN { ORS = ""; first = 1 }
        {
            if (!first) printf "\\n"
            first = 0
            gsub(/\\/, "\\\\")
            gsub(/"/, "\\\"")
            gsub(/\t/, "\\t")
            gsub(/\r/, "\\r")
            printf "%s", $0
        }
    '
}

response_text() {
	response=$(tr '\r\n' '  ' < "$1" 2> /dev/null || true)
	case "$response" in
		*"$token"*) printf '%s' '[redacted]' ;;
		*) printf '%s' "$response" ;;
	esac
}

strict=${ROKO_STRICT:-0}
for argument in "$@"; do
	if [ "$argument" = "--strict" ]; then
		strict=1
	fi
done

url=${ROKO_ENDPOINT_URL:-}
token=${ROKO_DEPLOY_TOKEN:-}
environment=${ROKO_ENVIRONMENT:-}
sha=${ROKO_SHA:-}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--url | --token | --environment)
			option=$1
			if [ "$#" -lt 2 ]; then
				log "missing value for $option"
				strict_exit 2
			fi
			value=$2
			case "$option" in
				--url) url=$value ;;
				--token) token=$value ;;
				--environment) environment=$value ;;
			esac
			shift 2
			;;
		--strict)
			strict=1
			shift
			;;
		*)
			log "unknown option $1"
			strict_exit 2
			;;
	esac
done

require_value url "$url"
require_value token "$token"
require_value environment "$environment"

if [ -z "$sha" ]; then
	sha=$(git rev-parse HEAD 2> /dev/null || true)
fi
if [ -z "$sha" ]; then
	log "missing sha"
	strict_exit 2
fi

if ! command -v curl > /dev/null 2>&1; then
	log "curl is required"
	strict_exit 4
fi

environment_json=$(json_escape "$environment")
sha_json=$(json_escape "$sha")
deploy_id=$(generate_deploy_id)
deploy_id_json=$(json_escape "$deploy_id")
payload=$(printf '{"environment":"%s","sha":"%s","deployId":"%s"}' "$environment_json" "$sha_json" "$deploy_id_json")

response_file=$(mktemp "${TMPDIR:-/tmp}/roko-adapter-response.XXXXXX") || {
	log "could not create a temporary response file"
	strict_exit 3
}
error_file=$(mktemp "${TMPDIR:-/tmp}/roko-adapter-error.XXXXXX") || {
	rm -f "$response_file"
	log "could not create a temporary error file"
	strict_exit 3
}
trap 'rm -f "$response_file" "$error_file"' EXIT HUP INT TERM

attempt=1
while [ "$attempt" -le 5 ]; do
	: > "$response_file"
	: > "$error_file"
	status=$(curl --silent --show-error \
		--connect-timeout 10 \
		--max-time 10 \
		--output "$response_file" \
		--write-out '%{http_code}' \
		--header "Authorization: Bearer $token" \
		--header 'Content-Type: application/json' \
		--data "$payload" \
		"$url" 2> "$error_file")
	curl_exit=$?

	if [ "$curl_exit" -eq 0 ] && [ "$status" -ge 200 ] 2> /dev/null && [ "$status" -lt 300 ] 2> /dev/null; then
		log "reported $sha to $environment"
		exit 0
	fi

	retry=0
	if [ "$curl_exit" -ne 0 ] || [ "$status" = "429" ]; then
		retry=1
	elif [ "$status" -ge 500 ] 2> /dev/null && [ "$status" -lt 600 ] 2> /dev/null; then
		retry=1
	fi

	if [ "$retry" -eq 1 ] && [ "$attempt" -lt 5 ]; then
		if [ "$curl_exit" -ne 0 ]; then
			log "attempt $attempt failed with a network error; retrying"
		else
			log "attempt $attempt failed with HTTP $status; retrying"
		fi
		case "$attempt" in
			1) sleep 2 ;;
			2) sleep 4 ;;
			3) sleep 8 ;;
			4) sleep 16 ;;
		esac
		attempt=$((attempt + 1))
		continue
	fi

	body=$(response_text "$response_file")
	if [ "$curl_exit" -ne 0 ]; then
		log "warning: report failed after $attempt attempts because of a network error"
	elif [ "$status" = "401" ] || [ "$status" = "403" ]; then
		if [ -n "$body" ]; then
			log "HTTP $status: $body; check ROKO_DEPLOY_TOKEN"
		else
			log "HTTP $status; check ROKO_DEPLOY_TOKEN"
		fi
	elif [ "$retry" -eq 1 ]; then
		if [ -n "$body" ]; then
			log "warning: report failed after $attempt attempts with HTTP $status: $body"
		else
			log "warning: report failed after $attempt attempts with HTTP $status"
		fi
	elif [ -n "$body" ]; then
		log "HTTP $status: $body"
	else
		log "HTTP $status"
	fi

	strict_exit 3
done

strict_exit 3
