import SwiftUI

struct BottomBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 16) {
            Toggle("Remove extras", isOn: $model.removeExtras)
                .help("Files that exist only in the target go to the Trash. Off by default.")
                .disabled(model.isBusy)
            Toggle("Compare contents", isOn: $model.options.compareContents)
                .help("Also read files whose size and date match. Slower, catches silent edits.")
                .disabled(model.isBusy)
                .onChange(of: model.options.compareContents) { if model.result != nil { model.compare() } }

            Spacer()

            if let result = model.result, !model.isComparing {
                Text(result.identicalCount.formatted() + " identical")
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            }

            Button(model.selectedJobID == nil ? "Automate…" : "Edit Schedule…") { model.showAutomateSheet = true }
                .disabled(model.source == nil || model.target == nil || model.isBusy)
                .help("Save this pair to sync when the drives connect or on a schedule")
            Button("Compare") { model.compare() }
                .disabled(!model.canCompare)
            Button("Sync…") { model.showSyncSheet = true }
                .buttonStyle(.primary)
                .disabled(!model.canSync)
        }
        .toggleStyle(.checkbox)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.card.opacity(0.6))
    }
}
