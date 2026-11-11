import SwiftUI

struct TreemapCell {
    let node: FileNode
    let rect: CGRect
    let depth: Int
    let hue: Int
    let container: Bool
    let header: Bool
    let variant: Int
}

enum Treemap {
    static func layout(node: FileNode, in rect: CGRect) -> [TreemapCell] {
        var cells: [TreemapCell] = []
        place(node, rect, 0, 0, &cells)
        return cells
    }

    private static func place(_ node: FileNode, _ rect: CGRect, _ depth: Int, _ hue: Int, _ cells: inout [TreemapCell]) {
        guard rect.width > 4, rect.height > 4 else { return }
        let total = Double(node.children.reduce(Int64(0)) { $0 + max(0, $1.size) })
        guard total > 0 else { return }
        let area = Double(rect.width * rect.height)
        var included: [FileNode] = []
        var sum = 0.0
        for k in node.children where k.size > 0 {
            if Double(k.size) / total * area < 30 { break }
            included.append(k)
            sum += Double(k.size)
        }
        guard !included.isEmpty else { return }
        let scale = area / sum
        let rects = squarify(included.map { Double($0.size) * scale }, in: rect)
        for (i, (k, r)) in zip(included, rects).enumerated() {
            let h = depth == 0 ? i : hue
            let rr = r.insetBy(dx: 0.5, dy: 0.5)
            let nest = k.isDir && !k.children.isEmpty && depth < 5 && rr.width > 24 && rr.height > 24
            if nest {
                let header: CGFloat = (rr.width > 56 && rr.height > 40) ? 15 : 0
                cells.append(TreemapCell(node: k, rect: rr, depth: depth, hue: h, container: true, header: header > 0, variant: i))
                let inner = CGRect(x: rr.minX + 2, y: rr.minY + 2 + header, width: rr.width - 4, height: rr.height - 4 - header)
                place(k, inner, depth + 1, h, &cells)
            } else {
                cells.append(TreemapCell(node: k, rect: rr, depth: depth, hue: h, container: false, header: false, variant: i))
            }
        }
    }

    /// Squarified treemap: alanlar büyükten küçüğe sıralı ve toplamı dikdörtgenin alanına eşit olmalı.
    static func squarify(_ areas: [Double], in rect: CGRect) -> [CGRect] {
        var rects: [CGRect] = []
        rects.reserveCapacity(areas.count)
        var free = rect
        var i = 0
        while i < areas.count {
            let side = Double(min(free.width, free.height))
            if side <= 0 { break }
            func worst(_ s: Double, _ mn: Double, _ mx: Double) -> Double {
                let s2 = s * s, w2 = side * side
                return max(w2 * mx / s2, s2 / (w2 * mn))
            }
            var row = [areas[i]]
            var sum = areas[i], minA = areas[i], maxA = areas[i]
            var j = i + 1
            while j < areas.count {
                let a = areas[j]
                if worst(sum + a, min(minA, a), max(maxA, a)) <= worst(sum, minA, maxA) {
                    row.append(a); sum += a; minA = min(minA, a); maxA = max(maxA, a); j += 1
                } else { break }
            }
            let thickness = sum / side
            var offset = 0.0
            if free.width >= free.height {
                for a in row {
                    let h = a / thickness
                    rects.append(CGRect(x: Double(free.minX), y: Double(free.minY) + offset, width: thickness, height: h))
                    offset += h
                }
                free = CGRect(x: free.minX + thickness, y: free.minY, width: max(0, free.width - thickness), height: free.height)
            } else {
                for a in row {
                    let w = a / thickness
                    rects.append(CGRect(x: Double(free.minX) + offset, y: Double(free.minY), width: w, height: thickness))
                    offset += w
                }
                free = CGRect(x: free.minX, y: free.minY + thickness, width: free.width, height: max(0, free.height - thickness))
            }
            i = j
        }
        return rects
    }
}

private final class LayoutCache {
    var key = ""
    var cells: [TreemapCell] = []
}

struct TreemapView: View {
    let node: FileNode
    let revision: Int
    @Binding var hovered: FileNode?
    var onOpen: (FileNode) -> Void
    @EnvironmentObject var state: AppState
    @State private var cache = LayoutCache()
    @State private var menuTarget: FileNode?

    private func cells(_ size: CGSize) -> [TreemapCell] {
        let key = "\(ObjectIdentifier(node).hashValue)-\(revision)-\(Int(size.width))x\(Int(size.height))"
        if cache.key != key {
            cache.key = key
            cache.cells = Treemap.layout(node: node, in: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4))
        }
        return cache.cells
    }

    private func fill(_ c: TreemapCell) -> Color {
        if c.node.isSynthetic { return Color(white: 0.40) }
        let h = Palette.hue(c.hue)
        if c.container {
            return Color(hue: h, saturation: 0.50, brightness: 0.22 + 0.07 * Double(c.depth))
        }
        return Color(hue: h, saturation: 0.60 - 0.06 * Double(c.depth % 3), brightness: 0.93 - 0.07 * Double(c.variant % 3))
    }

    private func cell(at p: CGPoint, in cells: [TreemapCell]) -> TreemapCell? {
        for c in cells.reversed() where c.rect.contains(p) { return c }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let cells = cells(geo.size)
            Canvas { ctx, _ in
                for c in cells {
                    let path = Path(roundedRect: c.rect, cornerRadius: c.container ? 4 : 2.5)
                    ctx.fill(path, with: .color(fill(c)))
                    if c.container {
                        if c.header {
                            var t = ctx
                            t.clip(to: Path(CGRect(x: c.rect.minX + 4, y: c.rect.minY, width: c.rect.width - 8, height: 17)))
                            t.draw(Text("\(c.node.name)  \(Text(fmt(c.node.size)).foregroundColor(.white.opacity(0.55)))")
                                .font(.system(size: 10.5, weight: .semibold)).foregroundColor(.white.opacity(0.92)),
                                   at: CGPoint(x: c.rect.minX + 5, y: c.rect.minY + 2.5), anchor: .topLeading)
                        }
                    } else if c.rect.width > 46 && c.rect.height > 16 {
                        var t = ctx
                        t.clip(to: Path(c.rect.insetBy(dx: 3, dy: 1)))
                        let dark = Color.black.opacity(c.node.isSynthetic ? 0.0 : 0.78)
                        let fg = c.node.isSynthetic ? Color.white.opacity(0.85) : dark
                        t.draw(Text(c.node.name).font(.system(size: 10.5, weight: .medium)).foregroundColor(fg),
                               at: CGPoint(x: c.rect.minX + 4, y: c.rect.minY + 3), anchor: .topLeading)
                        if c.rect.height > 30 {
                            t.draw(Text(fmt(c.node.size)).font(.system(size: 9.5)).foregroundColor(fg.opacity(0.7)),
                                   at: CGPoint(x: c.rect.minX + 4, y: c.rect.minY + 16), anchor: .topLeading)
                        }
                    }
                }
                if let h = hovered, let c = cells.first(where: { $0.node === h }) {
                    ctx.stroke(Path(roundedRect: c.rect.insetBy(dx: 1, dy: 1), cornerRadius: 3), with: .color(.white), lineWidth: 2)
                }
            }
            .background(Color(white: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let n = cell(at: p, in: cells)?.node
                    if hovered !== n { hovered = n }
                    if let n { menuTarget = n }
                case .ended:
                    hovered = nil
                }
            }
            .onTapGesture { p in
                guard let c = cell(at: p, in: cells) else { return }
                // Tıklanan hücrenin, mevcut klasörün doğrudan çocuğu olan atasına yakınlaş
                var n = c.node
                while let par = n.parent, par !== node { n = par }
                if n.isDir && !n.children.isEmpty { onOpen(n) }
            }
            .contextMenu {
                if let n = menuTarget {
                    NodeMenu(node: n, onOpen: onOpen)
                }
            }
        }
    }
}

struct NodeMenu: View {
    let node: FileNode
    var onOpen: ((FileNode) -> Void)?
    @EnvironmentObject var state: AppState

    var body: some View {
        Text("\(node.name) — \(fmt(node.size))")
        Divider()
        if let onOpen, node.isDir, !node.children.isEmpty {
            Button("Bu Klasöre Yakınlaş") { onOpen(node) }
        }
        Button("Finder'da Göster") { revealInFinder(node.path) }
        Button("Yolu Kopyala") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.path, forType: .string)
        }
        if !node.isSynthetic && node.parent != nil {
            Divider()
            Button("Çöp Kutusuna Taşı…", role: .destructive) { state.requestTrash(nodes: [node]) }
        }
    }
}
