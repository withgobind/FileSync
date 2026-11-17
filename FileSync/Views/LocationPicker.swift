import SwiftUI

/// In-app picker: drives and places on the left, folders on the right, one clear "Use" button.
struct LocationPicker: View {
    @Environment(AppModel.self) private var model
    @Bindable var picker: PickerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 230)
                Divider().overlay(Theme.stroke)
                browser
            }
            Divider().overlay(Theme.stroke)
            footer
        }
        .frame(width: 760, height: 520)
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(picker.side == .source ? "MASTER" : "TARGET")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(picker.side == .source ? Theme.accent.opacity(0.15) : Theme.stroke))
            Text(picker.side == .source ? "Choose what to copy from" : "Choose what to keep in sync")
                .font(.title3.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sectionTitle("Drives")
                ForEach(picker.drives) { drive in
                    placeRow(drive)
                }
                sectionTitle("Places").padding(.top, 10)
                ForEach(picker.places) { place in
                    placeRow(place)
                }
            }
            .padding(10)
        }
        .background(Theme.card.opacity(0.5))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

    private func placeRow(_ place: PickerModel.Place) -> some View {
        let active = picker.isCurrentDrive(place)
        return Button { picker.open(place.url) } label: {
            HStack(spacing: 8) {
                Image(nsImage: FinderIcon.forPath(place.url))
                    .resizable()
                    .frame(width: place.isDrive ? 26 : 20, height: place.isDrive ? 26 : 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(place.name).lineLimit(1)
                    if let d = place.detail {
                        Text(d).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, place.isDrive ? 5 : 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(active ? Theme.accent.opacity(0.14) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(place.url.path(percentEncoded: false))
    }

    // MARK: Browser

    private var browser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { picker.goUp() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .disabled(!picker.canGoUp)
                    .help("Up one folder")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(picker.breadcrumb.enumerated()), id: \.element.id) { i, crumb in
                            if i > 0 {
                                Image(systemName: "chevron.compact.right").foregroundStyle(Theme.muted)
                            }
                            Button(crumb.name) { picker.open(crumb.url) }
                                .buttonStyle(.plain)
                                .fontWeight(i == picker.breadcrumb.count - 1 ? .semibold : .regular)
                                .padding(.horizontal, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Theme.stroke)

            ZStack {
                List(selection: $picker.selection) {
                    ForEach(picker.folders) { folder in
                        HStack(spacing: 8) {
                            Image(nsImage: FinderIcon.forPath(folder.url))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(folder.name).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        .contentShape(Rectangle())
                        .tag(folder.url)
                    }
                }
                .contextMenu(forSelectionType: URL.self) { _ in } primaryAction: { urls in
                    if let u = urls.first { picker.open(u) }
                }
                .scrollContentBackground(.hidden)

                if picker.isLoading && picker.folders.isEmpty {
                    ProgressView()
                } else if let err = picker.loadError {
                    Text(err).multilineTextAlignment(.center).foregroundStyle(Theme.muted).padding(30)
                } else if picker.folders.isEmpty {
                    Text("No folders inside. You can use this one.")
                        .foregroundStyle(Theme.muted)
                }
            }
            Text("Click a folder to select it, double-click to open it.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.vertical, 6)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Use Finder Instead…") { model.chooseWithFinder(picker.side) }
                .buttonStyle(.link)
            Spacer()
            Button("Cancel", role: .cancel) { model.closePicker() }
                .keyboardShortcut(.cancelAction)
            Button {
                model.usePicked()
            } label: {
                Text("Use “\(picker.chosenName)”")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.primary)
            .keyboardShortcut(.defaultAction)
            .disabled(picker.loadError != nil && picker.selection == nil)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
