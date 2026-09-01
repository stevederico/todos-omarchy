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
  property bool skipRebase: false
  property string lastOutcome: ""

  signal syncFinished(string outcome)

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
    var args = [scriptPath(), "--dir", dir, "--push"]
    if (root.skipRebase) args.push("--skip-rebase")
    proc.command = args
    proc.running = true
  }

  function classify(out) {
    if (out.indexOf("DIVERGED") >= 0) return "DIVERGED"
    if (out.indexOf("REBASED_PUSHED") >= 0) return "REBASED_PUSHED"
    if (out.indexOf("REBASED") >= 0) return "REBASED"
    if (out.indexOf("PULLED") >= 0) return "PULLED"
    if (out.indexOf("PUSHED") >= 0) return "PUSHED"
    if (out.indexOf("BUSY") >= 0) return "BUSY"
    return "ok"
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
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
  }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var outcome = root.classify(String(text || ""))
        root.lastOutcome = outcome
        root.syncFinished(outcome)
        root.finished()
      }
    }
    onExited: function () { root.finished() }
  }
}
