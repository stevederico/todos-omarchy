"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Settings = require("../Settings.js")

test("defaults are write-only: no commit or push", () => {
  const d = Settings.defaultSettings()
  assert.equal(d.gitCommit, false)
  assert.equal(d.gitPush, false)
  assert.deepEqual(Settings.parseSettings(""), d)
  assert.deepEqual(Settings.parseSettings("not-json"), d)
  assert.deepEqual(Settings.parseSettings("[]"), d)
})

test("parseSettings only treats JSON true as enabled", () => {
  const on = Settings.parseSettings(JSON.stringify({
    gitCommit: true,
    gitPush: true
  }))
  assert.equal(on.gitCommit, true)
  assert.equal(on.gitPush, true)
  const strings = Settings.parseSettings(JSON.stringify({
    gitCommit: "true",
    gitPush: "yes"
  }))
  assert.equal(strings.gitCommit, false)
  assert.equal(strings.gitPush, false)
})

test("serializeSettings drops leftover changelog flag", () => {
  const raw = Settings.serializeSettings({ gitCommit: true, gitPush: false, updateChangelog: true })
  const parsed = JSON.parse(raw)
  assert.deepEqual(parsed, { gitCommit: true, gitPush: false })
  assert.ok(raw.endsWith("\n"))
})
