# Agent Cloud Todos

Omarchy bar **and window** app (`todos-omarchy`) for open items in plain markdown todos and [Agent Cloud](https://cloud.bixbyapps.com) hosted todos. Linux port of [todo-bar](https://github.com/stevederico/todo-bar).

## What it does

- Bar icon with the open-item count; click toggles a floating window (same as Agent Cloud Calendar)
- Omarchy menu **Agent Cloud Todos** opens the same window
- The window floats so it does not take over a scrolling-layout column
- Tabs for multiple files (default: `~/todos.md`, then `~/Documents/todos.md`)
- Agent Cloud is the default tab when `~/.config/agentcloud/hosted-calendars.json` exists (same write key as the calendar). Completes, edits, and deletes over HTTP, queued in order and guarded by each todo's rev. If a todo changed elsewhere, the server's version stays: an edit is saved as a new todo titled `… (conflict copy)` and a check is applied again on top. Queued writes keep going when you switch to a file tab. Refreshes every minute while open. No git. A `seal` calendar is sealed before write and opened after read. A `plain` calendar stays plaintext. Git lists stay on their own tabs.
- **+** tab after the last list takes a path to another `.md` (e.g. `~/books.md`, `~/marketing/todo.md`) or `agentcloud` / `agentcloud:cal_…` (`almanac` still works)
- Right-click tab → Rename / Reveal / Remove (Reveal is markdown only)
- Shows open items (`- task`) grouped by `##` section; completed stay hidden until **Show Completed**
- **+** / `n` — new to-do is prepended at the top of the first section (pre-header `To-Dos` when present)
- Capture box: `omarchy-shell shell call sd.agentcloud-todos capture {}` — large centered field; Enter adds one item to the active list, Esc closes
- Click the circle — mark complete (`- [x]`), move that line to the **end of the file**; **Show Completed** to see / reopen
- Click text to edit; right-click for Complete / Copy / Delete
- Drag open items to reorder
- Live-reloads when the active file changes; tabs persist in `~/.config/agentcloud-todos/sources.json`

Opening or closing the panel or window syncs that file's git remote (pull when behind; push when ahead). Edits commit and push. Fetch failures stay silent. Diverged branches and overlapping uncommitted files are left alone. **Refresh** (or `r`) forces a check.

Completing an item always appends it to a sibling `CHANGELOG.md` (creates the file if needed).

## Install

Review the plugin, then enable it. Omarchy plugins run unsandboxed inside `omarchy-shell`.

```sh
omarchy plugin add https://github.com/stevederico/todos-omarchy.git
omarchy plugin enable sd.agentcloud-todos --section right --before omarchy.clock
```

Local checkout (copy the repository root, not a symlink):

```sh
PLUGIN_ID="sd.agentcloud-todos"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
mkdir -p "$PLUGIN_DIR"
cp -a ~/Projects/todos-omarchy/. "$PLUGIN_DIR/"
omarchy plugin validate "$PLUGIN_DIR"
omarchy plugin enable "$PLUGIN_ID" --section right --before omarchy.clock
```

Open or toggle the window (menu or the bar icon):

```sh
omarchy-shell shell toggle sd.agentcloud-todos
```

Middle-click the bar icon to reload. Escape or the bar icon dismisses the window.

Optional menu row: merge `extra/omarchy-menu-todo.jsonc` into `~/.config/omarchy/extensions/omarchy-menu.jsonc`. Do not replace that file.

## Moving from Dottie-Todos

This app was Dottie-Todos (`dottie-todo-omarchy`). The plugin id changed, so install it again; your tabs and key carry over on their own:

- Plugin id: `sd.dottie-todo-omarchy` is now `sd.agentcloud-todos`. Run `omarchy plugin add https://github.com/stevederico/todos-omarchy.git`, enable `sd.agentcloud-todos`, then remove the old plugin. Update keybindings that call `sd.dottie-todo-omarchy` or `sd.dottie-todos-omarchy` (use `sd.agentcloud-todos`, `agentcloud-todos` or `sd.todo-omarchy`). Re-merge `extra/omarchy-menu-todo.jsonc` (key `apps.agentcloud-todos`).
- Tabs: kept in `~/.config/agentcloud-todos/sources.json`. On the first start without that file, the app reads `~/.config/dottie-todo-omarchy/sources.json` once and writes it to the new path. The old file is left alone; delete it when you like. A tab still titled `Almanac` shows as Agent Cloud.
- Credentials: read from `~/.config/agentcloud/hosted-calendars.json`. While that file is missing, the old `~/.config/almanac/hosted-calendars.json` is read instead. Move it when you like: `mkdir -p ~/.config/agentcloud && mv ~/.config/almanac/hosted-calendars.json ~/.config/agentcloud/`.
- Server: `https://cloud.bixbyapps.com`. A credentials file whose write URL is on `almanac.dottie.ai` talks to the new host.
- Sealed calendars need the `agentcloud` (or older `almanac`) binary for seal and open.
- Code names: `Almanac.js`, `AlmanacRemote.qml`, `scripts/almanac-todos.sh` and the tests are now `Cloud.js`, `CloudRemote.qml`, `scripts/cloud-todos.sh`, `tests/cloud_server.sh` and `tests/test_cloud.js`. The Agent Cloud tab is saved as kind `cloud` with `cloudHidden`; the old `almanac` kind and `almanacHidden` key are still read.
- Runtime files (open count, commit message, request bodies) and the git lock (`.git/agentcloud-todos-sync.lock`) use the new name. Nothing there needs moving.
- Git remote: `git remote set-url origin https://github.com/stevederico/todos-omarchy.git` in an existing clone.

## Format

Markdown lists:

- `- item` = open (shown)
- `- [x] item` = completed (line moved to end of file; hidden until Show Completed)
- `## Section` = group header

Agent Cloud lists use the hosted `/v1/c/{id}/todos` API. First tag becomes the section. Due date and priority stay on the server. Drag-reorder is markdown only (Agent Cloud sorts open items, then due, then created).

## Tests

```sh
node --test tests/*.js
AGENTCLOUD_BIN=~/Projects/agentcloud/target/debug/agentcloud bash tests/cloud_server.sh   # or ALMANAC_BIN for an older almanac build
```

`tests/cloud_server.sh` runs the script against a throwaway Agent Cloud server built from the agentcloud repo (plain and sealed calendars, stale `--rev`, no key or token in `ps`).

`scripts/cloud-lib.sh` is a copy of `clients/shell/cloud-lib.sh` from the Agent Cloud server repo (`stevederico/agentcloud`). Change it there first.

## Sample data

Screenshots / first-run tabs can use the fake lists in `docs/demo/` (not anyone's real todos).
