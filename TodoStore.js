.pragma library

var openCount = 0
var countListeners = []
var refreshListeners = []

function setOpenCount(n) {
  var next = Number(n)
  if (!isFinite(next) || next < 0) next = 0
  openCount = next
  for (var i = 0; i < countListeners.length; i++) countListeners[i](openCount)
}

function subscribeCount(fn) {
  countListeners.push(fn)
  fn(openCount)
}

function requestRefresh() {
  for (var i = 0; i < refreshListeners.length; i++) refreshListeners[i]()
}

function subscribeRefresh(fn) {
  refreshListeners.push(fn)
}
