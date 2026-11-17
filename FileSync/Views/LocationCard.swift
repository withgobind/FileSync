import SwiftUI
import UniformTypeIdentifiers

struct LocationCard: View {
    let side: Side
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false

    private var location: Location? { side == .source ? model.source : model.target }
    private var title: String { side == .source ? "MASTER" : "TARGET" }
    private var caption: String { side == .source ? "Copied from" : "Made to match" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                Spacer()
                if location != nil {
                    Button("Change…") { model.choose(side) }
                        .buttonStyle(.link)
                        .font(.caption)
                        .disabled(model.isBusy)
                }
            }

            if let location {
                Button { model.choose(side) } label: { filled(location) }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
            } else {
                Button { model.choose(side) } label: { empty }
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard !model.isBusy, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.set(url, for: side) }
            }
            return true
        }
    }

    private func filled(_ location: Location) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: FinderIcon.forPath(location.url))
                .resizable()
                .interpolation(.high)
                .frame(width: 46, height: 46)
                .overlay(alignment: .bottomTrailing) {
                    if let volume = location.volumeURL {
                        Image(nsImage: FinderIcon.forPath(volume))
                            .resizable()
                            .frame(width: 22, height: 22)
                            .offset(x: 4, y: 3)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(location.url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(location.volumeName)
                    if let free = location.freeBytes {
                        Text("·")
                        Text("\(Format.bytes(free)) free")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(height: 76)
        .background(card)
        .help(location.url.path(percentEncoded: false))
    }

    private var empty: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose a drive or folder")
                    .font(.callout.weight(.medium))
                if let path = model.missing[side] {
                    Text("\((path as NSString).lastPathComponent) isn't connected. Plug in its drive and it comes back.")
                        .font(.caption)
                        .lineLimit(2)
                } else {
                    Text("or drop one here from Finder")
                        .font(.caption)
                }
            }
        }
        .foregroundStyle(dropTargeted ? Theme.accent : Theme.muted)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(dropTargeted ? Theme.accent : Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .contentShape(Rectangle())
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(dropTargeted ? Theme.accent : Theme.stroke, lineWidth: dropTargeted ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }
}
