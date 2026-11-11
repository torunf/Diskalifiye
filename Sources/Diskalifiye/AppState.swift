import SwiftUI
import AppKit

struct PendingTrash: Identifiable {
    let id = UUID()
    let paths: [String]
    let size: Int64
}

@MainActor
final class AppState: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case overview, cleanup, large, duplicates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: return "Disk Haritası"
            case .cleanup: return "Temizlik Önerileri"
            case .large: return "Büyük Dosyalar"
            case .duplicates: return "Kopya Dosyalar"
            }
        }
        var icon: String {
            switch self {
            case .overview: return "square.grid.3x3.topleft.filled"
            case .cleanup: return "sparkles"
            case .large: return "doc.badge.arrow.up"
            case .duplicates: return "doc.on.doc"
            }
        }
    }

    enum DupState: Equatable { case idle, running(Double), done }

    @Published var section: Section? = .overview
    @Published var root: FileNode?
    @Published var current: FileNode?
    @Published var revision = 0
    @Published var scanning = false
    @Published var scanPath: String?
    @Published var progress = ProgressSnapshot()
    @Published var kindTotals = [Int64](repeating: 0, count: FileKind.allCases.count)
    @Published var denied = 0
    @Published var scanDuration: TimeInterval = 0
    @Published var largeFiles: [FileNode] = []
    @Published var disk = DiskInfo.current()

    @Published var cleanup: [CleanupCategory] = []
    @Published var cleanupAnalyzing = false
    @Published var cleanupAnalyzed = false
    @Published var cleanupSelection: Set<String> = []
    @Published var trashSize: Int64?
    @Published var emptyingTrash = false

    @Published var duplicates: [DuplicateGroup] = []
    @Published var dupState: DupState = .idle

    @Published var pendingTrash: PendingTrash?
    @Published var confirmEmptyTrash = false
    @Published var errorMessage: String?

    private var cleanupRerun = false
    private var scanProgress: ScanProgress?
    private var dupCancel: CancelFlag?

    init() {
        // Geliştirme için: --autoscan <yol> [--section cleanup|large|duplicates]
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--autoscan"), i + 1 < args.count {
            let path = args[i + 1]
            let sec = args.firstIndex(of: "--section").flatMap { $0 + 1 < args.count ? Section(rawValue: args[$0 + 1]) : nil }
            DispatchQueue.main.async {
                self.startScan(path)
                if let sec { self.section = sec }
            }
        }
    }

    var cleanupTotal: Int64 { cleanup.reduce(0) { $0 + $1.total } }

    // MARK: - Tarama

    func startScan(_ path: String) {
        guard !scanning else { return }
        scanning = true
        scanPath = path
        root = nil
        current = nil
        largeFiles = []
        duplicates = []
        dupState = .idle
        dupCancel?.value = true
        progress = ProgressSnapshot()
        section = .overview
        let sp = ScanProgress()
        scanProgress = sp
        let started = Date()

        Task {
            while self.scanning && self.scanProgress === sp {
                self.progress = sp.snapshot()
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        Task.detached(priority: .userInitiated) {
            let node = Scanner.scan(rootPath: path, progress: sp)
            let large = node.map { Array(Scanner.collectFiles($0, minSize: 1 << 20).prefix(1000)) } ?? []
            await MainActor.run {
                guard self.scanProgress === sp else { return }
                let snap = sp.snapshot()
                self.scanning = false
                self.scanProgress = nil
                self.progress = snap
                self.kindTotals = snap.kinds
                self.denied = snap.denied
                self.scanDuration = Date().timeIntervalSince(started)
                self.root = node
                self.current = node
                self.largeFiles = large
                self.revision += 1
                self.disk = DiskInfo.current()
                if node != nil { self.analyzeCleanup() }
            }
        }
    }

    func cancelScan() {
        scanProgress?.cancelled = true
    }

    func pickFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Tara"
        panel.message = "Taranacak klasörü seç"
        if panel.runModal() == .OK, let url = panel.url {
            startScan(url.path)
        }
    }

    func rescan() {
        if let p = scanPath { startScan(p) }
    }

    // MARK: - Temizlik

    func analyzeCleanup() {
        guard !cleanupAnalyzing else { cleanupRerun = true; return }
        cleanupAnalyzing = true
        cleanupRerun = false
        let root = self.root
        Task.detached(priority: .userInitiated) {
            let cats = CleanupEngine.analyze(root: root)
            let trash = CleanupEngine.trashSize()
            await MainActor.run {
                self.cleanup = cats
                self.trashSize = trash
                let valid = Set(cats.flatMap { $0.items.map(\.path) })
                self.cleanupSelection.formIntersection(valid)
                self.cleanupAnalyzing = false
                self.cleanupAnalyzed = true
                if self.cleanupRerun { self.analyzeCleanup() }
            }
        }
    }

    func refreshTrashSize() {
        Task.detached {
            let t = CleanupEngine.trashSize()
            await MainActor.run { self.trashSize = t; self.disk = DiskInfo.current() }
        }
    }

    func emptyTrash() {
        guard !emptyingTrash else { return }
        emptyingTrash = true
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "tell application \"Finder\" to empty trash"]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = Pipe()
            var message: String?
            do {
                try p.run()
                p.waitUntilExit()
                if p.terminationStatus != 0 {
                    let out = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    // -1728: çöp zaten boş
                    if !out.contains("-1728") { message = "Çöp Kutusu boşaltılamadı.\n\(out)" }
                }
            } catch {
                message = "Çöp Kutusu boşaltılamadı: \(error.localizedDescription)"
            }
            let m = message
            await MainActor.run {
                self.emptyingTrash = false
                if let m { self.errorMessage = m }
                self.refreshTrashSize()
            }
        }
    }

    // MARK: - Silme (Çöp Kutusuna taşıma)

    func requestTrash(nodes: [FileNode]) {
        let ns = nodes.filter { !$0.isSynthetic && $0.parent != nil }
        guard !ns.isEmpty else { return }
        pendingTrash = PendingTrash(paths: ns.map(\.path), size: ns.reduce(0) { $0 + $1.size })
    }

    func requestTrash(items: [CleanupItem]) {
        guard !items.isEmpty else { return }
        pendingTrash = PendingTrash(paths: items.map(\.path), size: items.reduce(0) { $0 + $1.size })
    }

    func performTrash(_ req: PendingTrash) {
        var failed: [String] = []
        var removed: [String] = []
        for p in req.paths {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil)
                removed.append(p)
            } catch {
                failed.append("\(tildePath(p)): \(error.localizedDescription)")
            }
        }
        for p in removed { removeFromTree(p) }
        if !removed.isEmpty {
            let set = Set(removed)
            func gone(_ path: String) -> Bool {
                set.contains(path) || removed.contains { path.hasPrefix($0 + "/") }
            }
            for i in cleanup.indices { cleanup[i].items.removeAll { gone($0.path) } }
            cleanup.removeAll { $0.items.isEmpty }
            cleanupSelection = cleanupSelection.filter { !gone($0) }
            largeFiles.removeAll { gone($0.path) }
            for i in duplicates.indices { duplicates[i].files.removeAll { gone($0.path) } }
            duplicates.removeAll { $0.files.count < 2 }
            revision += 1
            refreshTrashSize()
        }
        if !failed.isEmpty {
            errorMessage = "Bazı öğeler taşınamadı:\n" + failed.prefix(8).joined(separator: "\n")
                + (failed.count > 8 ? "\n… ve \(failed.count - 8) öğe daha" : "")
        }
    }

    func findNode(_ path: String) -> FileNode? {
        guard let root else { return nil }
        let rp = root.name
        if path == rp { return root }
        let prefix = rp.hasSuffix("/") ? rp : rp + "/"
        guard path.hasPrefix(prefix) else { return nil }
        var node = root
        for comp in path.dropFirst(prefix.count).split(separator: "/") {
            guard let next = node.children.first(where: { !$0.isSynthetic && $0.name == comp }) else { return nil }
            node = next
        }
        return node
    }

    private func removeFromTree(_ path: String) {
        guard let n = findNode(path), let parent = n.parent else { return }
        if let c = current, c.isDescendant(of: n) { current = parent }
        parent.children.removeAll { $0 === n }
        var p: FileNode? = parent
        while let x = p {
            x.size -= n.size
            x.fileCount -= n.fileCount
            p = x.parent
        }
        // Üst klasörlerdeki sıralamayı koru
        var q: FileNode? = parent
        while let x = q, let pp = x.parent {
            pp.children.sort { $0.size > $1.size }
            q = pp
        }
    }

    // MARK: - Kopyalar

    func findDuplicates() {
        guard let root, dupState != .running(0) else { return }
        if case .running = dupState { return }
        let cands = Scanner.collectFiles(root, minSize: DuplicateFinder.minSize).map { ($0, $0.path) }
        let cancel = CancelFlag()
        dupCancel = cancel
        dupState = .running(0)
        Task.detached(priority: .utility) {
            var last = Date.distantPast
            let groups = DuplicateFinder.find(candidates: cands, cancel: cancel) { frac in
                let now = Date()
                if now.timeIntervalSince(last) > 0.15 {
                    last = now
                    Task { @MainActor in
                        if self.dupCancel === cancel, case .running = self.dupState { self.dupState = .running(frac) }
                    }
                }
            }
            await MainActor.run {
                guard self.dupCancel === cancel else { return }
                if cancel.value { self.dupState = .idle; return }
                self.duplicates = groups
                self.dupState = .done
            }
        }
    }

    func cancelDuplicates() {
        dupCancel?.value = true
        dupState = .idle
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
