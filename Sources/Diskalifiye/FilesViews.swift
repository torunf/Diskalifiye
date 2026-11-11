import SwiftUI

struct NeedsScanView: View {
    let title: String
    let icon: String
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.scanning {
            ScanProgressView()
        } else {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text("Bu bölüm için önce bir tarama gerekiyor.")
            } actions: {
                Button("Ev Klasörünü Tara") { state.startScan(homePath) }.buttonStyle(.borderedProminent)
            }
        }
    }
}

struct FileRow: View {
    let node: FileNode
    @EnvironmentObject var state: AppState
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: node.kind.icon)
                .foregroundStyle(node.kind.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).lineLimit(1).truncationMode(.middle)
                Text(tildePath((node.path as NSString).deletingLastPathComponent))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            if hover {
                Button { revealInFinder(node.path) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless).help("Finder'da göster")
                Button { state.requestTrash(nodes: [node]) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Çöp Kutusuna taşı")
            }
            Text(fmt(node.size)).monospacedDigit().fontWeight(.medium).frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu { NodeMenu(node: node, onOpen: nil) }
    }
}

struct LargeFilesView: View {
    @EnvironmentObject var state: AppState
    @State private var kind: FileKind?
    @State private var query = ""
    @State private var selection: Set<FileNode.ID> = []

    private var files: [FileNode] {
        state.largeFiles.filter { n in
            (kind == nil || n.kind == kind) && (query.isEmpty || n.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        if state.root == nil {
            NeedsScanView(title: "Büyük Dosyalar", icon: "doc.badge.arrow.up")
        } else {
            let files = self.files
            let selected = files.filter { selection.contains($0.id) }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("Tür", selection: $kind) {
                        Text("Tüm türler").tag(FileKind?.none)
                        Divider()
                        ForEach(FileKind.fileKinds) { k in Text(k.title).tag(FileKind?.some(k)) }
                    }
                    .frame(width: 220)
                    TextField("Ada göre filtrele", text: $query)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    Spacer()
                    Text("\(files.count) dosya · \(fmt(files.reduce(0) { $0 + $1.size }))")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(12)
                Divider()
                List(files, selection: $selection) { n in
                    FileRow(node: n)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                if !selected.isEmpty {
                    Divider()
                    HStack {
                        Text("\(selected.count) dosya seçili · \(fmt(selected.reduce(0) { $0 + $1.size }))").foregroundStyle(.secondary)
                        Spacer()
                        Button { state.requestTrash(nodes: selected) } label: { Label("Seçilenleri Çöpe Taşı", systemImage: "trash") }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.bar)
                }
            }
        }
    }
}

struct DuplicatesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.root == nil {
            NeedsScanView(title: "Kopya Dosyalar", icon: "doc.on.doc")
        } else {
            switch state.dupState {
            case .idle:
                ContentUnavailableView {
                    Label("Kopya Dosyaları Bul", systemImage: "doc.on.doc")
                } description: {
                    Text("1 MB'tan büyük dosyalar içerik özetleriyle (SHA-256) karşılaştırılır. Büyük disklerde birkaç dakika sürebilir.")
                } actions: {
                    Button("Kopyaları Ara") { state.findDuplicates() }.buttonStyle(.borderedProminent)
                }
            case .running(let frac):
                VStack(spacing: 14) {
                    ProgressView(value: frac).frame(width: 320)
                    Text("Dosya içerikleri karşılaştırılıyor… %\(Int(frac * 100))").foregroundStyle(.secondary).monospacedDigit()
                    Button("Vazgeç") { state.cancelDuplicates() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done:
                if state.duplicates.isEmpty {
                    ContentUnavailableView {
                        Label("Kopya dosya bulunamadı", systemImage: "checkmark.seal")
                    } actions: {
                        Button("Yeniden Ara") { state.findDuplicates() }
                    }
                } else {
                    results
                }
            }
        }
    }

    private var results: some View {
        let wasted = state.duplicates.reduce(Int64(0)) { $0 + $1.wasted }
        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fmt(wasted)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("\(state.duplicates.count) kopya grubunda geri kazanılabilir").foregroundStyle(.secondary)
                }
                Spacer()
                Button { state.findDuplicates() } label: { Label("Yeniden Ara", systemImage: "arrow.clockwise") }
            }
            .padding(16)
            Divider()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(state.duplicates) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: g.files[0].kind.icon).foregroundStyle(g.files[0].kind.color)
                                Text("\(g.files.count) kopya · her biri \(fmt(g.size))").font(.headline)
                                Spacer()
                                Button("İlkini Tut, Diğerlerini Çöpe Taşı (\(fmt(g.wasted)))") {
                                    state.requestTrash(nodes: Array(g.files.dropFirst()))
                                }
                            }
                            .padding(.bottom, 2)
                            ForEach(g.files) { f in
                                FileRow(node: f)
                            }
                        }
                        .padding(12)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                    }
                }
                .padding(16)
            }
        }
    }
}
