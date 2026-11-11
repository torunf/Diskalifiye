import SwiftUI
import AppKit

@main
struct DiskalifiyeApp: App {
    @StateObject private var state = AppState()

    init() {
        // Geliştirme/test için: Diskalifiye --scan <yol>
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--scan"), i + 1 < args.count {
            CLI.run(path: args[i + 1])
            exit(0)
        }
    }

    var body: some Scene {
        Window("Diskalifiye", id: "main") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Ev Klasörünü Tara") { state.startScan(homePath) }.keyboardShortcut("1")
                Button("Tüm Diski Tara") { state.startScan("/") }.keyboardShortcut("2")
                Button("Klasör Seç ve Tara…") { state.pickFolderAndScan() }.keyboardShortcut("o")
                Divider()
                Button("Yeniden Tara") { state.rescan() }.keyboardShortcut("r").disabled(state.scanPath == nil || state.scanning)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(AppState.Section.allCases, selection: $state.section) { s in
                HStack {
                    Label(s.title, systemImage: s.icon)
                    Spacer()
                    if s == .cleanup, state.cleanupTotal > 0 {
                        Text(fmt(state.cleanupTotal)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    if s == .duplicates, !state.duplicates.isEmpty {
                        Text("\(state.duplicates.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(s)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
            .safeAreaInset(edge: .bottom) { DiskCard().padding(10) }
        } detail: {
            Group {
                switch state.section ?? .overview {
                case .overview: OverviewView()
                case .cleanup: CleanupView()
                case .large: LargeFilesView()
                case .duplicates: DuplicatesView()
                }
            }
            .navigationTitle(state.section?.title ?? "Diskalifiye")
            .navigationSubtitle(state.scanPath.map { $0 == "/" ? state.disk.name : tildePath($0) } ?? "")
            .toolbar {
                ToolbarItemGroup {
                    if state.scanning {
                        Button { state.cancelScan() } label: { Label("Durdur", systemImage: "stop.fill") }
                    } else {
                        Menu {
                            Button("Ev Klasörü") { state.startScan(homePath) }
                            Button("Tüm Disk (\(state.disk.name))") { state.startScan("/") }
                            Button("Klasör Seç…") { state.pickFolderAndScan() }
                            if state.scanPath != nil {
                                Divider()
                                Button("Yeniden Tara") { state.rescan() }
                            }
                        } label: {
                            Label("Tara", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .alert("Çöp Kutusuna taşınsın mı?", isPresented: Binding(get: { state.pendingTrash != nil }, set: { if !$0 { state.pendingTrash = nil } }), presenting: state.pendingTrash) { req in
            Button("Çöp Kutusuna Taşı", role: .destructive) { state.performTrash(req) }
            Button("Vazgeç", role: .cancel) {}
        } message: { req in
            Text(req.paths.count == 1
                 ? "\(tildePath(req.paths[0]))\n\n\(fmt(req.size)) · Çöp Kutusu'ndan geri alınabilir."
                 : "\(req.paths.count) öğe · \(fmt(req.size))\n\nÇöp Kutusu'ndan geri alınabilir.")
        }
        .alert("Çöp Kutusu boşaltılsın mı?", isPresented: $state.confirmEmptyTrash) {
            Button("Kalıcı Olarak Sil", role: .destructive) { state.emptyTrash() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Çöp Kutusu'ndaki tüm öğeler kalıcı olarak silinir. Bu işlem geri alınamaz.")
        }
        .alert("Bir sorun oluştu", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

struct DiskCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let d = state.disk
        let frac = d.usedFraction
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "internaldrive.fill").foregroundStyle(.secondary)
                Text(d.name).fontWeight(.semibold).lineLimit(1)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(frac > 0.9 ? Color.red : frac > 0.75 ? Color.orange : Color.accentColor)
                        .frame(width: max(4, g.size.width * frac))
                }
            }
            .frame(height: 6)
            Text("\(fmt(d.available)) boş / \(fmt(d.total))")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.callout)
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

enum CLI {
    static func run(path: String) {
        let sp = ScanProgress()
        let t = Date()
        guard let root = Scanner.scan(rootPath: path, progress: sp) else { print("tarama başarısız"); return }
        let snap = sp.snapshot()
        print(String(format: "%@  %@  %d dosya  %.2fs  (okunamayan: %d)", path, fmt(root.size), snap.files, Date().timeIntervalSince(t), snap.denied))
        for c in root.children.prefix(12) { print("  \(fmt(c.size))\t\(c.name)") }
        var nodes = 0
        var stack = [root]
        while let n = stack.popLast() { nodes += 1; stack.append(contentsOf: n.children) }
        print("düğüm: \(nodes)")
        for k in FileKind.fileKinds { print("  \(k.title): \(fmt(snap.kinds[Int(k.rawValue)]))") }
        if CommandLine.arguments.contains("--cleanup") {
            for c in CleanupEngine.analyze(root: root) {
                print("[\(c.risk.title)] \(c.title): \(fmt(c.total)) (\(c.items.count) öğe)")
                let all = CommandLine.arguments.contains("--all")
                for i in c.items.prefix(all ? Int.max : 3) { print("    \(fmt(i.size))\t\(all ? i.path : i.name)") }
            }
        }
    }
}
