#!/bin/bash
set -euo pipefail

input=$(cat)

field() {
  printf '%s' "$input" | plutil -extract "$1" raw -o - -
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

docker() {
  if [ -n "${PORTKILLER_SETTING_CONTEXT:-}" ]; then
    command docker --context "$PORTKILLER_SETTING_CONTEXT" "$@"
  else
    command docker "$@"
  fi
}

case "${1:-}" in
  items)
    format='{"id":{{json .ID}},"title":{{json .Names}},"subtitle":{{json .Image}},'
    format+='"status":{{if eq .State "running"}}"running"{{else if eq .State "exited"}}"stopped"{{else}}"warning"{{end}},'
    format+='"fields":[{"label":"State","value":{{json .Status}}},{"label":"Ports","value":{{json .Ports}}},{"label":"Created","value":{{json .RunningFor}}}],'
    format+='"actions":[{{if eq .State "running"}}{"id":"restart","title":"Restart","icon":"arrow.clockwise"},'
    format+='{"id":"stop","title":"Stop","icon":"stop.fill","destructive":true,"confirmation":{{json (printf "Stop %s? Anything running in it stops too." .Names)}}}'
    format+='{{else}}{"id":"start","title":"Start","icon":"play.fill"},'
    format+='{"id":"remove","title":"Remove","icon":"trash","destructive":true,"confirmation":{{json (printf "Remove %s? Its files are deleted unless they live in a volume." .Names)}}}{{end}},'
    format+='{"id":"logs","title":"Show Logs","icon":"text.alignleft"}]}'
    printf '{"items":[%s]}\n' "$(docker ps --all --format "$format" | paste -sd, -)"
    ;;
  perform)
    action=$(field action)
    container=$(field item)
    case "$action" in
      start|stop|restart)
        docker "$action" "$container" >/dev/null
        echo '{}'
        ;;
      remove)
        docker rm "$container" >/dev/null
        echo '{}'
        ;;
      logs)
        name=$(docker inspect --format '{{.Name}}' "$container" | sed 's|^/||')
        logs=$(docker logs --tail 300 "$container" 2>&1)
        printf '{"refresh":false,"details":{"title":%s,"text":%s}}\n' "$(json "Logs of $name")" "$(json "${logs:-No output yet.}")"
        ;;
      *)
        echo "Unknown action: $action" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unknown command: ${1:-}" >&2
    exit 1
    ;;
esac
