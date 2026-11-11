import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var state: AppState
    @State private var hovered: FileNode?

    var body: some View {
        if state.scanning {
            ScanProgressView()
        } else if let current = state.current, let root = state.root {
            VStack(spacing: 0) {
                Breadcrumb(root: root, current: current)
                HSplitView {
                    VStack(spacing: 8) {
                        TreemapView(node: current, revision: state.revision, hovered: $hovered) { state.current = $0 }
                        HoverBar(node: hovered, current: current)
                    }
                    .padding(12)
                    .frame(minWidth: 420)
                    SidePanel(current: current, hovered: $hovered)
                        .frame(minWidth: 270, idealWidth: 310, maxWidth: 420)
                }
            }
        } else {
            WelcomeView()
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 54))
                .foregroundStyle(.linearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 6) {
                Text("Diskalifiye").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Diskinde boşuna yer kaplayanları bul ve diskalifiye et.")
                    .font(.title3).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ScanButton(title: "Ev Klasörü", subtitle: "~ (önerilen)", icon: "house.fill", prominent: true) { state.startScan(homePath) }
                ScanButton(title: "Tüm Disk", subtitle: state.disk.name, icon: "internaldrive", prominent: false) { state.startScan("/") }
                ScanButton(title: "Klasör Seç…", subtitle: "Belirli bir konum", icon: "folder", prominent: false) { state.pickFolderAndScan() }
            }
            VStack(spacing: 8) {
                Label("Daha eksiksiz sonuç için uygulamaya Tam Disk Erişimi verebilirsin. Aksi halde macOS bazı klasörleri gizler.", systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Tam Disk Erişimi Ayarlarını Aç") { state.openFullDiskAccessSettings() }
                    .buttonStyle(.link)
            }
            .frame(maxWidth: 520)
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let prominent: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 24))
                Text(title).font(.headline)
                Text(subtitle).font(.caption).opacity(0.7).lineLimit(1)
            }
            .frame(width: 150, height: 104)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(hover ? 0.25 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ScanProgressView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Taranıyor…").font(.title2.weight(.semibold))
            HStack(spacing: 28) {
                Stat(value: state.progress.files.formatted(), label: "dosya")
                Stat(value: fmt(state.progress.bytes), label: "bulundu")
            }
            Text(tildePath(state.progress.path))
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 560)
            Button("Vazgeç") { state.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct Breadcrumb: View {
    let root: FileNode
    let current: FileNode
    @EnvironmentObject var state: AppState

    private var chain: [FileNode] {
        var out: [FileNode] = []
        var n: FileNode? = current
        while let x = n { out.append(x); n = x.parent }
        return out.reversed()
    }

    var body: some View {
        HStack(spacing: 6) {
            Button { if let p = current.parent { state.current = p } } label: { Image(systemName: "chevron.up") }
                .disabled(current.parent == nil)
                .help("Üst klasör")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(chain.enumerated()), id: \.element.id) { i, n in
                        if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        Button { state.current = n } label: {
                            Text(n.displayName).fontWeight(n === current ? .semibold : .regular)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(n === current ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            Spacer()
            Text("\(fmt(current.size)) · \(current.fileCount.formatted()) dosya")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct HoverBar: View {
    let node: FileNode?
    let current: FileNode

    var body: some View {
        HStack(spacing: 8) {
            if let n = node {
                Image(systemName: n.kind.icon).foregroundStyle(.secondary)
                Text(tildePath(n.path) + (n.isSynthetic ? "  ›  \(n.name)" : ""))
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                if current.size > 0 {
                    Text(String(format: "%%%.1f", Double(n.size) / Double(current.size) * 100)).foregroundStyle(.secondary)
                }
                Text(fmt(n.size)).fontWeight(.semibold)
            } else {
                Text("Yakınlaşmak için bir alana tıkla · seçenekler için sağ tıkla").foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .font(.callout).monospacedDigit()
        .frame(height: 18)
        .padding(.horizontal, 4)
    }
}

struct SidePanel: View {
    let current: FileNode
    @Binding var hovered: FileNode?
    @EnvironmentObject var state: AppState

    private func top(_ n: FileNode?) -> FileNode? {
        var x = n
        while let y = x, let p = y.parent {
            if p === current { return y }
            x = p
        }
        return nil
    }

    var body: some View {
        let kids = current.children.filter { $0.size > 0 }
        let hoverTop = top(hovered)
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(kids.enumerated()), id: \.element.id) { i, n in
                        ChildRow(node: n, index: i, fraction: Double(n.size) / Double(max(1, current.size)), highlighted: hoverTop === n)
                            .onHover { inside in
                                if inside { hovered = n } else if hovered === n { hovered = nil }
                            }
                            .onTapGesture { if n.isDir && !n.children.isEmpty { state.current = n } }
                            .contextMenu { NodeMenu(node: n) { state.current = $0 } }
                    }
                }
                .padding(8)
            }
            Divider()
            KindBreakdown()
                .padding(12)
        }
        .background(.background)
    }
}

struct ChildRow: View {
    let node: FileNode
    let index: Int
    let fraction: Double
    let highlighted: Bool

    var body: some View {
        let color = node.isSynthetic ? Color(white: 0.5) : Palette.color(index)
        HStack(spacing: 8) {
            Image(systemName: node.isDir ? "folder.fill" : node.kind.icon)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(fmt(node.size)).foregroundStyle(.secondary).monospacedDigit()
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(color).frame(width: max(2, g.size.width * fraction))
                    }
                }
                .frame(height: 3)
            }
            if node.isDir && !node.children.isEmpty {
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            } else {
                Color.clear.frame(width: 7, height: 1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(highlighted ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
}

struct KindBreakdown: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let kinds = FileKind.fileKinds
            .map { ($0, state.kindTotals[Int($0.rawValue)]) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        let total = max(1, kinds.reduce(Int64(0)) { $0 + $1.1 })
        VStack(alignment: .leading, spacing: 8) {
            Text("Dosya Türleri").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            GeometryReader { g in
                HStack(spacing: 1.5) {
                    ForEach(kinds, id: \.0) { k, v in
                        k.color.frame(width: max(1, (g.size.width - CGFloat(kinds.count) * 1.5) * Double(v) / Double(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 4) {
                ForEach(kinds, id: \.0) { k, v in
                    HStack(spacing: 5) {
                        Circle().fill(k.color).frame(width: 7, height: 7)
                        Text(k.title).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(fmt(v)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            if state.denied > 0 {
                Label("\(state.denied.formatted()) klasör okunamadı (izin yok)", systemImage: "lock")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
