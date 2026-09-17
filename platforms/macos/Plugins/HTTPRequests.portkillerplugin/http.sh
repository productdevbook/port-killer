#!/bin/bash
set -euo pipefail

input=$(cat)
dir=${PORTKILLER_PLUGIN_DIR:-$(cd "$(dirname "$0")" && pwd)}
requests="$dir/requests.json"
state="$dir/.state"

field() {
  printf '%s' "$input" | plutil -extract "$1" raw -o - -
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

# send <method> <url> <response file> [curl options...] prints "<status> <milliseconds> <bytes>".
send() {
  local method=$1 url=$2 output=$3 result code seconds bytes
  shift 3
  local verb=(--request "$method")
  [ "$method" = HEAD ] && verb=(--head)
  if ! result=$(curl --silent --show-error --max-time 10 "${verb[@]}" --output "$output" \
    --write-out '%{http_code} %{time_total} %{size_download}' ${1+"$@"} "$url" 2>"$output.error"); then
    echo "$method $url got no response. $(cat "$output.error")" >&2
    return 1
  fi
  read -r code seconds bytes <<<"$result"
  printf '%s %s %s\n' "$code" "$(awk -v seconds="$seconds" 'BEGIN { printf "%d", seconds * 1000 }')" "$bytes"
}

describe() {
  printf '%s %s → %s · %s ms · %s' "$1" "${2#*://}" "$3" "$4" "$(size "$5")"
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
  echo "requests.json has no request with the ID \"$1\"." >&2
  return 1
}

load() {
  id=$(saved "$1.id")
  name=$(saved "$1.name" || echo "$id")
  method=$(saved "$1.method" | tr '[:lower:]' '[:upper:]' || echo GET)
  url=$(saved "$1.url")
  key=$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_')
  options=()
  local number=0 header body
  while header=$(saved "$1.headers.$number"); do
    options+=(--header "$header")
    number=$((number + 1))
  done
  if body=$(saved "$1.body"); then
    options+=(--data-binary "$body")
  fi
}

items() {
  local index=0 entries=() code milliseconds bytes sent status subtitle response entry
  if [ ! -f "$requests" ]; then
    echo '{"items":[]}'
    return
  fi
  while saved "$index.id" >/dev/null; do
    load "$index"
    if [ -f "$state/$key.result" ]; then
      read -r code milliseconds bytes sent <"$state/$key.result"
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
      subtitle="$method · $response"
    else
      status=stopped
      response="Not sent yet"
      sent="Never"
      subtitle="$method · Not sent yet"
    fi
    entry="{\"id\":$(json "$id"),\"title\":$(json "$name"),\"subtitle\":$(json "$subtitle"),\"status\":\"$status\""
    if [ "$method" = GET ] && [[ $url =~ ^https?://[^[:space:]]+$ ]]; then
      entry+=",\"url\":$(json "$url")"
    fi
    entry+=",\"fields\":[{\"label\":\"Request\",\"value\":$(json "$method $url")},{\"label\":\"Response\",\"value\":$(json "$response")},{\"label\":\"Sent\",\"value\":$(json "$sent")}]"
    entry+=',"actions":[{"id":"send","title":"Send","icon":"paperplane"},{"id":"copy","title":"Send and Copy Response","icon":"doc.on.doc"},{"id":"curl","title":"Copy as curl","icon":"terminal"},{"id":"edit","title":"Edit Requests…","icon":"pencil"}]}'
    entries+=("$entry")
    index=$((index + 1))
  done
  printf '{"items":[%s]}\n' "$(IFS=,; echo "${entries[*]-}")"
}

perform() {
  local action item index summary message command option
  action=$(field action)
  if [ "$action" = edit ]; then
    printf '{"open":%s,"refresh":false}\n' "$(json "file://${requests// /%20}")"
    return
  fi
  item=$(field item)
  index=$(index_of "$item")
  load "$index"
  case $action in
    send|copy)
      mkdir -p "$state"
      if ! summary=$(send "$method" "$url" "$state/$key.body" ${options[@]+"${options[@]}"}); then
        printf '000 0 0 %s\n' "$(date '+%H:%M:%S')" >"$state/$key.result"
        exit 1
      fi
      printf '%s %s\n' "$summary" "$(date '+%H:%M:%S')" >"$state/$key.result"
      message=$(describe "$method" "$url" $summary)
      if [ "$action" = copy ]; then
        printf '{"message":%s,"copy":%s}\n' "$(json "$message")" "$(json "$(cat "$state/$key.body")")"
      else
        printf '{"message":%s}\n' "$(json "$message")"
      fi
      ;;
    curl)
      command="curl -X $method $(quote "$url")"
      for option in ${options[@]+"${options[@]}"}; do
        case $option in
          --header) command+=" -H" ;;
          --data-binary) command+=" --data-binary" ;;
          *) command+=" $(quote "$option")" ;;
        esac
      done
      printf '{"copy":%s,"message":"Copied the curl command.","refresh":false}\n' "$(json "$command")"
      ;;
    *)
      echo "Unknown action: $action" >&2
      exit 1
      ;;
  esac
}

port_action() {
  local action port url summary message
  action=$(field action)
  port=$(field port.port)
  url="http://localhost:$port/"
  scratch=$(mktemp -d)
  trap 'rm -rf "$scratch"' EXIT
  summary=$(send GET "$url" "$scratch/body")
  message=$(describe GET "$url" $summary)
  case $action in
    get) printf '{"message":%s}\n' "$(json "$message")" ;;
    copy) printf '{"message":%s,"copy":%s}\n' "$(json "$message")" "$(json "$(cat "$scratch/body")")" ;;
    *) echo "Unknown action: $action" >&2; exit 1 ;;
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
