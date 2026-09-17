# PortKiller Plugins

Plugins add your own tools to PortKiller. A plugin can:

- **Add a tab** next to Ports, Port Forwards and Tunnels, listing anything with a status, such as Docker containers, SSH tunnels or dev servers, with actions for each item.
- **Add actions to ports**, shown in a port's menu and details, such as opening the project folder of a dev server.

A plugin is a folder with a `plugin.json` and an executable in any language. PortKiller runs the executable, exchanges JSON with it, and draws everything with native controls.

## Install a Plugin

1. Copy the `.portkillerplugin` folder to `~/Library/Application Support/PortKiller/Plugins`. **Settings › Plugins › Open Plugins Folder** opens it.
2. Turn the plugin on in **Settings › Plugins**.

PortKiller never runs a plugin you haven't turned on. Plugins run with your user account, so only turn on plugins you trust.

Two examples live in [`Plugins`](Plugins): **Docker** adds a tab with your containers, and **Open in Editor** adds folder actions to dev server ports.

## Layout

```
MyTool.portkillerplugin/
├── plugin.json
└── run.sh
```

## plugin.json

```json
{
  "apiVersion": 1,
  "id": "com.example.mytool",
  "name": "My Tool",
  "version": "1.0.0",
  "description": "What the plugin does, in one sentence.",
  "author": "Your Name",
  "homepage": "https://example.com",
  "icon": "shippingbox",
  "executable": "run.sh",
  "items": {
    "title": "My Tool",
    "refreshInterval": 10
  },
  "portActions": [
    {
      "id": "open",
      "title": "Open in My Tool",
      "icon": "arrow.up.forward.app",
      "processes": ["node", "python*"],
      "ports": [3000, 5173]
    }
  ]
}
```

| Key | Required | Meaning |
| --- | --- | --- |
| `apiVersion` | Yes | Always `1`. |
| `id` | Yes | Unique ID made of letters, digits, `.`, `-` and `_`. |
| `name`, `version` | Yes | Shown in Settings. |
| `executable` | Yes | Path inside the plugin folder. It must be executable (`chmod +x`). |
| `description`, `author`, `homepage` | No | Shown in Settings. |
| `icon` | No | An [SF Symbol](https://developer.apple.com/sf-symbols/) name. |
| `items` | No | Adds a tab. `title` names the tab; `refreshInterval` is in seconds, at least 2, 10 by default. |
| `portActions` | No | Actions for ports. `processes` takes process names with `*` wildcards and `ports` takes port numbers. Leave both out to offer the action on every port. |

## Protocol

PortKiller runs the executable with one command as its argument, writes a JSON request to its standard input, and reads a JSON response from its standard output.

- Exit with status `0` on success. On any other status, PortKiller shows what the plugin wrote to standard error.
- A command must finish within 15 seconds.
- `PATH` includes Homebrew, `/usr/local/bin`, `~/.local/bin`, Rancher Desktop, OrbStack and Docker Desktop. `PORTKILLER_API_VERSION`, `PORTKILLER_PLUGIN_ID` and `PORTKILLER_PLUGIN_DIR` are also set.
- Empty output counts as `{}`.

### `items`

Called when the plugin's tab is open, every `refreshInterval` seconds. The request is `{}`.

```json
{
  "items": [
    {
      "id": "c0ffee",
      "title": "web",
      "subtitle": "nginx:latest",
      "status": "running",
      "port": 8080,
      "url": "http://localhost:8080",
      "fields": [
        { "label": "Image", "value": "nginx:latest" }
      ],
      "actions": [
        { "id": "stop", "title": "Stop", "icon": "stop.fill", "destructive": true }
      ]
    }
  ]
}
```

Only `id` and `title` are required. `status` is `running`, `stopped`, `warning` or `error`.

### `perform`

Called when someone picks one of an item's actions.

```json
{ "action": "stop", "item": "c0ffee" }
```

### `port-action`

Called when someone picks one of the plugin's `portActions` on a port.

```json
{
  "action": "open",
  "port": {
    "port": 3000,
    "pid": 4121,
    "process": "node",
    "command": "node server.js",
    "executable": "/opt/homebrew/bin/node",
    "user": "you",
    "addresses": ["127.0.0.1"]
  }
}
```

### Action Results

`perform` and `port-action` can answer with any of these keys:

```json
{
  "message": "Container stopped.",
  "open": "http://localhost:8080",
  "copy": "text for the clipboard",
  "refresh": true
}
```

`message` appears as a notification and `open` opens a URL. After `perform`, the tab refreshes unless `refresh` is `false`.

## A Minimal Plugin

```bash
#!/bin/bash
input=$(cat)

case "$1" in
  items)
    echo '{"items":[{"id":"hello","title":"Hello","status":"running","actions":[{"id":"wave","title":"Wave"}]}]}'
    ;;
  perform)
    action=$(printf '%s' "$input" | plutil -extract action raw -o - -)
    echo "{\"message\":\"You picked $action.\"}"
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 1
    ;;
esac
```

`plutil -extract key raw -o - -` reads a value from JSON on standard input, and it ships with macOS.

## Testing

Run the commands yourself before you turn the plugin on:

```bash
echo '{}' | ./run.sh items
echo '{"action":"wave","item":"hello"}' | ./run.sh perform
```

After changing `plugin.json`, click **Reload** in Settings › Plugins. Plugins that can't load are listed there with the reason.
