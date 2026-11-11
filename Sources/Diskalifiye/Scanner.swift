import Foundation

struct ProgressSnapshot {
    var files = 0
    var bytes: Int64 = 0
    var path = ""
    var kinds = [Int64](repeating: 0, count: FileKind.allCases.count)
    var denied = 0
}

final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var snap = ProgressSnapshot()
    private var seen = Set<UInt64>()
    private var _cancelled = false

    var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _cancelled }
        set { lock.lock(); _cancelled = newValue; lock.unlock() }
    }

    func firstSeen(_ ino: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return seen.insert(ino).inserted
    }

    func snapshot() -> ProgressSnapshot {
        lock.lock(); defer { lock.unlock() }
        return snap
    }

    fileprivate func merge(_ acc: inout Acc, path: String?) {
        lock.lock()
        snap.files += acc.files
        snap.bytes += acc.bytes
        snap.denied += acc.denied
        for i in 0..<acc.kinds.count { snap.kinds[i] += acc.kinds[i] }
        if let path { snap.path = path }
        lock.unlock()
        acc = Acc()
    }
}

private struct Acc {
    var files = 0
    var bytes: Int64 = 0
    var denied = 0
    var kinds = [Int64](repeating: 0, count: FileKind.allCases.count)
}

enum Scanner {
    /// Bu boyutun altındaki dosya ve klasörler tek tek tutulmaz, üst klasörde toplanır.
    static let fileThreshold: Int64 = 256 * 1024
    static let dirThreshold: Int64 = 256 * 1024
    private static let manualDepth = 3
    private static let rootSkips: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/.vol"]

    static func scan(rootPath: String, progress: ScanProgress) -> FileNode? {
        var rst = stat()
        guard lstat(rootPath, &rst) == 0 else { return nil }
        var devs: Set<Int32> = [rst.st_dev]
        if rootPath == "/" {
            var dst = stat()
            if lstat("/System/Volumes/Data", &dst) == 0 { devs.insert(dst.st_dev) }
        }

        let root = FileNode(name: rootPath, isDir: true, kind: .folder)
        root.pending = true
        var jobs: [(String, FileNode)] = []
        var acc = Acc()
        expand(root, rootPath, 0, devs, &jobs, &acc, progress)
        progress.merge(&acc, path: rootPath)

        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
            if progress.cancelled { return }
            let (path, parent) = jobs[i]
            if let node = ftsScan(path: path, devs: devs, progress: progress) {
                lock.lock()
                node.parent = parent
                parent.children.append(node)
                lock.unlock()
            }
        }
        if progress.cancelled { return nil }
        finalizeManual(root)
        return root
    }

    private static func join(_ dir: String, _ name: String) -> String {
        dir.hasSuffix("/") ? dir + name : dir + "/" + name
    }

    private static func expand(_ node: FileNode, _ path: String, _ depth: Int, _ devs: Set<Int32>,
                               _ jobs: inout [(String, FileNode)], _ acc: inout Acc, _ progress: ScanProgress) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            acc.denied += 1
            return
        }
        for name in names {
            let full = join(path, name)
            var st = stat()
            guard lstat(full, &st) == 0 else { continue }
            if (st.st_mode & S_IFMT) == S_IFDIR {
                if rootSkips.contains(full) || !devs.contains(st.st_dev) { continue }
                if depth + 1 < manualDepth {
                    let child = FileNode(name: name, isDir: true, kind: .folder)
                    child.pending = true
                    child.parent = node
                    node.children.append(child)
                    expand(child, full, depth + 1, devs, &jobs, &acc, progress)
                } else {
                    jobs.append((full, node))
                }
            } else {
                addFile(name: name, st: st, to: node, acc: &acc, progress: progress)
            }
        }
    }

    private static func finalizeManual(_ node: FileNode) {
        var kept: [FileNode] = []
        kept.reserveCapacity(node.children.count)
        for c in node.children {
            if c.pending { finalizeManual(c); c.pending = false }
            if c.isDir && c.size < dirThreshold {
                node.smallSize += c.size
                node.smallCount += c.fileCount
            } else {
                kept.append(c)
            }
        }
        node.children = kept
        node.finalize()
    }

    @inline(__always)
    private static func addFile(name: @autoclosure () -> String, st: stat, to parent: FileNode,
                                acc: inout Acc, progress: ScanProgress) {
        let size = Int64(st.st_blocks) * 512
        if st.st_nlink > 1 && (st.st_mode & S_IFMT) == S_IFREG && !progress.firstSeen(UInt64(st.st_ino)) { return }
        acc.files += 1
        acc.bytes += size
        if size >= fileThreshold {
            let nm = name()
            let kind = FileKind.of(nm)
            acc.kinds[Int(kind.rawValue)] += size
            let n = FileNode(name: nm, isDir: false, kind: kind, size: size)
            n.fileCount = 1
            n.parent = parent
            parent.children.append(n)
        } else {
            if size > 0 { acc.kinds[Int(FileKind.of(name()).rawValue)] += size }
            parent.smallSize += size
            parent.smallCount += 1
        }
    }

    private static let nameOffset = MemoryLayout<FTSENT>.offset(of: \FTSENT.fts_name)!

    private static func ftsScan(path: String, devs: Set<Int32>, progress: ScanProgress) -> FileNode? {
        guard let cpath = strdup(path) else { return nil }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = argv.withUnsafeMutableBufferPointer({ fts_open($0.baseAddress!, FTS_PHYSICAL | FTS_NOCHDIR, nil) }) else { return nil }
        defer { fts_close(fts) }

        var stack: [FileNode] = []
        var result: FileNode?
        var acc = Acc()
        var sinceFlush = 0

        while let ent = fts_read(fts) {
            let info = Int32(ent.pointee.fts_info)
            switch info {
            case FTS_D:
                let name: String
                if stack.isEmpty {
                    name = (path as NSString).lastPathComponent
                } else {
                    name = String(cString: UnsafeRawPointer(ent).advanced(by: nameOffset).assumingMemoryBound(to: CChar.self))
                }
                stack.append(FileNode(name: name, isDir: true, kind: .folder))
                if let st = ent.pointee.fts_statp, !devs.contains(st.pointee.st_dev) {
                    fts_set(fts, ent, FTS_SKIP)
                }
            case FTS_DP, FTS_DNR:
                guard let node = stack.popLast() else { continue }
                if info == FTS_DNR { acc.denied += 1 }
                node.finalize()
                if let parent = stack.last {
                    if node.size >= dirThreshold {
                        node.parent = parent
                        parent.children.append(node)
                    } else {
                        parent.smallSize += node.size
                        parent.smallCount += node.fileCount
                    }
                } else {
                    result = node
                }
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let parent = stack.last, let st = ent.pointee.fts_statp else { continue }
                addFile(name: String(cString: UnsafeRawPointer(ent).advanced(by: nameOffset).assumingMemoryBound(to: CChar.self)),
                        st: st.pointee, to: parent, acc: &acc, progress: progress)
                sinceFlush += 1
                if sinceFlush >= 4096 {
                    sinceFlush = 0
                    progress.merge(&acc, path: String(cString: ent.pointee.fts_path))
                    if progress.cancelled { return nil }
                }
            default:
                break
            }
        }
        progress.merge(&acc, path: nil)
        return result
    }

    /// Bir yolun diskte kapladığı toplam alan (ağaç kurmadan).
    static func du(_ path: String) -> Int64 {
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        if (st.st_mode & S_IFMT) != S_IFDIR { return Int64(st.st_blocks) * 512 }
        guard let cpath = strdup(path) else { return 0 }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = argv.withUnsafeMutableBufferPointer({ fts_open($0.baseAddress!, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) }) else { return 0 }
        defer { fts_close(fts) }
        var total: Int64 = 0
        while let ent = fts_read(fts) {
            let info = Int32(ent.pointee.fts_info)
            if info == FTS_F || info == FTS_SL || info == FTS_SLNONE || info == FTS_DEFAULT, let s = ent.pointee.fts_statp {
                total += Int64(s.pointee.st_blocks) * 512
            }
        }
        return total
    }

    /// Büyükten küçüğe tüm gerçek dosya düğümleri.
    static func collectFiles(_ root: FileNode, minSize: Int64) -> [FileNode] {
        var out: [FileNode] = []
        var stack = [root]
        while let n = stack.popLast() {
            for c in n.children {
                if c.isDir { stack.append(c) }
                else if !c.isSynthetic && c.size >= minSize { out.append(c) }
            }
        }
        out.sort { $0.size > $1.size }
        return out
    }
}
