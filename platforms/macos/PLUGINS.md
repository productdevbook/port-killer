# PortKiller Plugins

Plugins add your own tools to PortKiller. A plugin can:

- **Add a sidebar section** listing anything with a status, such as Docker containers, saved HTTP requests or dev servers, with actions for each item.
- **Add node types** that people add to the graph with their own settings and connect to ports, and that also run once from a port's menu and the inspector. See [Nodes](#nodes).
- **Ask for input** with a native form before an action runs, and ask for confirmation before destructive ones.
- **Show results** as a message, a copied value, an opened URL, or a details window with fields and text.
- **Have settings**, such as an editor name or an API token, that people fill in under **Settings › Plugins**.

A plugin is a folder with a `plugin.json` and an executable in any language. PortKiller runs the executable, exchanges JSON with it, and draws everything with native controls.

## Install a Plugin

- Double-click a `.portkillerplugin` folder, or click **Install Plugin…** in **Settings › Plugins**.
- Or copy it to `~/Library/Application Support/PortKiller/Plugins` and click **Reload**. **Open Plugins Folder** opens that folder.

Installing a plugin with the same `id` as an installed one replaces it. Its settings and data stay.

PortKiller never runs a plugin you haven't turned on in **Settings › Plugins**. Plugins run with your user account, so only turn on plugins you trust.

Three examples live in [`Plugins`](Plugins):

- **Docker** lists your containers with their logs, and starts, stops, restarts or removes them. It has a setting for the Docker context.
- **Open in Editor** opens the folder a dev server runs from in the editor you choose in its settings.
- **HTTP Requests** adds an HTTP Request node. Each node keeps its own method, path, headers and body, so a port can have a health check and an API call side by side.

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
  "settings": [
    { "id": "token", "label": "API Token", "type": "secret", "required": true }
  ],
  "portActions": [
    {
      "id": "open",
      "title": "Open in My Tool",
      "description": "Opens the project in My Tool.",
      "icon": "arrow.up.forward.app",
      "processes": ["node", "python*"],
      "ports": [3000, 5173]
    },
    {
      "id": "deploy",
      "title": "Deploy…",
      "icon": "icloud.and.arrow.up",
      "confirmation": "Deploy this server to production?",
      "inputs": [
        { "id": "branch", "label": "Branch", "default": "main", "required": true }
      ]
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
| `items` | No | Adds a sidebar section. `title` names it; `refreshInterval` is in seconds, at least 2, 10 by default. |
| `settings` | No | [Inputs](#inputs) shown under the plugin in Settings › Plugins. Every command gets their values. |
| `portActions` | No | Actions for ports, which are also the plugin's [node](#nodes) types. `description` is a sentence shown when adding the node and on nodes without a summary. `processes` takes process names with `*` wildcards and `ports` takes port numbers; leave both out to offer the action on every port. `confirmation` and `inputs` work as they do for [item actions](#items). |

A title that ends in `…` tells people the action asks for something first.

## Inputs

Settings, `portActions` and item actions describe their fields the same way. Before an action with `inputs` runs, PortKiller shows a form, checks the values, and remembers them for next time, except secrets.

```json
{ "id": "method", "label": "Method", "type": "choice", "options": ["GET", "POST"], "default": "GET" }
```

| Key | Meaning |
| --- | --- |
| `id` | Letters, digits, `-` and `_`. Unique within the list. |
| `label` | The field's name. |
| `type` | `text` (default), `multiline`, `secret`, `number`, `toggle` or `choice`. |
| `default` | The starting value. It must fit the type. |
| `options` | The choices of a `choice`. Required for that type. |
| `placeholder` | Hint text shown in an empty field. |
| `required` | `true` if the field can't be empty. |
| `help` | A sentence shown under the field. |

Values always reach the plugin as strings: toggles are `"true"` or `"false"`, and numbers are what was typed. Secret settings are stored in the Keychain.

## Nodes

Each of a plugin's `portActions` is a kind of node people add to the graph with **Add Node**, and as many times as they like. A node has a name and its own values for the action's inputs, so HTTP Requests can have a "Health Check" node that sends `GET /health` and a "Create User" node that sends `POST /users`.

- Dragging a port onto a node connects them, and a node can connect to several ports. The plugin doesn't need to store anything.
- A node runs from its ▶ button on every connected port that's listening, from a wire on that port, or from the port's Plugins tab in the inspector.
- **Edit** changes a node's name and values, and **Duplicate** copies it.
- A node can **run when a connected port starts listening**, such as sending a health check or opening an editor when a dev server starts.
- A port's menu and the inspector's **Run** still run an action once without adding a node.

The `port-action` request carries the node's `id` in `node`, which a plugin can use to keep data per node.

## Protocol

PortKiller runs the executable with one command as its argument, writes a JSON request to its standard input, and reads a JSON response from its standard output.

- Exit with status `0` on success. On any other status, PortKiller shows what the plugin wrote to standard error.
- On success, what the plugin writes to standard error appears as the plugin log in the run's details, which helps while building a plugin.
- A command must finish within 15 seconds.
- Empty output counts as `{}`.

Every command gets these environment variables:

| Variable | Value |
| --- | --- |
| `PATH` | Includes Homebrew, `/usr/local/bin`, `~/.local/bin`, Rancher Desktop, OrbStack and Docker Desktop. |
| `PORTKILLER_API_VERSION` | `1` |
| `PORTKILLER_PLUGIN_ID` | The plugin's `id`. |
| `PORTKILLER_PLUGIN_DIR` | The plugin folder. Treat it as read-only; installing an update replaces it. |
| `PORTKILLER_DATA_DIR` | A folder that belongs to the plugin and survives updates. Keep saved data here. |
| `PORTKILLER_SETTING_<ID>` | Each setting's value. The ID is uppercased and other characters become `_`, so `api-token` becomes `PORTKILLER_SETTING_API_TOKEN`. |

PortKiller doesn't run a plugin's commands while a required setting is empty.

### `items`

Called for plugins with `items`, every `refreshInterval` seconds and after an action on an item. The request is `{}`.

```json
{
  "items": [
    {
      "id": "c0ffee",
      "title": "web",
      "subtitle": "nginx:latest",
      "status": "running",
      "port": 8080,
      "targetPorts": [3000],
      "url": "http://localhost:8080",
      "fields": [
        { "label": "Image", "value": "nginx:latest" }
      ],
      "actions": [
        { "id": "logs", "title": "Show Logs", "icon": "text.alignleft" },
        {
          "id": "stop",
          "title": "Stop",
          "icon": "stop.fill",
          "destructive": true,
          "confirmation": "Stop web?"
        }
      ]
    }
  ]
}
```

- Only `id` and `title` are required, and each `id` must be unique.
- `status` is `running`, `stopped`, `warning` or `error`.
- `port` is a port the item listens on; the graph shows the item as its owner. `targetPorts` are ports the item uses, such as a saved request's server; the graph connects those ports to the item.
- `url` adds Open in Browser and Copy URL.
- Actions take `destructive`, `confirmation` and [`inputs`](#inputs).

### `perform`

Called when someone runs one of an item's actions. `inputs` is present when the action has inputs.

```json
{ "action": "stop", "item": "c0ffee", "inputs": { "grace": "10" } }
```

### `port-action`

Called when someone runs one of the plugin's `portActions` on a port from a menu or the inspector, and when a [node](#nodes) runs.

```json
{
  "action": "deploy",
  "port": {
    "port": 3000,
    "pid": 4121,
    "process": "node",
    "command": "node server.js",
    "executable": "/opt/homebrew/bin/node",
    "user": "you",
    "addresses": ["127.0.0.1"]
  },
  "inputs": { "branch": "main" },
  "node": "6F1C2A9E-4B5D-4E8F-9A7B-2C3D4E5F6A7B"
}
```

`inputs` is present when the action has inputs, and `node` when a [node](#nodes) runs.

### Action Results

`perform` and `port-action` can answer with any of these keys:

```json
{
  "message": "Deployed main.",
  "open": "https://example.com/deploys/42",
  "copy": "text for the clipboard",
  "refresh": true,
  "details": {
    "title": "Deploy 42",
    "fields": [{ "label": "Duration", "value": "38 s" }],
    "text": "Build output…"
  }
}
```

- `message` appears at the bottom of the window, and as a notification when PortKiller isn't in front.
- `open` opens a URL, and `copy` copies text.
- `details` opens a window with the fields and the text in a monospaced, selectable view with a Copy button.
- After `perform`, the section refreshes unless `refresh` is `false`.

PortKiller keeps a history of runs while it's open. It appears in the inspector's Plugins tab for ports and items, and a port action's node in the graph shows its last result; click the node to open it.

## A Minimal Plugin

```bash
#!/bin/bash
input=$(cat)

case "$1" in
  items)
    echo '{"items":[{"id":"hello","title":"Hello","status":"running","actions":[{"id":"wave","title":"Wave…","inputs":[{"id":"name","label":"Name","required":true}]}]}]}'
    ;;
  perform)
    name=$(printf '%s' "$input" | plutil -extract inputs.name raw -o - -)
    echo "{\"message\":\"Hello, $name.\"}"
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 1
    ;;
esac
```

`plutil -extract key raw -o - -` reads a value from JSON on standard input, and it ships with macOS. When you build JSON in a shell script, escape `\`, `"` and control characters in the values you insert; the HTTP Requests example has a `json` function that does.

## Testing

Run the commands yourself before you turn the plugin on:

```bash
echo '{}' | ./run.sh items
echo '{"action":"wave","item":"hello","inputs":{"name":"Ada"}}' | ./run.sh perform
echo '{}' | PORTKILLER_SETTING_TOKEN=abc ./run.sh items
```

After changing `plugin.json`, click **Reload** in Settings › Plugins. Plugins that can't load are listed there with the reason. Open a run from the inspector's Plugins tab to see its result and the plugin log.
