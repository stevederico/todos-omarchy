# todo-omarchy

Omarchy bar **and window** app for open items in plain markdown todos. Linux port of [todo-bar](https://github.com/stevederico/todo-bar).

## What it does

- Bar icon with the open-item count; click for the compact panel, right-click for a normal window
- App launcher / Omarchy menu **Todos** opens the same UI as a tiled Hyprland window
- Tabs for multiple files (default: `~/todos.md`, then `~/Documents/todos.md`)
- **Add List** takes a path to another `.md` (e.g. `~/books.md`, `~/marketing/todo.md`)
- Right-click tab → Rename / Reveal / Remove
- Shows open items (`- task`) grouped by `##` section; completed stay hidden until **Show Completed**
- **+** / `n` — new to-do is prepended at the top of the first section (pre-header `To-Dos` when present)
- Click the circle — mark complete (`- [x]`), move that line to the **end of the file**; **Show Completed** to see / reopen
- Each add/edit/complete/delete **commits**, then **pushes** if the file's repo has an upstream
- Click text to expand; double-click (or right-click → Edit) to rewrite
- Right-click — Mark Complete / Reopen, Move, Edit, Copy, **Delete**
- Reorder — ↑↓ on open items (or context menu)
- Live-reloads when the active file changes; tabs persist in `~/.config/todo-omarchy/sources.json`

## Install

```sh
omarchy plugin add https://github.com/stevederico/todo-omarchy.git --enable --yes
omarchy bar put sd.todo-omarchy --before omarchy.clock --section right
```

Local checkout (copy the repository root, not a symlink):

```sh
PLUGIN_ID="sd.todo-omarchy"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
mkdir -p "$PLUGIN_DIR"
cp -a ~/Projects/todo-omarchy/. "$PLUGIN_DIR/"
# drop git metadata if you copied a checkout you do not want the plugin manager to own
omarchy plugin validate "$PLUGIN_DIR"
omarchy plugin enable "$PLUGIN_ID"
omarchy bar put sd.todo-omarchy --before omarchy.clock --section right
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

Markdown mutations are pure JS and run without QML:

```sh
node --test tests/test_document.js
```

## Sample data

Screenshots / first-run tabs can use the fake lists in `docs/demo/` (not anyone's real todos).
