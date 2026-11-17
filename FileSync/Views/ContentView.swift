import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
        SidebarView()
            .frame(width: 260)
        Divider().overlay(Theme.stroke)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                LocationCard(side: .source)
                DirectionButton()
                LocationCard(side: .target)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)

            Divider().overlay(Theme.stroke)

            PendingBanner()

            Group {
                if model.isComparing {
                    ComparingView()
                } else if let result = model.result {
                    if result.isInSync {
                        InSyncView(result: result)
                    } else {
                        DiffListView()
                    }
                } else {
                    StartView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(Theme.stroke)
            BottomBar()
        }
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: $model.showSyncSheet) { SyncSheet() }
        .sheet(isPresented: $model.showAutomateSheet) { AutomateSheet() }
        .sheet(item: $model.picker, onDismiss: { model.closePicker() }) { picker in
            LocationPicker(picker: picker)
        }
        .alert("Can't continue", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// The arrow between the cards. Click to swap which side is the master.
private struct DirectionButton: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button { withAnimation(.snappy) { model.swap() } } label: {
            Image(systemName: hovering ? "arrow.left.arrow.right" : "arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.card))
                .overlay(Circle().strokeBorder(Theme.stroke))
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .onHover { hovering = $0 }
        .help("Swap master and target (⇧⌘S)")
        .disabled(model.isBusy)
    }
}

private struct StartView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.muted)
            if model.source == nil || model.target == nil {
                Text("Pick two folders to compare")
                    .font(.title3.weight(.medium))
                Text("Any folder on this Mac or on an external drive. The master's contents win when you sync.")
                    .multilineTextAlignment(.center)
            } else {
                Text("Ready to compare")
                    .font(.title3.weight(.medium))
                Text("Nothing changes until you review the preview and press Sync.")
                Button("Compare Now") { model.compare() }
                    .controlSize(.large)
                    .buttonStyle(.primary)
                    .padding(.top, 6)
            }
        }
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: 380)
    }
}

private struct ComparingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text(model.compareProgress?.phase ?? "Scanning")
                .font(.headline)
            if let n = model.compareProgress?.filesSeen, n > 0 {
                Text(Format.count(n, "file") + " so far")
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            Button("Stop") { model.cancelCompare() }
                .padding(.top, 4)
        }
    }
}

private struct InSyncView: View {
    let result: CompareResult

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.onPastel(.onlyInSource))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.pastel(.onlyInSource)))
                .symbolEffect(.bounce, value: result.identicalCount)
            Text("In sync")
                .font(.title3.weight(.medium))
            Text(Format.count(result.identicalCount, "file") + " match on both sides.")
                .foregroundStyle(Theme.muted)
        }
    }
}

/// Shown when a saved sync found changes on its own and is waiting for a review.
private struct PendingBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(Scheduler.self) private var scheduler

    var body: some View {
        if let id = model.selectedJobID, let pending = scheduler.pending[id], !model.showSyncSheet {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.onPastel(.onlyInTarget))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.pastel(.onlyInTarget)))
                Text("This saved sync found \(Format.count(pending.items.count, "change")) on its own. Nothing has changed yet.")
                Spacer()
                Button("Review Changes…") { Services.shared.open(jobID: id, review: true) }
                    .buttonStyle(.primary(Theme.pastel(.onlyInTarget), ink: Theme.onPastel(.onlyInTarget)))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.pastel(.onlyInTarget).opacity(0.35))
        }
    }
}
