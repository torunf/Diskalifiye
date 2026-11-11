import Foundation
import SwiftUI

enum FileKind: UInt8, CaseIterable, Identifiable {
    case video, image, audio, archive, document, code, binary, other, folder, small

    var id: UInt8 { rawValue }

    /// Yalnızca gerçek dosya türleri (klasör ve sentetik türler hariç).
    static let fileKinds: [FileKind] = [.video, .image, .audio, .archive, .document, .code, .binary, .other]

    var title: String {
        switch self {
        case .video: return "Video"
        case .image: return "Görsel"
        case .audio: return "Ses"
        case .archive: return "Arşiv & Disk İmajı"
        case .document: return "Belge"
        case .code: return "Kod & Veri"
        case .binary: return "Uygulama & İkili"
        case .other: return "Diğer"
        case .folder: return "Klasör"
        case .small: return "Küçük öğeler"
        }
    }

    var icon: String {
        switch self {
        case .video: return "film"
        case .image: return "photo"
        case .audio: return "music.note"
        case .archive: return "archivebox"
        case .document: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .binary: return "app.dashed"
        case .other: return "doc"
        case .folder: return "folder.fill"
        case .small: return "square.grid.3x3.fill"
        }
    }

    var color: Color {
        switch self {
        case .video: return Color(hue: 0.78, saturation: 0.55, brightness: 0.90)
        case .image: return Color(hue: 0.08, saturation: 0.65, brightness: 0.95)
        case .audio: return Color(hue: 0.93, saturation: 0.55, brightness: 0.92)
        case .archive: return Color(hue: 0.14, saturation: 0.70, brightness: 0.90)
        case .document: return Color(hue: 0.58, saturation: 0.60, brightness: 0.92)
        case .code: return Color(hue: 0.40, saturation: 0.55, brightness: 0.78)
        case .binary: return Color(hue: 0.50, saturation: 0.55, brightness: 0.82)
        case .other, .small: return Color(white: 0.55)
        case .folder: return Color(hue: 0.58, saturation: 0.50, brightness: 0.90)
        }
    }

    private static let map: [String: FileKind] = {
        var m: [String: FileKind] = [:]
        func add(_ k: FileKind, _ exts: String) { for e in exts.split(separator: " ") { m[String(e)] = k } }
        add(.video, "mp4 mov mkv avi m4v webm wmv flv mpg mpeg 3gp ts mts braw prores")
        add(.image, "jpg jpeg png gif heic heif tiff tif bmp raw cr2 cr3 nef arw dng psd psb ai svg webp ico icns sketch fig xcf")
        add(.audio, "mp3 m4a wav aiff aif flac aac ogg opus wma caf mid midi band logicx")
        add(.archive, "zip dmg pkg iso tar gz tgz bz2 xz 7z rar zst lz4 xip ipa apk aab jar war img sparseimage sparsebundle cpio")
        add(.document, "pdf doc docx xls xlsx ppt pptx pages numbers key txt rtf md epub mobi csv odt ods odp tex")
        add(.code, "swift js jsx ts tsx py rb go rs c h cpp hpp cc m mm java kt kts dart php html css scss json xml yaml yml toml sql sh lock map plist db sqlite sqlite3 realm log ipynb pack idx bin dat cache wal")
        add(.binary, "dylib so a o exe dll framework app node wasm car nib tbd swiftmodule pcm dsym bundle kext")
        m["ts"] = .code
        return m
    }()

    static func of(_ name: String) -> FileKind {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return .other }
        let ext = name[name.index(after: dot)...]
        if ext.count > 12 || ext.isEmpty { return .other }
        return map[ext.lowercased()] ?? .other
    }
}

/// Tarama ağacındaki bir düğüm. Ağaç tarama sırasında arka planda kurulur, sonra yalnızca ana iş parçacığında değiştirilir.
final class FileNode: Identifiable, Hashable, @unchecked Sendable {
    let name: String
    let isDir: Bool
    let kind: FileKind
    let isSynthetic: Bool
    weak var parent: FileNode?
    var size: Int64
    var fileCount: Int = 0
    var children: [FileNode] = []
    var smallSize: Int64 = 0
    var smallCount: Int = 0
    var pending = false

    init(name: String, isDir: Bool, kind: FileKind, size: Int64 = 0, synthetic: Bool = false) {
        self.name = name
        self.isDir = isDir
        self.kind = kind
        self.size = size
        self.isSynthetic = synthetic
    }

    var id: ObjectIdentifier { ObjectIdentifier(self) }
    static func == (a: FileNode, b: FileNode) -> Bool { a === b }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    var path: String {
        guard let p = parent else { return name }
        if isSynthetic { return p.path }
        let pp = p.path
        return pp.hasSuffix("/") ? pp + name : pp + "/" + name
    }

    var displayName: String {
        if parent == nil {
            if name == "/" { return DiskInfo.current().name }
            return (name as NSString).lastPathComponent
        }
        return name
    }

    /// Küçük öğeleri tek bir sentetik düğümde toplar, çocukları sıralar, boyutu hesaplar.
    func finalize() {
        if smallCount > 0 || smallSize > 0 {
            let s = FileNode(name: "Küçük öğeler (\(smallCount.formatted()))", isDir: false, kind: .small, size: smallSize, synthetic: true)
            s.fileCount = smallCount
            s.parent = self
            children.append(s)
            smallSize = 0
            smallCount = 0
        }
        children.sort { $0.size > $1.size }
        var total: Int64 = 0
        var count = 0
        for c in children { total += c.size; count += c.fileCount }
        size = total
        fileCount = count
    }

    func isDescendant(of other: FileNode) -> Bool {
        var n: FileNode? = self
        while let x = n {
            if x === other { return true }
            n = x.parent
        }
        return false
    }
}

struct DiskInfo {
    var name = "Macintosh HD"
    var total: Int64 = 0
    var available: Int64 = 0
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskInfo {
        var d = DiskInfo()
        let url = URL(fileURLWithPath: "/")
        if let v = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            d.name = v.volumeName ?? d.name
            d.total = Int64(v.volumeTotalCapacity ?? 0)
            d.available = v.volumeAvailableCapacityForImportantUsage ?? 0
        }
        return d
    }
}

func fmt(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

let homePath = NSHomeDirectory()

func tildePath(_ path: String) -> String {
    if path == homePath { return "~" }
    if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
    return path
}

func revealInFinder(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}

enum Palette {
    static let hues: [Double] = [0.58, 0.08, 0.38, 0.78, 0.97, 0.14, 0.48, 0.68, 0.88, 0.28]
    static func hue(_ i: Int) -> Double { hues[i % hues.count] }
    static func color(_ i: Int) -> Color { Color(hue: hue(i), saturation: 0.62, brightness: 0.90) }
}
