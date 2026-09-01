import QtQuick
import Quickshell
import Quickshell.Io
import "Settings.js" as Settings
import "GitSync.js" as GitSync

// Lives on the bar. Pulls every list repo on a timer. Pushes when Git: push.
// Fetch failures stay silent and retry next tick.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/todo-omarchy"
  property int intervalMs: 30000
  property bool gitPush: false
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
    var args = [scriptPath(), "--dir", dir]
    if (gitPush) args.push("--push")
    proc.command = args
    proc.running = true
  }

  function finished() {
    if (!inFlight) return
    inFlight = false
    kick()
  }

  Timer {
    interval: root.intervalMs
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.enqueueAll()
  }

  FileView {
    id: sourcesFile
    path: root.configDir + "/sources.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.enqueueAll()
  }

  FileView {
    id: settingsFile
    path: root.configDir + "/settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var next = Settings.parseSettings(text())
      root.gitPush = next.gitPush === true
    }
    onLoadFailed: root.gitPush = false
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
