import SwiftUI

struct DiffListView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<DiffItem.ID>()

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Filter.allCases, id: \.self) { f in
                    FilterChip(filter: f, count: model.count(f), selected: model.filter == f) {
                        model.filter = f
                    }
                }
                Spacer()
                TextField("Filter by name", text: $model.search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Table(model.visibleItems, selection: $selection) {
                TableColumn("Name") { item in NameCell(item: item) }
                    .width(min: 200, ideal: 320)
                TableColumn("On sync") { item in ActionCell(item: item, removeExtras: model.removeExtras) }
                    .width(min: 120, ideal: 150)
                TableColumn("Size") { item in
                    Text(sizeText(item))
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
                .width(min: 70, ideal: 90)
                TableColumn("Modified") { item in DatesCell(item: item) }
                    .width(min: 140, ideal: 170)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: DiffItem.ID.self) { ids in
                if let id = ids.first, let item = model.result?.items.first(where: { $0.id == id }) {
                    if item.source != nil, let url = model.source?.url.appending(path: item.relativePath) {
                        Button("Show Master Copy in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    if item.target != nil, let url = model.target?.url.appending(path: item.relativePath) {
                        Button("Show Target Copy in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                }
            }
            .overlay {
                if model.visibleItems.isEmpty {
                    Text(model.search.isEmpty ? "Nothing here" : "No matches")
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func sizeText(_ item: DiffItem) -> String {
        if item.kind == .changed, let s = item.source?.size, let t = item.target?.size, s != t {
            return Format.bytes(s)
        }
        return Format.bytes(item.size)
    }
}

private struct FilterChip: View {
    let filter: Filter
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let kind = filter.kind {
                    Circle().fill(Theme.pastel(kind)).overlay(Circle().strokeBorder(Theme.color(kind).opacity(0.5))).frame(width: 9, height: 9)
                }
                Text(filter.title)
                Text(count.formatted())
                    .monospacedDigit()
                    .foregroundStyle(selected ? Theme.ink : Theme.muted)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(selected ? Theme.card : .clear)
            )
            .overlay(Capsule().strokeBorder(selected ? Theme.stroke : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(count == 0 && filter != .all ? 0.45 : 1)
        .disabled(count == 0 && filter != .all)
    }
}

private struct NameCell: View {
    let item: DiffItem

    var body: some View {
        HStack(spacing: 8) {
            KindBadge(kind: item.kind)
            Image(nsImage: FinderIcon.forItem(name: item.name, isDirectory: item.isDirectory))
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name).lineLimit(1)
                    if item.isDirectory {
                        Text(Format.count(item.fileCount, "file"))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                if !item.parentPath.isEmpty {
                    Text(item.parentPath)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .help(item.relativePath)
    }
}

private struct ActionCell: View {
    let item: DiffItem
    let removeExtras: Bool

    var body: some View {
        switch item.kind {
        case .onlyInSource:
            Label("Copy to target", systemImage: "arrow.right")
        case .changed:
            VStack(alignment: .leading, spacing: 1) {
                Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                if item.newerSide == .target {
                    Text("Target copy is newer")
                        .font(.caption)
                        .foregroundStyle(Theme.color(.onlyInTarget))
                }
            }
        case .onlyInTarget:
            if removeExtras {
                Label("Move to Trash", systemImage: "trash")
                    .foregroundStyle(Theme.color(.onlyInTarget))
            } else {
                Label("Keep", systemImage: "hand.raised")
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

private struct DatesCell: View {
    let item: DiffItem

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let s = item.source {
                Text(Format.date(s.modified))
                    .fontWeight(item.newerSide == .source ? .medium : .regular)
            }
            if item.kind == .changed, let t = item.target {
                Text("target " + Format.date(t.modified))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            } else if item.source == nil, let t = item.target {
                Text(Format.date(t.modified))
            }
        }
        .monospacedDigit()
    }
}
