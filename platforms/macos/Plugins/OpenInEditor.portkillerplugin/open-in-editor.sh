#!/bin/bash
set -euo pipefail

input=$(cat)

field() {
  printf '%s' "$input" | plutil -extract "$1" raw -o - -
}

if [ "${1:-}" != "port-action" ]; then
  echo "Unknown command: ${1:-}" >&2
  exit 1
fi

pid=$(field port.pid)
folder=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1 || true)
if [ -z "$folder" ]; then
  echo "Couldn't find the folder process $pid runs from." >&2
  exit 1
fi

case "$(field action)" in
  code) open -a "Visual Studio Code" "$folder" ;;
  finder) open "$folder" ;;
  *) echo "Unknown action." >&2; exit 1 ;;
esac

echo '{}'
