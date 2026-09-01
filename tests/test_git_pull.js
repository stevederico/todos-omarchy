"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { spawnSync } = require("child_process")

const script = path.join(__dirname, "..", "scripts", "git-pull.sh")

function gitEnv() {
  return {
    ...process.env,
    GIT_AUTHOR_NAME: "Test",
    GIT_AUTHOR_EMAIL: "test@example.test",
    GIT_COMMITTER_NAME: "Test",
    GIT_COMMITTER_EMAIL: "test@example.test",
    GIT_TERMINAL_PROMPT: "0"
  }
}

function sh(cwd, args, opts = {}) {
  return spawnSync("git", args, {
    cwd,
    encoding: "utf8",
    env: gitEnv(),
    ...opts
  })
}

function runPull(dir, extra = []) {
  return spawnSync("bash", [script, "--dir", dir, ...extra], {
    encoding: "utf8",
    env: gitEnv()
  })
}

function initRepo(root) {
  sh(root, ["init", "-b", "master"])
  sh(root, ["config", "user.name", "Test"])
  sh(root, ["config", "user.email", "test@example.test"])
  fs.writeFileSync(path.join(root, "todos.md"), "- existing\n")
  sh(root, ["add", "todos.md"])
  sh(root, ["commit", "-m", "init"])
}

function setupRemotePair() {
  const local = fs.mkdtempSync(path.join(os.tmpdir(), "todo-omarchy-pull-local-"))
  const bare = fs.mkdtempSync(path.join(os.tmpdir(), "todo-omarchy-pull-bare-"))
  const other = fs.mkdtempSync(path.join(os.tmpdir(), "todo-omarchy-pull-other-"))
  spawnSync("git", ["init", "--bare", "-b", "master", bare], { encoding: "utf8", env: gitEnv() })
  initRepo(local)
  sh(local, ["remote", "add", "origin", bare])
  sh(local, ["push", "-u", "origin", "master"])
  const clone = spawnSync("git", ["clone", bare, other], { encoding: "utf8", env: gitEnv() })
  assert.equal(clone.status, 0, clone.stderr)
  sh(other, ["config", "user.name", "Test"])
  sh(other, ["config", "user.email", "test@example.test"])
  return { local, bare, other }
}

function cleanup(dirs) {
  for (const dir of dirs) fs.rmSync(dir, { recursive: true, force: true })
}

test("git-pull.sh is argv-driven and executable as a file", () => {
  assert.equal(path.basename(script), "git-pull.sh")
  assert.ok(fs.existsSync(script))
})

test("missing --dir is a usage failure", () => {
  const result = spawnSync("bash", [script], { encoding: "utf8", env: gitEnv() })
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /FAILED:usage/)
})

test("non-git directory reports NOT_A_REPO", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "todo-omarchy-pull-none-"))
  const result = runPull(dir)
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /NOT_A_REPO/)
  cleanup([dir])
})

test("repo without upstream reports NO_UPSTREAM", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "todo-omarchy-pull-noremote-"))
  initRepo(root)
  const result = runPull(root)
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /NO_UPSTREAM/)
  cleanup([root])
})

test("up-to-date clone reports UP_TO_DATE", () => {
  const pair = setupRemotePair()
  const result = runPull(pair.local)
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /UP_TO_DATE/)
  cleanup([pair.local, pair.bare, pair.other])
})

test("fast-forwards when behind a clean remote", () => {
  const pair = setupRemotePair()
  fs.writeFileSync(path.join(pair.other, "todos.md"), "- from remote\n")
  sh(pair.other, ["add", "todos.md"])
  sh(pair.other, ["commit", "-m", "remote update"])
  sh(pair.other, ["push", "origin", "master"])
  const result = runPull(pair.local)
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /PULLED/)
  const text = fs.readFileSync(path.join(pair.local, "todos.md"), "utf8")
  assert.equal(text, "- from remote\n")
  cleanup([pair.local, pair.bare, pair.other])
})

test("local-ahead clone reports AHEAD and does not rewrite files", () => {
  const pair = setupRemotePair()
  fs.writeFileSync(path.join(pair.local, "todos.md"), "- local only\n")
  sh(pair.local, ["add", "todos.md"])
  sh(pair.local, ["commit", "-m", "local commit"])
  const result = runPull(pair.local)
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /AHEAD/)
  const text = fs.readFileSync(path.join(pair.local, "todos.md"), "utf8")
  assert.equal(text, "- local only\n")
  cleanup([pair.local, pair.bare, pair.other])
})

test("diverged histories report DIVERGED and keep the local file", () => {
  const pair = setupRemotePair()
  fs.writeFileSync(path.join(pair.local, "todos.md"), "- local branch\n")
  sh(pair.local, ["add", "todos.md"])
  sh(pair.local, ["commit", "-m", "local commit"])
  fs.writeFileSync(path.join(pair.other, "todos.md"), "- remote branch\n")
  sh(pair.other, ["add", "todos.md"])
  sh(pair.other, ["commit", "-m", "remote commit"])
  sh(pair.other, ["push", "origin", "master"])
  const result = runPull(pair.local)
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /DIVERGED/)
  const text = fs.readFileSync(path.join(pair.local, "todos.md"), "utf8")
  assert.equal(text, "- local branch\n")
  cleanup([pair.local, pair.bare, pair.other])
})

test("diverged non-overlapping commits rebase then push", () => {
  const pair = setupRemotePair()
  fs.writeFileSync(path.join(pair.local, "todos.md"), "- local only\n")
  sh(pair.local, ["add", "todos.md"])
  sh(pair.local, ["commit", "-m", "local commit"])
  fs.writeFileSync(path.join(pair.other, "notes.md"), "from remote\n")
  sh(pair.other, ["add", "notes.md"])
  sh(pair.other, ["commit", "-m", "remote commit"])
  sh(pair.other, ["push", "origin", "master"])
  const result = runPull(pair.local, ["--push"])
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /REBASED_PUSHED|REBASED/)
  const text = fs.readFileSync(path.join(pair.local, "todos.md"), "utf8")
  assert.equal(text, "- local only\n")
  assert.ok(fs.existsSync(path.join(pair.local, "notes.md")))
  cleanup([pair.local, pair.bare, pair.other])
})

test("ahead with --push pushes and reports PUSHED", () => {
  const pair = setupRemotePair()
  fs.writeFileSync(path.join(pair.local, "todos.md"), "- local only\n")
  sh(pair.local, ["add", "todos.md"])
  sh(pair.local, ["commit", "-m", "local commit"])
  const result = runPull(pair.local, ["--push"])
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /PUSHED/)
  const remoteLog = spawnSync("git", ["-C", pair.bare, "log", "-1", "--pretty=%s"], {
    encoding: "utf8",
    env: gitEnv()
  })
  assert.equal(remoteLog.stdout.trim(), "local commit")
  cleanup([pair.local, pair.bare, pair.other])
})

test("overlapping uncommitted changes skip the fast-forward", () => {
  const pair = setupRemotePair()
  fs.writeFileSync(path.join(pair.local, "todos.md"), "- dirty local\n")
  fs.writeFileSync(path.join(pair.other, "todos.md"), "- from remote\n")
  sh(pair.other, ["add", "todos.md"])
  sh(pair.other, ["commit", "-m", "remote update"])
  sh(pair.other, ["push", "origin", "master"])
  const result = runPull(pair.local)
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /SKIPPED:blocked/)
  const text = fs.readFileSync(path.join(pair.local, "todos.md"), "utf8")
  assert.equal(text, "- dirty local\n")
  cleanup([pair.local, pair.bare, pair.other])
})
