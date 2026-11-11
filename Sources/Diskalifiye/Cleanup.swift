import Foundation

enum Risk {
    case safe, caution
    var title: String { self == .safe ? "Güvenli" : "Dikkat" }
}

struct CleanupItem: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let size: Int64
    var note: String? = nil
}

struct CleanupCategory: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let risk: Risk
    var items: [CleanupItem]
    var total: Int64 { items.reduce(0) { $0 + $1.size } }
}

enum CleanupEngine {
    private static let minItem: Int64 = 512 * 1024

    static func analyze(root: FileNode?) -> [CleanupCategory] {
        let h = homePath
        var cats: [CleanupCategory] = []

        cats.append(CleanupCategory(
            id: "caches", title: "Uygulama Önbellekleri",
            detail: "Uygulamaların geçici verileri. Silinirse uygulamalar gerektiğinde yeniden oluşturur.",
            icon: "internaldrive", risk: .safe,
            items: childItems(of: h + "/Library/Caches")))

        cats.append(CleanupCategory(
            id: "logs", title: "Günlük Dosyaları",
            detail: "Uygulama ve sistem günlükleri, çökme raporları.",
            icon: "doc.text.magnifyingglass", risk: .safe,
            items: childItems(of: h + "/Library/Logs")))

        cats.append(CleanupCategory(
            id: "xcode", title: "Xcode Derleme Verileri",
            detail: "DerivedData, cihaz destek dosyaları ve simülatör önbellekleri. Bir sonraki derlemede yeniden üretilir.",
            icon: "hammer", risk: .safe,
            items: childItems(of: h + "/Library/Developer/Xcode/DerivedData", prefix: "DerivedData / ")
                + childItems(of: h + "/Library/Developer/Xcode/iOS DeviceSupport", prefix: "iOS DeviceSupport / ")
                + childItems(of: h + "/Library/Developer/Xcode/watchOS DeviceSupport", prefix: "watchOS DeviceSupport / ")
                + singleItems([(h + "/Library/Developer/CoreSimulator/Caches", "Simülatör önbellekleri")])))

        cats.append(CleanupCategory(
            id: "pkg", title: "Paket Yöneticisi Önbellekleri",
            detail: "npm, Gradle, Maven, Cargo, CocoaPods, pub vb. indirme önbellekleri. Gerektiğinde tekrar indirilir.",
            icon: "shippingbox", risk: .safe,
            items: singleItems([
                (h + "/.npm/_cacache", "npm önbelleği"),
                (h + "/.yarn/cache", "Yarn önbelleği"),
                (h + "/.bun/install/cache", "Bun önbelleği"),
                (h + "/Library/pnpm/store", "pnpm deposu"),
                (h + "/.gradle/caches", "Gradle önbelleği"),
                (h + "/.m2/repository", "Maven deposu"),
                (h + "/.cargo/registry", "Cargo kayıt önbelleği"),
                (h + "/.pub-cache", "Dart/Flutter pub önbelleği"),
                (h + "/.cocoapods/repos", "CocoaPods spec depoları"),
                (h + "/.cache", "~/.cache (çeşitli araçlar)"),
            ])))

        if let root {
            cats.append(CleanupCategory(
                id: "projects", title: "Proje Artıkları",
                detail: "node_modules, Pods, build, target, .venv gibi yeniden üretilebilen bağımlılık ve derleme klasörleri.",
                icon: "folder.badge.gearshape", risk: .caution,
                items: projectLeftovers(root)))
        }

        cats.append(CleanupCategory(
            id: "xcode-heavy", title: "Xcode Arşivleri & Simülatörler",
            detail: "Eski uygulama arşivleri ve simülatör cihaz verileri. Arşivler eski sürümlerin çökme kayıtlarını çözmek için gerekebilir.",
            icon: "iphone", risk: .caution,
            items: childItems(of: h + "/Library/Developer/Xcode/Archives", prefix: "Arşiv / ")
                + singleItems([(h + "/Library/Developer/CoreSimulator/Devices", "Simülatör cihazları")])))

        cats.append(CleanupCategory(
            id: "backups", title: "iPhone / iPad Yedekleri",
            detail: "Bu Mac'e alınmış cihaz yedekleri. Silmeden önce artık gerekmediğinden emin ol.",
            icon: "arrow.triangle.2.circlepath", risk: .caution,
            items: childItems(of: h + "/Library/Application Support/MobileSync/Backup")))

        cats.append(CleanupCategory(
            id: "downloads", title: "Eski İndirilenler",
            detail: "İndirilenler klasöründe 90 günden uzun süredir duran öğeler.",
            icon: "arrow.down.circle", risk: .caution,
            items: oldDownloads()))

        return cats.filter { !$0.items.isEmpty }
    }

    static func trashSize() -> Int64? {
        let p = homePath + "/.Trash"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: p) else { return nil }
        return sizes(names.map { p + "/" + $0 }).reduce(0, +)
    }

    private static func sizes(_ paths: [String]) -> [Int64] {
        var out = [Int64](repeating: 0, count: paths.count)
        out.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: paths.count) { i in
                base[i] = Scanner.du(paths[i])
            }
        }
        return out
    }

    private static func childItems(of dir: String, prefix: String = "") -> [CleanupItem] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        let paths = names.filter { $0 != ".DS_Store" }.map { dir + "/" + $0 }
        let s = sizes(paths)
        return zip(paths, s)
            .filter { $0.1 >= minItem }
            .map { CleanupItem(path: $0.0, name: prefix + ($0.0 as NSString).lastPathComponent, size: $0.1) }
            .sorted { $0.size > $1.size }
    }

    private static func singleItems(_ list: [(String, String)]) -> [CleanupItem] {
        let existing = list.filter { FileManager.default.fileExists(atPath: $0.0) }
        let s = sizes(existing.map { $0.0 })
        return zip(existing, s)
            .filter { $0.1 >= minItem }
            .map { CleanupItem(path: $0.0.0, name: $0.0.1, size: $0.1) }
            .sorted { $0.size > $1.size }
    }

    private static func oldDownloads() -> [CleanupItem] {
        let dir = URL(fileURLWithPath: homePath + "/Downloads")
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let limit = Date().addingTimeInterval(-90 * 86400)
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "tr_TR")
        var old: [(String, Date)] = []
        for u in urls {
            let v = try? u.resourceValues(forKeys: Set(keys))
            guard let d = v?.addedToDirectoryDate ?? v?.contentModificationDate, d < limit else { continue }
            old.append((u.path, d))
        }
        let s = sizes(old.map { $0.0 })
        return zip(old, s)
            .filter { $0.1 >= minItem }
            .map { CleanupItem(path: $0.0.0, name: ($0.0.0 as NSString).lastPathComponent, size: $0.1,
                               note: rel.localizedString(for: $0.0.1, relativeTo: Date())) }
            .sorted { $0.size > $1.size }
    }

    private static func projectLeftovers(_ root: FileNode) -> [CleanupItem] {
        let fm = FileManager.default
        var out: [CleanupItem] = []
        func has(_ dir: String, _ names: [String]) -> Bool { names.contains { fm.fileExists(atPath: dir + "/" + $0) } }

        func isLeftover(_ n: FileNode, parentPath: String) -> Bool {
            switch n.name {
            case "node_modules": return has(parentPath, ["package.json"])
            case "Pods": return has(parentPath, ["Podfile"])
            case ".next", ".nuxt", ".turbo", ".parcel-cache": return has(parentPath, ["package.json"])
            case "target": return has(parentPath, ["Cargo.toml", "pom.xml"])
            case ".dart_tool": return has(parentPath, ["pubspec.yaml"])
            case "build": return has(parentPath, ["pubspec.yaml", "build.gradle", "build.gradle.kts"])
            case ".gradle": return has(parentPath, ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"])
            case ".build": return has(parentPath, ["Package.swift"])
            case "DerivedData": return true
            case ".venv", "venv": return has(parentPath + "/" + n.name, ["pyvenv.cfg"])
            default: return false
            }
        }

        func walk(_ node: FileNode, _ path: String, _ depth: Int) {
            for c in node.children where c.isDir {
                if isLeftover(c, parentPath: path) {
                    let p = path.hasSuffix("/") ? path + c.name : path + "/" + c.name
                    out.append(CleanupItem(path: p, name: tildePath(p), size: c.size))
                    continue
                }
                if c.name.hasPrefix(".") || c.name == "Library" || c.name == "Applications" || c.name.hasSuffix(".app") { continue }
                if depth < 12 {
                    walk(c, path.hasSuffix("/") ? path + c.name : path + "/" + c.name, depth + 1)
                }
            }
        }
        walk(root, root.path, 0)
        return out.filter { $0.size >= minItem }.sorted { $0.size > $1.size }
    }
}
