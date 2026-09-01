"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { spawnSync } = require("child_process")

const script = path.join(__dirname, "..", "scripts", "git-sync.sh")

function sh(cwd, args, opts = {}) {
  return spawnSync("git", args, {
    cwd,
    encoding: "utf8",
    env: { ...process.env, GIT_AUTHOR_NAME: "Test", GIT_AUTHOR_EMAIL: "test@example.test", GIT_COMMITTER_NAME: "Test", GIT_COMMITTER_EMAIL: "test@example.test" },
    ...opts
  })
}

function setupRepo() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "todo-omarchy-git-"))
  sh(root, ["init", "-b", "master"])
  sh(root, ["config", "user.name", "Test"])
  sh(root, ["config", "user.email", "test@example.test"])
  fs.writeFileSync(path.join(root, "todos.md"), "- existing\n")
  sh(root, ["add", "todos.md"])
  sh(root, ["commit", "-m", "init"])
  return root
}

function runSync(root, message, extraArgs = []) {
  const msgFile = path.join(root, ".commit-msg")
  fs.writeFileSync(msgFile, message)
  return spawnSync("bash", [script, "--dir", root, "--message-file", msgFile, ...extraArgs, "--", path.join(root, "todos.md")], {
    encoding: "utf8",
    env: { ...process.env, GIT_TERMINAL_PROMPT: "0" }
  })
}

test("git-sync.sh is argv-driven and executable as a file", () => {
  assert.equal(path.basename(script), "git-sync.sh")
  assert.ok(fs.existsSync(script))
})

test("commit message with quotes and substitution is stored literally", () => {
  const root = setupRepo()
  const pwn = path.join(root, "pwned")
  fs.writeFileSync(path.join(root, "todos.md"), "- hello\n")
  const message = `Add $(touch pwned) "; echo injected" \``
  const result = runSync(root, message)
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /COMMITTED/)
  assert.equal(fs.existsSync(pwn), false, "shell must not execute the commit message")
  const log = sh(root, ["log", "-1", "--pretty=%B"])
  assert.equal(log.stdout.trim(), message)
  fs.rmSync(root, { recursive: true, force: true })
})

test("without --push the commit stays local even if a remote exists", () => {
  const root = setupRepo()
  const bare = fs.mkdtempSync(path.join(os.tmpdir(), "todo-omarchy-bare-"))
  spawnSync("git", ["init", "--bare", "-b", "master", bare], { encoding: "utf8" })
  sh(root, ["remote", "add", "origin", bare])
  sh(root, ["push", "-u", "origin", "master"])
  fs.writeFileSync(path.join(root, "todos.md"), "- local only\n")
  const result = runSync(root, "Add local only")
  assert.match(result.stdout, /COMMITTED/)
  assert.doesNotMatch(result.stdout, /PUSHED/)
  const remoteLog = spawnSync("git", ["-C", bare, "log", "-1", "--pretty=%s"], { encoding: "utf8" })
  assert.equal(remoteLog.stdout.trim(), "init")
  fs.rmSync(root, { recursive: true, force: true })
  fs.rmSync(bare, { recursive: true, force: true })
})

test("skips a missing extra file and still commits the todo", () => {
  const root = setupRepo()
  fs.writeFileSync(path.join(root, "todos.md"), "- hello\n")
  const missing = path.join(root, "CHANGELOG.md")
  const msgFile = path.join(root, ".commit-msg")
  fs.writeFileSync(msgFile, "Complete hello")
  const result = spawnSync("bash", [
    script, "--dir", root, "--message-file", msgFile, "--",
    path.join(root, "todos.md"), missing
  ], { encoding: "utf8", env: { ...process.env, GIT_TERMINAL_PROMPT: "0" } })
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /COMMITTED/)
  const log = sh(root, ["log", "-1", "--pretty=%s"])
  assert.equal(log.stdout.trim(), "Complete hello")
  fs.rmSync(root, { recursive: true, force: true })
})

test("refuses files outside the git root", () => {
  const root = setupRepo()
  const outside = path.join(os.tmpdir(), "todo-omarchy-outside.md")
  fs.writeFileSync(outside, "- nope\n")
  const msgFile = path.join(root, ".commit-msg")
  fs.writeFileSync(msgFile, "Add nope")
  const result = spawnSync("bash", [script, "--dir", root, "--message-file", msgFile, "--", outside], { encoding: "utf8" })
  assert.match(result.stdout, /FAILED:File outside git root/)
  fs.rmSync(root, { recursive: true, force: true })
  fs.unlinkSync(outside)
})
