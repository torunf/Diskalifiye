import Foundation
import CryptoKit

struct DuplicateGroup: Identifiable {
    let id: String
    let size: Int64
    var files: [FileNode]
    var wasted: Int64 { size * Int64(max(0, files.count - 1)) }
}

final class CancelFlag: @unchecked Sendable {
    var value = false
}

enum DuplicateFinder {
    static let minSize: Int64 = 1 << 20

    static func find(candidates: [(FileNode, String)], cancel: CancelFlag, progress: @escaping (Double) -> Void) -> [DuplicateGroup] {
        struct Cand { let node: FileNode; let path: String; let size: Int64 }
        // 1) Mantıksal boyuta göre grupla
        var bySize: [Int64: [Cand]] = [:]
        var inodes = Set<UInt64>()
        for (node, path) in candidates {
            var st = stat()
            guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
            if st.st_flags & 0x4000_0000 != 0 { continue } // iCloud'da duran (indirilmemiş) dosyaları atla
            guard inodes.insert(UInt64(st.st_ino)).inserted else { continue }
            bySize[Int64(st.st_size), default: []].append(Cand(node: node, path: path, size: Int64(st.st_size)))
        }
        // 2) Baş + son 64 KB hızlı özet
        var quick: [String: [Cand]] = [:]
        for (size, group) in bySize where group.count > 1 {
            for c in group {
                if cancel.value { return [] }
                guard let h = hash(c.path, quick: true, cancel: cancel) else { continue }
                quick["\(size)-\(h)", default: []].append(c)
            }
        }
        // 3) Tam SHA-256
        let pending = quick.values.filter { $0.count > 1 }
        let totalBytes = max(1, pending.reduce(Int64(0)) { $0 + $1.reduce(0) { $0 + $1.size } })
        var done: Int64 = 0
        var groups: [DuplicateGroup] = []
        for group in pending {
            var full: [String: [Cand]] = [:]
            for c in group {
                if cancel.value { return [] }
                if let h = hash(c.path, quick: false, cancel: cancel) { full[h, default: []].append(c) }
                done += c.size
                progress(Double(done) / Double(totalBytes))
            }
            for (h, cs) in full where cs.count > 1 {
                groups.append(DuplicateGroup(id: h, size: cs[0].node.size, files: cs.map { $0.node }))
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    private static func hash(_ path: String, quick: Bool, cancel: CancelFlag) -> String? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        var hasher = SHA256()
        let cap = quick ? 64 * 1024 : 1 << 20
        let buf = UnsafeMutableRawBufferPointer.allocate(byteCount: cap, alignment: 16)
        defer { buf.deallocate() }
        if quick {
            let n = read(fd, buf.baseAddress, cap)
            guard n >= 0 else { return nil }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buf[0..<n]))
            let end = lseek(fd, 0, SEEK_END)
            if end > off_t(cap) {
                lseek(fd, end - off_t(cap), SEEK_SET)
                let m = read(fd, buf.baseAddress, cap)
                guard m >= 0 else { return nil }
                hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buf[0..<m]))
            }
        } else {
            while true {
                if cancel.value { return nil }
                let n = read(fd, buf.baseAddress, cap)
                if n < 0 { return nil }
                if n == 0 { break }
                hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buf[0..<n]))
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
