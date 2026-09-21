# Dottie-Todos

Omarchy bar **and window** app (`todo-omarchy`) for open items in plain markdown todos and [Almanac](https://almanac.dottie.ai) hosted todos. Linux port of [todo-bar](https://github.com/stevederico/todo-bar).

## What it does

- Bar icon with the open-item count; click toggles a floating window (same as Almanac Calendar)
- App launcher / Omarchy menu **Dottie-Todos** opens the same window
- The window floats so it does not take over a scrolling-layout column
- Tabs for multiple files (default: `~/todos.md`, then `~/Documents/todos.md`)
- Almanac tab when `~/.config/almanac/hosted-calendars.json` exists (same write key as the calendar). Completes, edits, and deletes over HTTP. No git.
- **+** tab after the last list takes a path to another `.md` (e.g. `~/books.md`, `~/marketing/todo.md`) or `almanac` / `almanac:cal_…`
- Right-click tab → Rename / Reveal / Remove (Reveal is markdown only)
- Shows open items (`- task`) grouped by `##` section; completed stay hidden until **Show Completed**
- **+** / `n` — new to-do is prepended at the top of the first section (pre-header `To-Dos` when present)
- Capture box: `omarchy-shell shell call sd.todo-omarchy capture {}` — large centered field; Enter adds one item to the active list, Esc closes
- Click the circle — mark complete (`- [x]`), move that line to the **end of the file**; **Show Completed** to see / reopen
- Click text to edit; right-click for Complete / Copy / Delete
- Drag open items to reorder
- Live-reloads when the active file changes; tabs persist in `~/.config/todo-omarchy/sources.json`

Opening or closing the panel or window syncs that file's git remote (pull when behind; push when ahead). Edits commit and push. Fetch failures stay silent. Diverged branches and overlapping uncommitted files are left alone. **Refresh** (or `r`) forces a check.

Completing an item always appends it to a sibling `CHANGELOG.md` (creates the file if needed).

## Install

Review the plugin, then enable it. Omarchy plugins run unsandboxed inside `omarchy-shell`.

```sh
omarchy plugin add https://github.com/stevederico/todo-omarchy.git
omarchy plugin enable sd.todo-omarchy --section right --before omarchy.clock
```

Local checkout (copy the repository root, not a symlink):

```sh
PLUGIN_ID="sd.todo-omarchy"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
mkdir -p "$PLUGIN_DIR"
cp -a ~/Projects/todo-omarchy/. "$PLUGIN_DIR/"
omarchy plugin validate "$PLUGIN_DIR"
omarchy plugin enable "$PLUGIN_ID" --section right --before omarchy.clock
```

Open or toggle the window (app launcher, menu, or the bar icon):

```sh
omarchy-shell shell toggle sd.todo-omarchy
```

To show it in the application launcher:

```sh
cp extra/sd.todo-omarchy.desktop ~/.local/share/applications/
```

Middle-click the bar icon to reload. Escape or the bar icon dismisses the window.

Optional menu row: merge `extra/omarchy-menu-todo.jsonc` into `~/.config/omarchy/extensions/omarchy-menu.jsonc`. Do not replace that file.

## Format

Markdown lists:

- `- item` = open (shown)
- `- [x] item` = completed (line moved to end of file; hidden until Show Completed)
- `## Section` = group header

Almanac lists use the hosted `/v1/c/{id}/todos` API. First tag becomes the section. Due date and priority stay on the server. Drag-reorder is markdown only (Almanac sorts open items, then due, then created).

## Tests

```sh
node --test tests/*.js
```

## Sample data

Screenshots / first-run tabs can use the fake lists in `docs/demo/` (not anyone's real todos).
