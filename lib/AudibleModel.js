.pragma library

// AudibleModel.js holds the Audiobooks source's pure helpers (the library's
// sort orders), free of Qt objects so node can test them
// (tests/model.test.cjs) and the panel scene's fake source can use the real
// thing.

// "recent" is the bridge's own order: the books listened to most recently
// first, then the rest by purchase date.
var SORT_ORDERS = [
  { key: "recent", label: "Recent" }, { key: "title", label: "Title" }, { key: "author", label: "Author" }
]

function sortLabel(key) {
  for (var i = 0; i < SORT_ORDERS.length; i++) if (SORT_ORDERS[i].key === key) return SORT_ORDERS[i].label
  return SORT_ORDERS[0].label
}

function nextSort(key) {
  var i = 0
  for (var k = 0; k < SORT_ORDERS.length; k++) if (SORT_ORDERS[k].key === key) i = k
  return SORT_ORDERS[(i + 1) % SORT_ORDERS.length].key
}

// Natural order ("Book 2" before "Book 10"), case aside, blanks last. Not
// localeCompare's `numeric` option: the QML engine ignores it.
function compareText(a, b) {
  var x = String(a || "").trim().toLowerCase()
  var y = String(b || "").trim().toLowerCase()
  if (x === "" || y === "") return (x === "" ? 1 : 0) - (y === "" ? 1 : 0)
  var xs = x.split(/(\d+)/)
  var ys = y.split(/(\d+)/)
  for (var i = 0; i < Math.min(xs.length, ys.length); i++) {
    var p = xs[i], q = ys[i]
    if (p === q) continue
    // split() puts the digit runs at the odd places.
    if (i % 2 === 1) {
      var d = Number(p) - Number(q)
      if (d !== 0) return d < 0 ? -1 : 1
      continue  // "02" and "2"
    }
    var c = p.localeCompare(q)
    if (c !== 0) return c < 0 ? -1 : 1
  }
  return xs.length - ys.length
}

function firstAuthor(book) {
  var a = book ? book.authors : null
  if (!a) return ""
  return typeof a === "string" ? a : (a[0] || "")
}

// A copy of `books` in `order`; ties keep the bridge's order, so a series
// stays in the order it was read.
function sortBooks(books, order) {
  var items = (books || []).slice()
  if (order !== "title" && order !== "author") return items
  var ranked = items.map(function (b, i) { return { b: b || {}, i: i } })
  ranked.sort(function (x, y) {
    var c = order === "author" ? compareText(firstAuthor(x.b), firstAuthor(y.b)) : 0
    return c || compareText(x.b.title, y.b.title) || x.i - y.i
  })
  return ranked.map(function (r) { return items[r.i] })
}
