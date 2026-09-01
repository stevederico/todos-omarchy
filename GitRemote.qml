import QtQuick
import Quickshell
import Quickshell.Io
import "GitSync.js" as GitSync

// Lives on the bar (and the window). Syncs on open/close, not on a timer.
// Always fetches and pushes when ahead. Fetch failures stay silent.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/todo-omarchy"
  property var queue: []
  property bool inFlight: false

  function scriptPath() {
    var url = String(Qt.resolvedUrl("scripts/git-pull.sh") || "")
    if (url.indexOf("file://") === 0) return url.slice(7)
    return url
  }

  function enqueueAll() {
    var dirs = GitSync.parseSourceDirs(sourcesFile.text())
    var next = queue.slice()
    for (var i = 0; i < dirs.length; i++) {
      if (next.indexOf(dirs[i]) < 0) next.push(dirs[i])
    }
    queue = next
    kick()
  }

  function kick() {
    if (inFlight) return
    if (queue.length === 0) return
    var dir = queue[0]
    var rest = []
    for (var i = 1; i < queue.length; i++) rest.push(queue[i])
    queue = rest
    inFlight = true
    proc.command = [scriptPath(), "--dir", dir, "--push"]
    proc.running = true
  }

  function finished() {
    if (!inFlight) return
    inFlight = false
    kick()
  }

  FileView {
    id: sourcesFile
    path: root.configDir + "/sources.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finished()
    }
    onExited: function () { root.finished() }
  }
}
