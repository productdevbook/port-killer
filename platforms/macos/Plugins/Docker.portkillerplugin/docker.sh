#!/bin/bash
set -euo pipefail

input=$(cat)

field() {
  printf '%s' "$input" | plutil -extract "$1" raw -o - -
}

case "${1:-}" in
  items)
    format='{"id":{{json .ID}},"title":{{json .Names}},"subtitle":{{json .Image}},'
    format+='"status":{{if eq .State "running"}}"running"{{else if eq .State "exited"}}"stopped"{{else}}"warning"{{end}},'
    format+='"fields":[{"label":"State","value":{{json .Status}}},{"label":"Ports","value":{{json .Ports}}},{"label":"Created","value":{{json .RunningFor}}}],'
    format+='"actions":[{{if eq .State "running"}}{"id":"restart","title":"Restart","icon":"arrow.clockwise"},{"id":"stop","title":"Stop","icon":"stop.fill","destructive":true}{{else}}{"id":"start","title":"Start","icon":"play.fill"}{{end}}]}'
    printf '{"items":[%s]}\n' "$(docker ps --all --format "$format" | paste -sd, -)"
    ;;
  perform)
    action=$(field action)
    case "$action" in
      start|stop|restart) docker "$action" "$(field item)" >/dev/null ;;
      *) echo "Unknown action: $action" >&2; exit 1 ;;
    esac
    echo '{}'
    ;;
  *)
    echo "Unknown command: ${1:-}" >&2
    exit 1
    ;;
esac
