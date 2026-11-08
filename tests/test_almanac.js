"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const http = require("http")
const os = require("os")
const path = require("path")
const { spawn } = require("child_process")
const crypto = require("crypto")

const Almanac = require("../Almanac.js")
const script = path.join(__dirname, "..", "scripts", "almanac-todos.sh")
const TOKEN = crypto.createHash("sha256").update("test-key" + "almanac-auth-v1").digest("hex")

test("parseCalendars keeps id and name only", () => {
  const rows = Almanac.parseCalendars(JSON.stringify([
    { id: "cal_1", name: "Almanac", key: "secret", write: "https://example/v1/c/cal_1/events" },
    { id: "cal_2", name: "  Roadmap  " }
  ]))
  assert.deepEqual(rows, [
    { id: "cal_1", name: "Agent Cloud" },
    { id: "cal_2", name: "Roadmap" }
  ])
  assert.equal(JSON.stringify(rows).includes("secret"), false)
})

test("parseCalendars accepts a wrapped or single object", () => {
  assert.deepEqual(Almanac.parseCalendars(JSON.stringify({
    calendars: [{ id: "cal_x", name: "X" }]
  })), [{ id: "cal_x", name: "X" }])
  assert.deepEqual(Almanac.parseCalendars(JSON.stringify({ id: "cal_y" })), [{
    id: "cal_y",
    name: "Agent Cloud"
  }])
  assert.deepEqual(Almanac.parseCalendars(""), [])
  assert.deepEqual(Almanac.parseCalendars("not-json"), [])
})

test("almanac path and source helpers", () => {
  assert.equal(Almanac.isAlmanacPath("almanac"), true)
  assert.equal(Almanac.isAlmanacPath("almanac:cal_1"), true)
  assert.equal(Almanac.isAlmanacPath("~/todos.md"), false)
  assert.equal(Almanac.pathCalendarId("almanac"), "")
  assert.equal(Almanac.pathCalendarId("almanac:cal_1"), "cal_1")
  assert.equal(Almanac.isAlmanacSource({ kind: "almanac", calendarId: "cal_1" }), true)
  assert.equal(Almanac.isAlmanacSource({ path: "almanac:cal_1" }), true)
  assert.equal(Almanac.isAlmanacSource({ path: "/tmp/todos.md" }), false)
  assert.equal(Almanac.calendarIdOf({ kind: "almanac", calendarId: "cal_9" }), "cal_9")
  assert.equal(Almanac.calendarIdOf({ path: "almanac:cal_8" }), "cal_8")
  assert.equal(Almanac.isAlmanacPath("agentcloud"), true)
  assert.equal(Almanac.isAlmanacPath("agentcloud:cal_1"), true)
  assert.equal(Almanac.isAlmanacPath("agentcloudx"), false)
  assert.equal(Almanac.pathCalendarId("agentcloud"), "")
  assert.equal(Almanac.pathCalendarId("agentcloud:cal_7"), "cal_7")
})

test("the old default tab names show as Agent Cloud", () => {
  assert.equal(Almanac.displayName("Almanac"), "Agent Cloud")
  assert.equal(Almanac.displayName("Dottie"), "Agent Cloud")
  assert.equal(Almanac.displayName(""), "Agent Cloud")
  assert.equal(Almanac.displayName(" Groceries "), "Groceries")
  assert.equal(Almanac.makeSource({ id: "cal_1", name: "Almanac" }, "s").title, "Agent Cloud")
})

test("resolveCalendar matches id or first", () => {
  const cals = [{ id: "cal_a", name: "A" }, { id: "cal_b", name: "B" }]
  assert.deepEqual(Almanac.resolveCalendar(cals, ""), cals[0])
  assert.deepEqual(Almanac.resolveCalendar(cals, "cal_b"), cals[1])
  assert.equal(Almanac.resolveCalendar(cals, "missing"), null)
  assert.equal(Almanac.resolveCalendar([], ""), null)
})

test("defaultTabId prefers the Almanac source", () => {
  const sources = [
    { id: "todos", path: "/tmp/todos.md" },
    { id: "alm", kind: "almanac", calendarId: "cal_1" }
  ]
  assert.equal(Almanac.defaultTabId(sources), "alm")
  assert.equal(Almanac.defaultTabId([{ id: "todos", path: "/tmp/todos.md" }]), "todos")
  assert.equal(Almanac.defaultTabId([]), "")
})

test("ensureSource prepends Almanac once", () => {
  const files = [{ id: "s1", title: "Todos", path: "/tmp/todos.md" }]
  const cals = [{ id: "cal_1", name: "Almanac" }]
  const next = Almanac.ensureSource(files, cals, () => "new")
  assert.equal(next.length, 2)
  assert.equal(next[0].kind, "almanac")
  assert.equal(next[0].calendarId, "cal_1")
  assert.equal(next[0].title, "Agent Cloud")
  assert.equal(next[1].path, "/tmp/todos.md")
  assert.equal(Almanac.ensureSource(next, cals, () => "again").length, 2)
  assert.deepEqual(Almanac.ensureSource(files, [], () => "x"), files)
})

test("parseTodos groups by first tag, open stay first", () => {
  const sections = Almanac.parseTodos({
    todos: [
      { uid: "todo-a", title: "Milk", done: false, tags: ["home"], rev: 5 },
      { uid: "todo-b", title: "Call", done: true },
      { uid: "todo-c", title: "Pack", done: false, tags: ["home", "travel"] }
    ]
  })
  assert.equal(sections.length, 2)
  assert.equal(sections[0].title, "Home")
  assert.deepEqual(sections[0].items.map((i) => i.text), ["Milk", "Pack"])
  assert.equal(sections[0].items[0].uid, "todo-a")
  assert.equal(sections[0].items[0].rev, 5)
  assert.equal(sections[0].items[1].rev, 0)
  assert.equal(sections[1].title, "To-Dos")
  assert.equal(sections[1].items[0].isCompleted, true)
  assert.equal(Almanac.countOpen(sections), 2)
  assert.equal(Almanac.countCompleted(sections), 1)
})

test("errorMessage reads ERROR and JSON", () => {
  assert.equal(Almanac.errorMessage("ERROR:not found"), "not found")
  assert.equal(Almanac.errorMessage(JSON.stringify({ error: "title is required" })), "title is required")
  assert.equal(Almanac.errorMessage(""), "Agent Cloud request failed")
  assert.equal(Almanac.errorMessage("ERROR:conflict\n"), "Changed elsewhere")
})

test("conflictInfo reads the server copy after the conflict line", () => {
  assert.equal(Almanac.isConflict('ERROR:conflict\n{"deleted":true,"current":null}\n'), true)
  assert.equal(Almanac.isConflict("ERROR:not found\n"), false)
  assert.deepEqual(Almanac.conflictInfo('ERROR:conflict\n{"deleted":true,"current":null}\n'), { deleted: true, current: null })
  assert.deepEqual(Almanac.conflictInfo("ERROR:conflict\n"), { deleted: false, current: null })
})

test("conflictCopyTitle marks the copy and fits the title cap", () => {
  assert.equal(Almanac.conflictCopyTitle(" Milk "), "Milk (conflict copy)")
  const long = Almanac.conflictCopyTitle("\u00e9".repeat(512))
  assert.ok(Buffer.byteLength(long) <= 512)
  assert.match(long, / \(conflict copy\)$/)
  assert.ok(Buffer.byteLength(Almanac.conflictCopyTitle("\u{1F600}".repeat(200))) <= 512)
})

test("conflictRetry keeps an edit as a new todo", () => {
  const job = { op: "post", cal: "cal_1", uid: "todo-1", payload: { uid: "todo-1", body: { title: "Mine", done: false } } }
  assert.deepEqual(Almanac.conflictRetry(job, { deleted: false, current: { uid: "todo-1", title: "Theirs", rev: 9 } }), {
    op: "post",
    payload: { body: { title: "Mine (conflict copy)", done: false } }
  })
  assert.deepEqual(Almanac.conflictRetry(job, { deleted: true, current: null }).payload.body.title, "Mine (conflict copy)")
})

test("conflictRetry sends a toggle again on the server copy", () => {
  const job = { op: "post", cal: "cal_1", uid: "todo-1", payload: { uid: "todo-1", toggle: true, body: { title: "Old", done: true } } }
  assert.deepEqual(Almanac.conflictRetry(job, { deleted: false, current: { uid: "todo-1", title: "New", done: false, rev: 9 } }), {
    op: "post",
    payload: { uid: "todo-1", toggle: true, rev: 9, body: { title: "New", done: true } }
  })
  assert.equal(Almanac.conflictRetry(job, { deleted: false, current: { uid: "todo-1", title: "New", done: true, rev: 9 } }), null)
  assert.equal(Almanac.conflictRetry(job, { deleted: true, current: null }), null)
  assert.equal(Almanac.conflictRetry(job, { deleted: false, current: null }), null)
})

test("conflictRetry keeps the server copy on a delete", () => {
  assert.equal(Almanac.conflictRetry({ op: "delete", uid: "todo-1", payload: { uid: "todo-1" } }, { deleted: false, current: { rev: 9 } }), null)
})

function listen(server) {
  return new Promise((resolve, reject) => {
    server.listen(0, "127.0.0.1", () => resolve(server.address().port))
    server.on("error", reject)
  })
}

function writeConfig(dir, port, extra = {}) {
  const file = path.join(dir, "hosted-calendars.json")
  fs.writeFileSync(file, JSON.stringify([{
    id: extra.id || "cal_test",
    name: "Test",
    key: extra.key || "test-key",
    write: `http://127.0.0.1:${port}/v1/c/${extra.id || "cal_test"}/events`
  }]) + "\n")
  return file
}

function runScript(args, env) {
  return new Promise((resolve) => {
    const child = spawn("bash", [script, ...args], {
      env: { ...process.env, ...env }
    })
    let stdout = ""
    let stderr = ""
    child.stdout.on("data", (c) => { stdout += c })
    child.stderr.on("data", (c) => { stderr += c })
    child.on("close", (status) => resolve({ status, stdout, stderr }))
  })
}

test("almanac-todos.sh lists with bearer and user-agent", async () => {
  const seen = []
  const server = http.createServer((req, res) => {
    seen.push({
      method: req.method,
      url: req.url,
      ua: req.headers["user-agent"],
      auth: req.headers.authorization
    })
    res.writeHead(200, { "content-type": "application/json" })
    res.end(JSON.stringify({ todos: [{ uid: "todo-1", title: "Milk", done: false, tags: [] }] }))
  })
  const port = await listen(server)
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "agentcloud-todos-almanac-"))
  const config = writeConfig(dir, port)
  const result = await runScript(["list", "--cal", "cal_test"], {
    ALMANAC_CONFIG: config,
    ALMANAC_BASE: `http://127.0.0.1:${port}`
  })
  server.close()
  fs.rmSync(dir, { recursive: true, force: true })
  assert.equal(result.status, 0, result.stderr + result.stdout)
  assert.match(result.stdout, /Milk/)
  assert.equal(seen[0].method, "GET")
  assert.equal(seen[0].url, "/v1/c/cal_test/todos")
  assert.equal(seen[0].auth, "Bearer " + TOKEN)
  assert.match(seen[0].ua, /agentcloud-todos/)
  assert.equal(result.stdout.includes("test-key"), false)
})

test("almanac-todos.sh posts a title and patches done", async () => {
  const seen = []
  const server = http.createServer((req, res) => {
    let raw = ""
    req.on("data", (c) => { raw += c })
    req.on("end", () => {
      seen.push({ method: req.method, url: req.url, body: raw })
      if (req.method === "GET" && !req.url.includes("/todos")) {
        res.writeHead(200, { "content-type": "application/json" })
        res.end(JSON.stringify({ id: "cal_test", feed: "plain" }))
        return
      }
      if (req.method === "POST") {
        res.writeHead(201, { "content-type": "application/json" })
        res.end(JSON.stringify({ uid: "todo-new", title: "Call Bob", done: false }))
        return
      }
      res.writeHead(200, { "content-type": "application/json" })
      res.end(JSON.stringify({ uid: "todo-new", title: "Call Bob", done: true }))
    })
  })
  const port = await listen(server)
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "agentcloud-todos-almanac-"))
  const config = writeConfig(dir, port)
  const body = path.join(dir, "body.json")
  fs.writeFileSync(body, JSON.stringify({ title: "Call Bob" }))
  const created = await runScript(["post", "--cal", "cal_test", "--body-file", body], { ALMANAC_CONFIG: config })
  fs.writeFileSync(body, JSON.stringify({ title: "Call Bob", done: true }))
  const patched = await runScript(["patch", "--cal", "cal_test", "--uid", "todo-new", "--body-file", body], { ALMANAC_CONFIG: config })
  server.close()
  fs.rmSync(dir, { recursive: true, force: true })
  assert.equal(created.status, 0, created.stdout)
  assert.match(created.stdout, /todo-new/)
  assert.equal(patched.status, 0, patched.stdout)
  assert.equal(seen[1].method, "POST")
  assert.equal(seen[1].url, "/v1/c/cal_test/todos")
  assert.equal(seen[3].method, "PUT")
  assert.equal(seen[3].url, "/v1/c/cal_test/todos/todo-new")
  assert.match(seen[3].body, /"done":\s*true/)
})

test("almanac-todos.sh puts a post with a uid to that todo", async () => {
  const seen = []
  const server = http.createServer((req, res) => {
    let raw = ""
    req.on("data", (c) => { raw += c })
    req.on("end", () => {
      seen.push({ method: req.method, url: req.url, body: raw })
      if (req.method === "GET" && !req.url.includes("/todos")) {
        res.writeHead(200, { "content-type": "application/json" })
        res.end(JSON.stringify({ id: "cal_test", feed: "plain" }))
        return
      }
      res.writeHead(200, { "content-type": "application/json" })
      res.end(JSON.stringify({ uid: "todo-new", title: "Call Bob", done: true }))
    })
  })
  const port = await listen(server)
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "agentcloud-todos-almanac-"))
  const config = writeConfig(dir, port)
  const body = path.join(dir, "body.json")
  fs.writeFileSync(body, JSON.stringify({ uid: "todo-new", title: "Call Bob", done: true }))
  const result = await runScript(["post", "--cal", "cal_test", "--body-file", body], { ALMANAC_CONFIG: config })
  server.close()
  fs.rmSync(dir, { recursive: true, force: true })
  assert.equal(result.status, 0, result.stdout)
  assert.equal(seen[1].method, "PUT")
  assert.equal(seen[1].url, "/v1/c/cal_test/todos/todo-new")
  assert.equal(seen[1].body.includes("uid"), false)
  assert.match(seen[1].body, /"done":\s*true/)
})

test("almanac-todos.sh sends --rev as If-Match and maps 412 to conflict", async () => {
  const seen = []
  const server = http.createServer((req, res) => {
    req.resume()
    req.on("end", () => {
      seen.push({ method: req.method, url: req.url, ifMatch: req.headers["if-match"] })
      if (req.method === "GET") {
        res.writeHead(200, { "content-type": "application/json" })
        res.end(JSON.stringify({ id: "cal_test", feed: "plain" }))
        return
      }
      res.writeHead(412, { "content-type": "application/json" })
      res.end(JSON.stringify({ error: "changed elsewhere", deleted: false, current: { uid: "todo-1", title: "New", rev: 9 } }))
    })
  })
  const port = await listen(server)
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "agentcloud-todos-almanac-"))
  const config = writeConfig(dir, port)
  const body = path.join(dir, "body.json")
  fs.writeFileSync(body, JSON.stringify({ uid: "todo-1", title: "Old", done: true }))
  const posted = await runScript(["post", "--cal", "cal_test", "--rev", "7", "--body-file", body], { ALMANAC_CONFIG: config })
  const removed = await runScript(["delete", "--cal", "cal_test", "--uid", "todo-1", "--rev", "7"], { ALMANAC_CONFIG: config })
  server.close()
  fs.rmSync(dir, { recursive: true, force: true })
  assert.equal(posted.stdout.split("\n")[0], "ERROR:conflict")
  assert.notEqual(posted.status, 0)
  assert.equal(removed.stdout.split("\n")[0], "ERROR:conflict")
  assert.deepEqual(Almanac.conflictInfo(posted.stdout), {
    deleted: false,
    current: { uid: "todo-1", title: "New", rev: 9 }
  })
  const writes = seen.filter((row) => row.method !== "GET")
  assert.deepEqual(writes.map((row) => [row.method, row.url, row.ifMatch]), [
    ["PUT", "/v1/c/cal_test/todos/todo-1", '"7"'],
    ["DELETE", "/v1/c/cal_test/todos/todo-1", '"7"']
  ])
  assert.equal(Almanac.isConflict(posted.stdout), true)
  assert.equal(Almanac.errorMessage(posted.stdout), "Changed elsewhere")
})

test("almanac-todos.sh maps 401 to ERROR without leaking the key", async () => {
  const server = http.createServer((_req, res) => {
    res.writeHead(401, { "content-type": "application/json" })
    res.end(JSON.stringify({ error: "unauthorized" }))
  })
  const port = await listen(server)
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "agentcloud-todos-almanac-"))
  const config = writeConfig(dir, port)
  const result = await runScript(["list"], { ALMANAC_CONFIG: config })
  server.close()
  fs.rmSync(dir, { recursive: true, force: true })
  assert.notEqual(result.status, 0)
  assert.match(result.stdout, /^ERROR:unauthorized/)
  assert.equal(result.stdout.includes("test-key"), false)
})

function almanacBin() {
  return process.env.AGENTCLOUD_BIN || process.env.ALMANAC_BIN
    || ["agentcloud/target/debug/agentcloud", "almanac/target/debug/almanac"].map((rel) => path.join(process.env.HOME, "Projects", rel)).find((p) => fs.existsSync(p))
    || path.join(process.env.HOME, "Projects/agentcloud/target/debug/agentcloud")
}

function runBin(bin, args, input, env) {
  return new Promise((resolve) => {
    const child = spawn(bin, args, { env: { ...process.env, ...env } })
    let stdout = ""
    child.stdout.on("data", (c) => { stdout += c })
    child.stdin.end(input)
    child.on("close", (status) => resolve({ status, stdout: stdout.trim() }))
  })
}

test("almanac-todos.sh seals a post and opens the reply", async () => {
  const bin = almanacBin()
  if (!fs.existsSync(bin)) return
  const seen = []
  const server = http.createServer((req, res) => {
    let raw = ""
    req.on("data", (c) => { raw += c })
    req.on("end", () => {
      seen.push({ method: req.method, url: req.url, body: raw })
      if (req.method === "GET") {
        res.writeHead(200, { "content-type": "application/json" })
        res.end(JSON.stringify({ id: "cal_test", feed: "seal" }))
        return
      }
      res.writeHead(201, { "content-type": "application/json" })
      const sent = JSON.parse(raw)
      res.end(JSON.stringify({ uid: req.url.split("/").pop(), seal: sent.seal }))
    })
  })
  const port = await listen(server)
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "agentcloud-todos-almanac-"))
  const config = writeConfig(dir, port)
  const body = path.join(dir, "body.json")
  fs.writeFileSync(body, JSON.stringify({ title: "Call Bob" }))
  const created = await runScript(["post", "--cal", "cal_test", "--body-file", body], {
    ALMANAC_CONFIG: config,
    ALMANAC_BIN: bin
  })
  server.close()
  fs.rmSync(dir, { recursive: true, force: true })
  assert.equal(created.status, 0, created.stderr + created.stdout)
  const put = seen.find((row) => row.method === "PUT")
  assert.ok(put)
  assert.match(put.url, /^\/v1\/c\/cal_test\/todos\/todo-/)
  const sent = JSON.parse(put.body)
  assert.match(sent.seal, /^alm1\./)
  assert.equal(put.body.includes("Call Bob"), false)
  assert.match(created.stdout, /Call Bob/)
  assert.equal(created.stdout.includes("test-key"), false)
})

test("almanac-todos.sh opens a sealed list and merges a patch", async () => {
  const bin = almanacBin()
  if (!fs.existsSync(bin)) return
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "agentcloud-todos-almanac-"))
  const config = writeConfig(dir, 9)
  const sealed = await runBin(bin, ["seal", "--cal", "cal_test", "--kind", "todo", "--uid", "todo-milk"], JSON.stringify({
    uid: "todo-milk",
    title: "Milk",
    done: false
  }), { ALMANAC_CREDS: config })
  assert.equal(sealed.status, 0, sealed.stdout)
  const store = { "todo-milk": sealed.stdout }
  const seen = []
  const server = http.createServer((req, res) => {
    let raw = ""
    req.on("data", (c) => { raw += c })
    req.on("end", () => {
      seen.push({ method: req.method, url: req.url, body: raw })
      if (req.url === "/v1/c/cal_test") {
        res.writeHead(200, { "content-type": "application/json" })
        res.end(JSON.stringify({ id: "cal_test", feed: "seal" }))
        return
      }
      if (req.method === "GET" && req.url === "/v1/c/cal_test/todos") {
        res.writeHead(200, { "content-type": "application/json" })
        res.end(JSON.stringify({ todos: [{ uid: "todo-milk", seal: store["todo-milk"] }] }))
        return
      }
      if (req.method === "GET") {
        res.writeHead(200, { "content-type": "application/json" })
        res.end(JSON.stringify({ uid: "todo-milk", seal: store["todo-milk"] }))
        return
      }
      const sent = JSON.parse(raw)
      store["todo-milk"] = sent.seal
      res.writeHead(200, { "content-type": "application/json" })
      res.end(JSON.stringify({ uid: "todo-milk", seal: sent.seal }))
    })
  })
  const port = await listen(server)
  fs.writeFileSync(config, JSON.stringify([{
    id: "cal_test",
    name: "Test",
    key: "test-key",
    write: `http://127.0.0.1:${port}/v1/c/cal_test/events`
  }]) + "\n")
  const listed = await runScript(["list", "--cal", "cal_test"], { ALMANAC_CONFIG: config, ALMANAC_BIN: bin })
  const body = path.join(dir, "body.json")
  fs.writeFileSync(body, JSON.stringify({ done: true }))
  const patched = await runScript(["patch", "--cal", "cal_test", "--uid", "todo-milk", "--body-file", body], {
    ALMANAC_CONFIG: config,
    ALMANAC_BIN: bin
  })
  server.close()
  const opened = await runBin(bin, ["open", "--cal", "cal_test", "--kind", "todo", "--uid", "todo-milk"], store["todo-milk"], {
    ALMANAC_CREDS: config
  })
  fs.rmSync(dir, { recursive: true, force: true })
  assert.equal(listed.status, 0, listed.stderr + listed.stdout)
  assert.match(listed.stdout, /Milk/)
  assert.equal(listed.stdout.includes("alm1."), false)
  assert.equal(patched.status, 0, patched.stderr + patched.stdout)
  assert.match(patched.stdout, /Milk/)
  const put = seen.find((row) => row.method === "PUT")
  assert.equal(put.body.includes("Milk"), false)
  assert.equal(JSON.parse(opened.stdout).done, true)
  assert.equal(JSON.parse(opened.stdout).title, "Milk")
})
