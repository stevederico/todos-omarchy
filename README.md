# todo-omarchy

Omarchy bar **and window** app for open items in plain markdown todos. Linux port of [todo-bar](https://github.com/stevederico/todo-bar).

## What it does

- Bar icon with the open-item count; click for the compact panel, right-click for a normal window
- App launcher / Omarchy menu **Todos** opens the same UI as a tiled Hyprland window
- Tabs for multiple files (default: `~/todos.md`, then `~/Documents/todos.md`)
- **+** tab after the last list takes a path to another `.md` (e.g. `~/books.md`, `~/marketing/todo.md`)
- Right-click tab → Rename / Reveal / Remove
- Shows open items (`- task`) grouped by `##` section; completed stay hidden until **Show Completed**
- **+** / `n` — new to-do is prepended at the top of the first section (pre-header `To-Dos` when present)
- Click the circle — mark complete (`- [x]`), move that line to the **end of the file**; **Show Completed** to see / reopen
- Click text to expand; double-click (or right-click → Edit) to rewrite
- Right-click — Mark Complete / Reopen, Move, Edit, Copy, **Delete**
- Reorder — ↑↓ on open items (or context menu)
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

Open the compact bar panel:

```sh
omarchy-shell sd.todo-omarchy toggle
```

Open the normal window (app launcher, menu, or right-click the bar icon):

```sh
omarchy-shell shell summon sd.todo-omarchy
```

To show it in the application launcher:

```sh
cp extra/sd.todo-omarchy.desktop ~/.local/share/applications/
```

Middle-click the bar icon to reload. In the compact panel, **Open Window** (or `w`) pops the same list out into a real window.

Optional menu row: merge `extra/omarchy-menu-todo.jsonc` into `~/.config/omarchy/extensions/omarchy-menu.jsonc`. Do not replace that file.

## Format

- `- item` = open (shown)
- `- [x] item` = completed (line moved to end of file; hidden until Show Completed)
- `## Section` = group header

## Tests

```sh
node --test tests/*.js
```

## Sample data

Screenshots / first-run tabs can use the fake lists in `docs/demo/` (not anyone's real todos).
