import SwiftUI

struct CleanupView: View {
    @EnvironmentObject var state: AppState
    @State private var expanded: Set<String> = []

    private var selectedItems: [CleanupItem] {
        state.cleanup.flatMap { $0.items }.filter { state.cleanupSelection.contains($0.path) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.cleanupAnalyzing && state.cleanup.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Temizlenebilir alanlar hesaplanıyor…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.cleanup.isEmpty {
                ContentUnavailableView("Temizlenecek bir şey bulunamadı", systemImage: "checkmark.seal",
                                       description: Text("Diskin gayet derli toplu görünüyor."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if state.root == nil {
                            Label("Proje artıklarını (node_modules, build vb.) da görmek için önce Disk Haritası'ndan bir tarama başlat.", systemImage: "info.circle")
                                .font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                        ForEach(state.cleanup) { cat in
                            CategoryCard(category: cat, expanded: expanded.contains(cat.id)) {
                                if expanded.contains(cat.id) { expanded.remove(cat.id) } else { expanded.insert(cat.id) }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            Divider()
            footer
        }
        .onAppear { if !state.cleanupAnalyzed { state.analyzeCleanup() } }
    }

    private var header: some View {
        let safe = state.cleanup.filter { $0.risk == .safe }.reduce(Int64(0)) { $0 + $1.total }
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fmt(state.cleanupTotal))
                    .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                Text("temizlenebilir alan bulundu · \(fmt(safe)) kadarı güvenle silinebilir")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.cleanupAnalyzing { ProgressView().controlSize(.small) }
            Button("Güvenli Olanları Seç") {
                for c in state.cleanup where c.risk == .safe {
                    state.cleanupSelection.formUnion(c.items.map(\.path))
                }
            }
            Button { state.analyzeCleanup() } label: { Label("Yeniden Analiz Et", systemImage: "arrow.clockwise") }
                .disabled(state.cleanupAnalyzing)
        }
        .padding(16)
    }

    private var footer: some View {
        let items = selectedItems
        let size = items.reduce(Int64(0)) { $0 + $1.size }
        return HStack(spacing: 12) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text("Öğeler önce Çöp Kutusu'na taşınır; alan, çöp boşaltılınca açılır.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button {
                state.confirmEmptyTrash = true
            } label: {
                if state.emptyingTrash {
                    ProgressView().controlSize(.small)
                } else if let t = state.trashSize, t > 0 {
                    Label("Çöp Kutusunu Boşalt (\(fmt(t)))", systemImage: "trash.slash")
                } else {
                    Label("Çöp Kutusunu Boşalt", systemImage: "trash.slash")
                }
            }
            .disabled(state.emptyingTrash)
            Button {
                state.requestTrash(items: items)
            } label: {
                Label(items.isEmpty ? "Seçilenleri Çöpe Taşı" : "\(items.count) Öğeyi Çöpe Taşı (\(fmt(size)))", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(items.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }
}

struct RiskBadge: View {
    let risk: Risk
    var body: some View {
        let color: Color = risk == .safe ? .green : .orange
        Text(risk.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct CategoryCard: View {
    let category: CleanupCategory
    let expanded: Bool
    let toggle: () -> Void
    @EnvironmentObject var state: AppState
    @State private var showAll = false

    private var selectedCount: Int { category.items.filter { state.cleanupSelection.contains($0.path) }.count }

    var body: some View {
        let allSelected = selectedCount == category.items.count
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { allSelected },
                    set: { on in
                        let paths = category.items.map(\.path)
                        if on { state.cleanupSelection.formUnion(paths) } else { state.cleanupSelection.subtract(paths) }
                    }))
                    .toggleStyle(.checkbox).labelsHidden()
                Image(systemName: category.icon)
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(category.risk == .safe ? Color.green : Color.orange)
                    .background((category.risk == .safe ? Color.green : Color.orange).opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(category.title).font(.headline)
                        RiskBadge(risk: category.risk)
                        if selectedCount > 0 && !allSelected {
                            Text("\(selectedCount)/\(category.items.count) seçili").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(category.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(fmt(category.total)).font(.title3.weight(.semibold)).monospacedDigit()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { toggle() } }

            if expanded {
                Divider().padding(.leading, 12)
                let items = showAll ? category.items : Array(category.items.prefix(12))
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        ItemRow(item: item, maxSize: category.items.first?.size ?? 1)
                    }
                    if category.items.count > 12 && !showAll {
                        Button("Tümünü göster (\(category.items.count - 12) öğe daha)") { showAll = true }
                            .buttonStyle(.link).padding(8)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }
}

struct ItemRow: View {
    let item: CleanupItem
    let maxSize: Int64
    @EnvironmentObject var state: AppState
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { state.cleanupSelection.contains(item.path) },
                set: { on in if on { state.cleanupSelection.insert(item.path) } else { state.cleanupSelection.remove(item.path) } }))
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                if let note = item.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if hover {
                Button { revealInFinder(item.path) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless).help("Finder'da göster")
            }
            Capsule().fill(.tertiary)
                .frame(width: max(2, 80 * Double(item.size) / Double(max(1, maxSize))), height: 4)
                .frame(width: 80, alignment: .trailing)
            Text(fmt(item.size)).monospacedDigit().foregroundStyle(.secondary).frame(width: 84, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(hover ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu {
            Button("Finder'da Göster") { revealInFinder(item.path) }
            Button("Çöp Kutusuna Taşı…", role: .destructive) { state.requestTrash(items: [item]) }
        }
    }
}
