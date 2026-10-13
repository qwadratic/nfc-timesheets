// Runnable check: a query string is never percent-encoded into the path (TASK-365.17).
//
//   cd NFCTimeSheets && cat NFCTimeSheets/Branding.swift NFCTimeSheets/TagLink.swift \
//     NFCTimeSheets/API.swift NFCTimeSheets/AppLanguage.swift checks/request-url-check.swift \
//     > /tmp/request-url-check.swift && swift /tmp/request-url-check.swift
//
// WHY: "who worked at this door" built "/operator/zones/<id>/shifts?page=N" as a PATH, and
// Foundation encodes the "?" as %3F, so the server (which matches on pathname segments) answered
// 404 on iOS while Android's string concatenation worked. The screen had only ever been walked
// with mocks. This pins the URL the real request goes to, and - as text - that no request layer
// goes back to `API.base.appending(path:)` with a caller-supplied path.
//
// RED CASE reproduced before this was trusted: making RequestURL.make (in API.swift) return
// base.appending(path: path) unchanged fails "query is a query, not path" below.

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}

let base = URL(string: "https://api.example.test")!
let zone = "6f1c2a7e-0b1d-4e55-9a39-2d6f5f3b8c10"

// 1. Explicit query (what OperatorAPI.zoneShifts now passes)
let a = RequestURL.make(base: base, path: "/operator/zones/\(zone)/shifts", query: [("page", "2")])
check(a.path == "/operator/zones/\(zone)/shifts", "path is the bare path (\(a.path))")
check(a.query == "page=2", "query is a query, not path (\(a.query ?? "nil"))")
check(!a.absoluteString.contains("%3F"), "no %3F anywhere in \(a.absoluteString)")
check(a.absoluteString == "https://api.example.test/operator/zones/\(zone)/shifts?page=2",
      "exact URL (\(a.absoluteString))")

// 2. A caller that still writes the query inline cannot reproduce the bug
let b = RequestURL.make(base: base, path: "/operator/zones/\(zone)/shifts?page=3")
check(b.path.hasSuffix("/shifts"), "inline query is split off the path (\(b.path))")
check(b.query == "page=3", "inline query survives as a query (\(b.query ?? "nil"))")
check(!b.absoluteString.contains("%3F"), "inline form has no %3F either")

// 3. Both at once, order stable: explicit first, inline after
let c = RequestURL.make(base: base, path: "/x?b=2", query: [("a", "1")])
check(c.query == "a=1&b=2", "explicit then inline (\(c.query ?? "nil"))")

// 4. Values are encoded by URLComponents, once
let d = RequestURL.make(base: base, path: "/x", query: [("q", "a b&c")])
check(d.query == "q=a%20b%26c" || d.query == "q=a b&c" || d.absoluteString.contains("q=a%20b%26c"),
      "a value with space and ampersand stays ONE parameter (\(d.absoluteString))")
check(URLComponents(url: d, resolvingAgainstBaseURL: false)?.queryItems?.count == 1,
      "exactly one query item")

// 5. No query, no "?"
let e = RequestURL.make(base: base, path: "/operator/zones")
check(e.absoluteString == "https://api.example.test/operator/zones", "plain path untouched (\(e.absoluteString))")

// 6. THE REQUEST LAYERS, read as text
for file in ["NFCTimeSheets/OperatorAPI.swift", "NFCTimeSheets/API.swift"] {
    let src = try! String(contentsOfFile: file, encoding: .utf8)
    let live = src.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
    check(!live.contains("API.base.appending(path: path)"),
          "\(file) builds request URLs through RequestURL, not API.base.appending(path: <caller path>)")
    check(live.contains("RequestURL.make("), "\(file) uses RequestURL.make")
}
// Comments may still DOCUMENT the endpoint as "shifts?page=N"; only live code is held to it.
let op = try! String(contentsOfFile: "NFCTimeSheets/OperatorAPI.swift", encoding: .utf8)
    .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
check(!op.contains("shifts?page="), "OperatorAPI no longer concatenates ?page= into a path")

if failed { exit(1) }
print("request-url-check: OK")
