#!/bin/bash
set -euo pipefail

input=$(cat)
timeout=${PORTKILLER_SETTING_TIMEOUT:-10}
insecure=${PORTKILLER_SETTING_INSECURE:-true}

field() {
  printf '%s' "$input" | plutil -extract "$1" raw -o - - 2>/dev/null
}

json() {
  local text
  text=$(printf '%s' "$1" | iconv -f UTF-8 -t UTF-8 -c | tr -d '\000-\010\013\014\016-\037')
  text=${text//\\/\\\\}
  text=${text//\"/\\\"}
  text=${text//$'\n'/\\n}
  text=${text//$'\r'/\\r}
  text=${text//$'\t'/\\t}
  printf '"%s"' "$text"
}

quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

size() {
  awk -v bytes="$1" 'BEGIN {
    if (bytes < 1024) printf "%d B", bytes
    else if (bytes < 1048576) printf "%.1f KB", bytes / 1024
    else printf "%.1f MB", bytes / 1048576
  }'
}

seconds() {
  awk -v wanted="$timeout" -v limit="$1" 'BEGIN {
    value = wanted + 0
    if (value <= 0 || value > limit) value = limit
    print value
  }'
}

# send <url> <response prefix> <seconds>: uses $method, $headers and $body.
send() {
  local url=$1 output=$2 limit=$3 result line
  local options=(--silent --show-error --max-time "$limit" --output "$output.body" --dump-header "$output.headers")
  if [ "$method" = HEAD ]; then
    options+=(--head)
  else
    options+=(--request "$method")
  fi
  if [ "$insecure" = true ]; then
    options+=(--insecure)
  fi
  while IFS= read -r line; do
    line=${line%$'\r'}
    if [ -n "$line" ]; then
      options+=(--header "$line")
    fi
  done <<<"$headers"
  if [ -n "$body" ]; then
    options+=(--data-binary "$body")
  fi
  : >"$output.headers"
  if ! result=$(curl "${options[@]}" --write-out '%{http_code} %{time_total} %{size_download}' "$url" 2>"$output.error"); then
    return 1
  fi
  printf '%s\n' "$result" >"$output.result"
}

curl_command() {
  local url=$1 command line
  command="curl -X $method $(quote "$url")"
  while IFS= read -r line; do
    line=${line%$'\r'}
    [ -n "$line" ] && command+=" -H $(quote "$line")"
  done <<<"$headers"
  [ -n "$body" ] && command+=" --data-binary $(quote "$body")"
  printf '%s' "$command"
}

# report <url> <response prefix>: prints the result with details.
report() {
  local url=$1 output=$2 code seconds bytes milliseconds status line fields text message
  read -r code seconds bytes <"$output.result"
  milliseconds=$(awk -v seconds="$seconds" 'BEGIN { printf "%d", seconds * 1000 }')
  status=$(grep -a '^HTTP/' "$output.headers" | tail -n 1 | tr -d '\r')
  fields="{\"label\":\"Status\",\"value\":$(json "${status:-$code}")},{\"label\":\"Time\",\"value\":\"$milliseconds ms\"},{\"label\":\"Size\",\"value\":$(json "$(size "$bytes")")}"
  while IFS= read -r line; do
    line=${line%$'\r'}
    case $line in
      *:*) fields+=",{\"label\":$(json "${line%%:*}"),\"value\":$(json "$(printf '%s' "${line#*:}" | sed 's/^ *//')")}" ;;
    esac
  done < <(awk '/^HTTP\// { block = ""; next } { block = block $0 "\n" } END { printf "%s", block }' "$output.headers")
  fields+=",{\"label\":\"curl\",\"value\":$(json "$(curl_command "$url")")}"
  if [ ! -s "$output.body" ]; then
    text=""
  elif ! tr -d '\000' <"$output.body" | cmp -s - "$output.body"; then
    text="Binary response, $(size "$bytes")."
  else
    text=$(head -c 200000 "$output.body")
  fi
  message="$method ${url#http://} → $code · $milliseconds ms · $(size "$bytes")"
  printf '{"message":%s,"details":{"title":%s,"fields":[%s],"text":%s}}\n' \
    "$(json "$message")" "$(json "$method ${url#http://}")" "$fields" "$(json "$text")"
}

if [ "${1:-}" != "port-action" ]; then
  echo "Unknown command: ${1:-}" >&2
  exit 1
fi

action=$(field action)
port=$(field port.port)
case $action in
  send)
    method=$(field inputs.method || echo GET)
    path=$(field inputs.path || echo /)
    headers=$(field inputs.headers || true)
    body=$(field inputs.body || true)
    ;;
  *)
    echo "Unknown action: $action" >&2
    exit 1
    ;;
esac
[[ $path == /* ]] || path="/$path"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
url="http://localhost:$port$path"
if send "$url" "$scratch/http" "$(seconds 6)"; then
  report "$url" "$scratch/http"
  exit 0
fi
url="https://localhost:$port$path"
if send "$url" "$scratch/https" "$(seconds 6)"; then
  report "$url" "$scratch/https"
  exit 0
fi
echo "Port $port didn't answer HTTP or HTTPS, so it may not be a web server. $(cat "$scratch/http.error")" >&2
exit 1
