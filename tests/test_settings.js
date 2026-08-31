"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Settings = require("../Settings.js")

test("defaults are write-only: no commit, push, or changelog", () => {
  const d = Settings.defaultSettings()
  assert.equal(d.gitCommit, false)
  assert.equal(d.gitPush, false)
  assert.equal(d.updateChangelog, false)
  assert.deepEqual(Settings.parseSettings(""), d)
  assert.deepEqual(Settings.parseSettings("not-json"), d)
  assert.deepEqual(Settings.parseSettings("[]"), d)
})

test("parseSettings only treats JSON true as enabled", () => {
  const on = Settings.parseSettings(JSON.stringify({
    gitCommit: true,
    gitPush: true,
    updateChangelog: true
  }))
  assert.equal(on.gitCommit, true)
  assert.equal(on.gitPush, true)
  assert.equal(on.updateChangelog, true)
  const strings = Settings.parseSettings(JSON.stringify({
    gitCommit: "true",
    gitPush: "yes",
    updateChangelog: 1
  }))
  assert.equal(strings.gitCommit, false)
  assert.equal(strings.gitPush, false)
  assert.equal(strings.updateChangelog, false)
})

test("serializeSettings round-trips booleans only", () => {
  const raw = Settings.serializeSettings({ gitCommit: true, gitPush: false, updateChangelog: true })
  const parsed = JSON.parse(raw)
  assert.deepEqual(parsed, { gitCommit: true, gitPush: false, updateChangelog: true })
  assert.ok(raw.endsWith("\n"))
})
