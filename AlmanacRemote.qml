import QtQuick
import Quickshell
import Quickshell.Io

// Sequential Almanac HTTP via scripts/almanac-todos.sh. Key never leaves that script.
Item {
  id: root

  property var queue: []
  property bool inFlight: false
  property int token: 0

  signal finished(string op, bool ok, string body, int token)

  function scriptPath() {
    var url = String(Qt.resolvedUrl("scripts/almanac-todos.sh") || "")
    if (url.indexOf("file://") === 0) return url.slice(7)
    return url
  }

  function enqueue(op, args, jobToken) {
    var next = queue.slice()
    next.push({ op: op, args: args, token: jobToken })
    queue = next
    kick()
  }

  function list(calId, jobToken) {
    enqueue("list", ["list", "--cal", String(calId || "")], jobToken)
  }

  function post(calId, bodyPath, jobToken) {
    enqueue("post", ["post", "--cal", String(calId || ""), "--body-file", String(bodyPath || "")], jobToken)
  }

  function patch(calId, uid, bodyPath, jobToken) {
    enqueue("patch", ["patch", "--cal", String(calId || ""), "--uid", String(uid || ""), "--body-file", String(bodyPath || "")], jobToken)
  }

  function remove(calId, uid, jobToken) {
    enqueue("delete", ["delete", "--cal", String(calId || ""), "--uid", String(uid || "")], jobToken)
  }

  function kick() {
    if (inFlight) return
    if (queue.length === 0) return
    var job = queue[0]
    var rest = []
    for (var i = 1; i < queue.length; i++) rest.push(queue[i])
    queue = rest
    inFlight = true
    proc.running = false
    proc.op = job.op
    proc.token = job.token
    proc.command = [scriptPath()].concat(job.args)
    proc.running = true
  }

  function done(ok, body) {
    var op = proc.op
    var jobToken = proc.token
    inFlight = false
    finished(op, ok, body, jobToken)
    kick()
  }

  Process {
    id: proc
    property string op: ""
    property int token: 0
    property string lastBody: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: proc.lastBody = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function (code) {
      var body = proc.lastBody
      proc.lastBody = ""
      var ok = code === 0 && body.indexOf("ERROR:") !== 0
      if (!ok && body.indexOf("ERROR:") !== 0)
        body = body.length ? body : "ERROR:Almanac request failed"
      root.done(ok, body)
    }
  }
}
