#!/bin/bash
set -euo pipefail

input=$(cat)
dir=${PORTKILLER_PLUGIN_DIR:-$(cd "$(dirname "$0")" && pwd)}
data=${PORTKILLER_DATA_DIR:-$dir}
requests="$data/requests.json"
state="$data/state"
timeout=${PORTKILLER_SETTING_TIMEOUT:-10}
insecure=${PORTKILLER_SETTING_INSECURE:-true}
local_url='^https?://(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0):([0-9]+)'

field() {
  printf '%s' "$input" | plutil -extract "$1" raw -o - - 2>/dev/null
}

saved() {
  plutil -extract "$1" raw -o - "$requests" 2>/dev/null
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

# send <method> <url> <response prefix> <seconds> [headers text] [body]
send() {
  local method=$1 url=$2 output=$3 limit=$4 headers=${5:-} body=${6-} result line
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

# report <method> <url> <response prefix>: prints a result with details.
report() {
  local method=$1 url=$2 output=$3 code seconds bytes milliseconds status line fields text message
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
  printf '%s %s %s %s\n' "$code" "$milliseconds" "$bytes" "$(date '+%H:%M:%S')" >"$output.summary"
}

index_of() {
  local index=0 id
  while id=$(saved "$index.id"); do
    if [ "$id" = "$1" ]; then
      echo "$index"
      return
    fi
    index=$((index + 1))
  done
  echo "There's no saved request with the ID \"$1\"." >&2
  return 1
}

load() {
  id=$(saved "$1.id")
  name=$(saved "$1.name" || echo "$id")
  method=$(saved "$1.method" || echo GET)
  url=$(saved "$1.url")
  headers=$(saved "$1.headers" || true)
  body=$(saved "$1.body" || true)
  key=$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_')
}

items() {
  local index=0 entries=() code milliseconds bytes sent status subtitle response entry
  if [ ! -f "$requests" ]; then
    echo '{"items":[]}'
    return
  fi
  while saved "$index.id" >/dev/null; do
    load "$index"
    if [ -f "$state/$key.summary" ]; then
      read -r code milliseconds bytes sent <"$state/$key.summary"
      case $code in
        2??|3??) status=running ;;
        4??) status=warning ;;
        *) status=error ;;
      esac
      if [ "$code" = 000 ]; then
        response="No response"
      else
        response="$code · $milliseconds ms · $(size "$bytes")"
      fi
    else
      status=stopped
      response="Not sent yet"
      sent="Never"
    fi
    subtitle="$method · $response"
    entry="{\"id\":$(json "$id"),\"title\":$(json "$name"),\"subtitle\":$(json "$subtitle"),\"status\":\"$status\""
    if [[ $url =~ $local_url ]]; then
      entry+=",\"targetPorts\":[${BASH_REMATCH[2]}]"
    fi
    if [ "$method" = GET ] && [[ $url =~ ^https?://[^[:space:]]+$ ]]; then
      entry+=",\"url\":$(json "$url")"
    fi
    entry+=",\"fields\":[{\"label\":\"Request\",\"value\":$(json "$method $url")},{\"label\":\"Response\",\"value\":$(json "$response")},{\"label\":\"Sent\",\"value\":$(json "$sent")}]"
    entry+=',"actions":[{"id":"send","title":"Send","icon":"paperplane"},{"id":"curl","title":"Copy as curl","icon":"terminal"},{"id":"edit","title":"Edit Saved Requests","icon":"pencil"}'
    entry+=",{\"id\":\"delete\",\"title\":\"Delete\",\"icon\":\"trash\",\"destructive\":true,\"confirmation\":$(json "Delete the saved request “${name}”?")}]}"
    entries+=("$entry")
    index=$((index + 1))
  done
  printf '{"items":[%s]}\n' "$(IFS=,; echo "${entries[*]-}")"
}

perform() {
  local action item index command line
  action=$(field action)
  item=$(field item)
  index=$(index_of "$item")
  load "$index"
  case $action in
    send)
      mkdir -p "$state"
      if ! send "$method" "$url" "$state/$key" "$(seconds 14)" "$headers" "$body"; then
        printf '000 0 0 %s\n' "$(date '+%H:%M:%S')" >"$state/$key.summary"
        echo "$method $url got no response. $(cat "$state/$key.error")" >&2
        exit 1
      fi
      report "$method" "$url" "$state/$key"
      ;;
    curl)
      command="curl -X $method $(quote "$url")"
      while IFS= read -r line; do
        [ -n "$line" ] && command+=" -H $(quote "$line")"
      done <<<"$headers"
      [ -n "$body" ] && command+=" --data-binary $(quote "$body")"
      printf '{"copy":%s,"message":"Copied the curl command.","refresh":false}\n' "$(json "$command")"
      ;;
    edit)
      printf '{"open":%s,"refresh":false}\n' "$(json "file://${requests// /%20}")"
      ;;
    delete)
      plutil -remove "$index" "$requests"
      rm -f "$state/$key".*
      printf '{"message":%s}\n' "$(json "Deleted $name.")"
      ;;
    *)
      echo "Unknown action: $action" >&2
      exit 1
      ;;
  esac
}

port_action() {
  local action port method path url name id object count
  action=$(field action)
  port=$(field port.port)
  method=$(field inputs.method || echo GET)
  path=$(field inputs.path || echo /)
  [[ $path == /* ]] || path="/$path"
  headers=$(field inputs.headers || true)
  body=$(field inputs.body || true)
  scratch=$(mktemp -d)
  trap 'rm -rf "$scratch"' EXIT
  case $action in
    get|send)
      url="http://localhost:$port$path"
      if ! send "$method" "$url" "$scratch/http" "$(seconds 6)" "$headers" "$body"; then
        url="https://localhost:$port$path"
        if ! send "$method" "$url" "$scratch/https" "$(seconds 6)" "$headers" "$body"; then
          echo "Port $port didn't answer HTTP or HTTPS, so it may not be a web server. $(cat "$scratch/http.error")" >&2
          exit 1
        fi
        report "$method" "$url" "$scratch/https"
        return
      fi
      report "$method" "$url" "$scratch/http"
      ;;
    save)
      name=$(field inputs.name)
      id="request-$(date +%s)-$RANDOM"
      mkdir -p "$data"
      [ -f "$requests" ] || printf '[]' >"$requests"
      object="{\"id\":$(json "$id"),\"name\":$(json "$name"),\"method\":$(json "$method"),\"url\":$(json "http://localhost:$port$path")"
      [ -n "$headers" ] && object+=",\"headers\":$(json "$headers")"
      [ -n "$body" ] && object+=",\"body\":$(json "$body")"
      object+="}"
      count=0
      while saved "$count.id" >/dev/null; do
        count=$((count + 1))
      done
      plutil -insert "$count" -json "$object" "$requests"
      printf '{"message":%s}\n' "$(json "Saved $name. It's in the HTTP Requests section of the sidebar.")"
      ;;
    *)
      echo "Unknown action: $action" >&2
      exit 1
      ;;
  esac
}

case "${1:-}" in
  items) items ;;
  perform) perform ;;
  port-action) port_action ;;
  *)
    echo "Unknown command: ${1:-}" >&2
    exit 1
    ;;
esac
