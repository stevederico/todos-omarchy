"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Settings = require("../Settings.js")

test("settings stay empty: git and changelog are always on", () => {
  assert.deepEqual(Settings.defaultSettings(), {})
  assert.deepEqual(Settings.parseSettings(""), {})
  assert.deepEqual(Settings.parseSettings("not-json"), {})
  assert.deepEqual(Settings.parseSettings(JSON.stringify({ gitCommit: true })), {})
})

test("serializeSettings writes an empty object", () => {
  const raw = Settings.serializeSettings({ gitCommit: true, gitPush: false })
  assert.equal(raw, "{}\n")
})
