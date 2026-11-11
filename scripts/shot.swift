import AppKit
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Diskalifiye" && (w[kCGWindowLayer as String] as? Int) == 0 {
    print(w[kCGWindowNumber as String] as! Int); break
}
