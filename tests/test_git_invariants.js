import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { spawn, spawnSync } from "node:child_process"

const pullScript = path.join(import.meta.dirname, "..", "scripts", "git-pull.sh")
const syncScript = path.join(import.meta.dirname, "..", "scripts", "git-sync.sh")

const env = {
  ...process.env,
  GIT_AUTHOR_NAME: "Test",
  GIT_AUTHOR_EMAIL: "test@example.test",
  GIT_COMMITTER_NAME: "Test",
  GIT_COMMITTER_EMAIL: "test@example.test",
  GIT_TERMINAL_PROMPT: "0",
  TODO_OMARCHY_LOCK_WAIT: "1"
}

function git(cwd, args) {
  const r = spawnSync("git", args, { cwd, encoding: "utf8", env })
  assert.equal(r.status, 0, `git ${args.join(" ")}: ${r.stderr}`)
  return r.stdout.trim()
}

function plumbingCommit(dir, file, text, message) {
  fs.writeFileSync(path.join(dir, file), text)
  git(dir, ["add", file])
  const tree = git(dir, ["write-tree"])
  const parent = spawnSync("git", ["rev-parse", "--verify", "-q", "HEAD"], { cwd: dir, encoding: "utf8", env }).stdout.trim()
  const sha = git(dir, ["commit-tree", tree, "-m", message, ...(parent ? ["-p", parent] : [])])
  git(dir, ["update-ref", "HEAD", sha])
  return sha
}

function remotePair() {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), "agentcloud-todos-inv-"))
  const bare = path.join(base, "bare.git")
  const local = path.join(base, "local")
  const other = path.join(base, "other")
  git(base, ["init", "-q", "--bare", "-b", "master", bare])
  fs.mkdirSync(local)
  git(local, ["init", "-q", "-b", "master"])
  plumbingCommit(local, "todos.md", "- one\n- two\n", "init")
  git(local, ["remote", "add", "origin", bare])
  git(local, ["push", "-q", "-u", "origin", "master"])
  git(base, ["clone", "-q", bare, other])
  return { base, local, other }
}

function run(script, args, cwd) {
  return spawnSync("bash", [script, ...args], { cwd, encoding: "utf8", env, stdio: ["ignore", "pipe", "pipe"] })
}

test("git-pull.sh rebases a diverge only on a clean tree, even with rebase.autoStash on", () => {
  const p = remotePair()
  plumbingCommit(p.other, "other.md", "theirs\n", "theirs")
  git(p.other, ["push", "-q", "origin", "master"])
  const mine = plumbingCommit(p.local, "local.md", "mine\n", "mine")
  git(p.local, ["config", "rebase.autoStash", "true"])
  fs.writeFileSync(path.join(p.local, "todos.md"), "- one\n- two\n- unsaved\n")

  const dirty = run(pullScript, ["--dir", p.local], p.local)
  assert.equal(dirty.status, 0)
  assert.equal(dirty.stdout, "DIVERGED\n")
  assert.equal(git(p.local, ["rev-parse", "HEAD"]), mine)
  assert.equal(fs.readFileSync(path.join(p.local, "todos.md"), "utf8"), "- one\n- two\n- unsaved\n")

  git(p.local, ["checkout", "--", "todos.md"])
  const clean = run(pullScript, ["--dir", p.local], p.local)
  assert.equal(clean.status, 0)
  assert.equal(clean.stdout, "REBASED\n")
  assert.equal(fs.readFileSync(path.join(p.local, "other.md"), "utf8"), "theirs\n")
  assert.equal(fs.readFileSync(path.join(p.local, "local.md"), "utf8"), "mine\n")
  fs.rmSync(p.base, { recursive: true, force: true })
})

test("git-pull.sh aborts a conflicting rebase and keeps the local commit and file", () => {
  const p = remotePair()
  plumbingCommit(p.other, "todos.md", "- one\n- theirs\n", "theirs")
  git(p.other, ["push", "-q", "origin", "master"])
  const mine = plumbingCommit(p.local, "todos.md", "- one\n- mine\n", "mine")

  const result = run(pullScript, ["--dir", p.local, "--push"], p.local)
  assert.equal(result.status, 0)
  assert.equal(result.stdout, "DIVERGED\n")
  assert.equal(result.stderr, "")
  assert.equal(git(p.local, ["rev-parse", "HEAD"]), mine)
  assert.equal(git(p.local, ["symbolic-ref", "HEAD"]), "refs/heads/master")
  assert.equal(fs.existsSync(path.join(p.local, ".git", "rebase-merge")), false)
  assert.equal(fs.existsSync(path.join(p.local, ".git", "rebase-apply")), false)
  assert.equal(fs.readFileSync(path.join(p.local, "todos.md"), "utf8"), "- one\n- mine\n")
  assert.equal(git(p.local, ["status", "--porcelain"]), "")
  fs.rmSync(p.base, { recursive: true, force: true })
})

test("git-pull.sh and git-sync.sh wait on the same .git/agentcloud-todos-sync.lock", async () => {
  const p = remotePair()
  const lock = path.join(p.local, ".git", "agentcloud-todos-sync.lock")
  const msg = path.join(p.base, "msg")
  fs.writeFileSync(msg, "Add three")
  fs.writeFileSync(path.join(p.local, "todos.md"), "- one\n- two\n- three\n")
  const held = spawn("bash", ["-c", 'exec 9>"$1"; flock 9; echo held; sleep 20', "lock", lock], { stdio: ["ignore", "pipe", "ignore"] })
  await new Promise((resolve) => held.stdout.once("data", resolve))
  const pull = run(pullScript, ["--dir", p.local, "--push"], p.local)
  const sync = run(syncScript, ["--dir", p.local, "--message-file", msg, "--push", "--", path.join(p.local, "todos.md")], p.local)
  held.kill("SIGTERM")
  assert.equal(pull.stdout, "BUSY\n")
  assert.equal(sync.stdout, "BUSY\n")
  assert.equal(pull.status, 0)
  assert.equal(sync.status, 0)
  fs.rmSync(p.base, { recursive: true, force: true })
})

test("git-sync.sh never runs shell code from the commit message or a file path", () => {
  const p = remotePair()
  const name = "$(touch pwned-path)`touch pwned-tick`.md"
  fs.writeFileSync(path.join(p.local, name), "- x\n")
  const msg = path.join(p.base, "msg")
  fs.writeFileSync(msg, "Add $(touch pwned-msg) \"; touch pwned-quote; \" `touch pwned-msg-tick`")
  const result = run(syncScript, ["--dir", p.local, "--message-file", msg, "--", path.join(p.local, name)], p.local)
  const planted = fs.readdirSync(p.local).filter((f) => f.startsWith("pwned"))
  const staged = git(p.local, ["diff", "--cached", "--name-only", "-z"]).split("\0").filter(Boolean)
  const committed = git(p.local, ["log", "-1", "--name-only", "-z", "--format="]).split("\0").filter(Boolean)
  fs.rmSync(p.base, { recursive: true, force: true })
  assert.equal(result.status, 0)
  assert.deepEqual(planted, [])
  assert.deepEqual([...staged, ...committed].filter((f) => f === name), [name])
})
