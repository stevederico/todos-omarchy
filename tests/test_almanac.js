"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const http = require("http")
const os = require("os")
const path = require("path")
const { spawn } = require("child_process")

const Almanac = require("../Almanac.js")
const script = path.join(__dirname, "..", "scripts", "almanac-todos.sh")

test("parseCalendars keeps id and name only", () => {
  const rows = Almanac.parseCalendars(JSON.stringify([
    { id: "cal_1", name: "Almanac", key: "secret", write: "https://example/v1/c/cal_1/events" },
    { id: "cal_2", name: "  Roadmap  " }
  ]))
  assert.deepEqual(rows, [
    { id: "cal_1", name: "Almanac" },
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
    name: "Almanac"
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
})

test("resolveCalendar matches id or first", () => {
  const cals = [{ id: "cal_a", name: "A" }, { id: "cal_b", name: "B" }]
  assert.deepEqual(Almanac.resolveCalendar(cals, ""), cals[0])
  assert.deepEqual(Almanac.resolveCalendar(cals, "cal_b"), cals[1])
  assert.equal(Almanac.resolveCalendar(cals, "missing"), null)
  assert.equal(Almanac.resolveCalendar([], ""), null)
})

test("ensureSource prepends Almanac once", () => {
  const files = [{ id: "s1", title: "Todos", path: "/tmp/todos.md" }]
  const cals = [{ id: "cal_1", name: "Almanac" }]
  const next = Almanac.ensureSource(files, cals, () => "new")
  assert.equal(next.length, 2)
  assert.equal(next[0].kind, "almanac")
  assert.equal(next[0].calendarId, "cal_1")
  assert.equal(next[1].path, "/tmp/todos.md")
  assert.equal(Almanac.ensureSource(next, cals, () => "again").length, 2)
  assert.deepEqual(Almanac.ensureSource(files, [], () => "x"), files)
})

test("parseTodos groups by first tag, open stay first", () => {
  const sections = Almanac.parseTodos({
    todos: [
      { uid: "todo-a", title: "Milk", done: false, tags: ["home"] },
      { uid: "todo-b", title: "Call", done: true },
      { uid: "todo-c", title: "Pack", done: false, tags: ["home", "travel"] }
    ]
  })
  assert.equal(sections.length, 2)
  assert.equal(sections[0].title, "Home")
  assert.deepEqual(sections[0].items.map((i) => i.text), ["Milk", "Pack"])
  assert.equal(sections[0].items[0].uid, "todo-a")
  assert.equal(sections[1].title, "To-Dos")
  assert.equal(sections[1].items[0].isCompleted, true)
  assert.equal(Almanac.countOpen(sections), 2)
  assert.equal(Almanac.countCompleted(sections), 1)
})

test("errorMessage reads ERROR and JSON", () => {
  assert.equal(Almanac.errorMessage("ERROR:not found"), "not found")
  assert.equal(Almanac.errorMessage(JSON.stringify({ error: "title is required" })), "title is required")
  assert.equal(Almanac.errorMessage(""), "Almanac request failed")
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
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dottie-todos-omarchy-almanac-"))
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
  assert.equal(seen[0].auth, "Bearer test-key")
  assert.match(seen[0].ua, /dottie-todos-omarchy/)
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
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dottie-todos-omarchy-almanac-"))
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
  assert.equal(seen[3].method, "POST")
  assert.equal(seen[3].url, "/v1/c/cal_test/todos")
  assert.match(seen[3].body, /todo-new/)
})

test("almanac-todos.sh posts done with uid on the collection", async () => {
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
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dottie-todos-omarchy-almanac-"))
  const config = writeConfig(dir, port)
  const body = path.join(dir, "body.json")
  fs.writeFileSync(body, JSON.stringify({ uid: "todo-new", title: "Call Bob", done: true }))
  const result = await runScript(["post", "--cal", "cal_test", "--body-file", body], { ALMANAC_CONFIG: config })
  server.close()
  fs.rmSync(dir, { recursive: true, force: true })
  assert.equal(result.status, 0, result.stdout)
  assert.equal(seen[1].method, "POST")
  assert.equal(seen[1].url, "/v1/c/cal_test/todos")
  assert.match(seen[1].body, /"uid":"todo-new"/)
  assert.match(seen[1].body, /"done":true/)
})

test("almanac-todos.sh maps 401 to ERROR without leaking the key", async () => {
  const server = http.createServer((_req, res) => {
    res.writeHead(401, { "content-type": "application/json" })
    res.end(JSON.stringify({ error: "unauthorized" }))
  })
  const port = await listen(server)
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dottie-todos-omarchy-almanac-"))
  const config = writeConfig(dir, port)
  const result = await runScript(["list"], { ALMANAC_CONFIG: config })
  server.close()
  fs.rmSync(dir, { recursive: true, force: true })
  assert.notEqual(result.status, 0)
  assert.match(result.stdout, /^ERROR:unauthorized/)
  assert.equal(result.stdout.includes("test-key"), false)
})

function almanacBin() {
  return process.env.ALMANAC_BIN
    || path.join(process.env.HOME, "Projects/almanac/target/debug/almanac")
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
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dottie-todos-omarchy-almanac-"))
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
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dottie-todos-omarchy-almanac-"))
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
