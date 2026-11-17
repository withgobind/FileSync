import SwiftUI

/// The dry run: shows exactly what will happen, then runs it only when confirmed.
struct SyncSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.syncStage {
            case .preview: preview
            case .running: running
            case .done: done
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Theme.canvas)
        .interactiveDismissDisabled(model.syncStage == .running)
    }

    // MARK: Preview

    @ViewBuilder private var preview: some View {
        if let plan = model.plan, let source = model.source, let target = model.target {
            Text("Review sync")
                .font(.title2.weight(.semibold))
            HStack(spacing: 6) {
                Text(source.name).fontWeight(.medium)
                Image(systemName: "arrow.right").foregroundStyle(Theme.muted)
                Text(target.name).fontWeight(.medium)
            }
            .font(.callout)

            VStack(spacing: 0) {
                row(.onlyInSource, "Copy", plan.copies)
                Divider().overlay(Theme.stroke)
                row(.changed, "Replace", plan.replacements)
                Divider().overlay(Theme.stroke)
                row(.onlyInTarget, "Move to Trash", plan.trashes)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))

            if !plan.trashes.isEmpty {
                trashWarning(plan.trashes)
            } else if model.count(.onlyInTarget) > 0 {
                note("\(Format.count(model.count(.onlyInTarget), "item")) only in the target will be kept.")
            }
            if let free = target.freeBytes, plan.bytesToWrite > free {
                note("The target drive has \(Format.bytes(free)) free; this sync writes up to \(Format.bytes(plan.bytesToWrite)).", warning: true)
            }
            if plan.replacements.contains(where: { a in model.result?.items.first { $0.relativePath == a.relativePath }?.newerSide == .target }) {
                note("Some target copies are newer than the master's and will be replaced.", warning: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.closeSyncSheet() }
                    .keyboardShortcut(.cancelAction)
                Button(plan.trashes.isEmpty ? "Sync" : "Sync and Move to Trash") { model.startSync() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(plan.trashes.isEmpty ? PrimaryButtonStyle() : PrimaryButtonStyle(tint: Theme.pastel(.onlyInTarget), ink: Theme.onPastel(.onlyInTarget)))
            }
            .controlSize(.large)
        }
    }

    private func row(_ kind: DiffKind, _ label: String, _ actions: [SyncAction]) -> some View {
        HStack {
            KindBadge(kind: kind, size: 22)
            Text(label)
            Spacer()
            Text(Format.count(actions.count, "item"))
                .monospacedDigit()
            Text(actions.isEmpty ? "–" : Format.bytes(actions.reduce(0) { $0 + $1.bytes }))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(actions.isEmpty ? 0.45 : 1)
    }

    private func trashWarning(_ trashes: [SyncAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("These will be moved from the target to the Trash:", systemImage: "trash")
                .foregroundStyle(Theme.color(.onlyInTarget))
                .font(.callout.weight(.medium))
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(trashes, id: \.self) { a in
                        Text(a.relativePath)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.pastel(.onlyInTarget).opacity(0.55)))
    }

    private func note(_ text: String, warning: Bool = false) -> some View {
        Label(text, systemImage: warning ? "exclamationmark.triangle.fill" : "info.circle")
            .font(.callout)
            .foregroundStyle(warning ? Theme.color(.onlyInTarget) : Theme.muted)
    }

    // MARK: Running

    @ViewBuilder private var running: some View {
        Text("Syncing…")
            .font(.title2.weight(.semibold))
        if let p = model.syncProgress {
            ProgressView(value: p.fraction)
            HStack {
                Text("\(p.actionsDone.formatted()) of \(Format.count(p.actionsTotal, "item"))")
                Spacer()
                Text("\(Format.bytes(p.bytesDone)) of \(Format.bytes(p.bytesTotal))")
            }
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(Theme.muted)
            Text(p.currentPath.isEmpty ? " " : p.currentPath)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        HStack {
            Spacer()
            Button("Stop") { model.cancelSync() }
                .controlSize(.large)
        }
    }

    // MARK: Done

    @ViewBuilder private var done: some View {
        if let r = model.syncReport {
            HStack(spacing: 10) {
                Image(systemName: r.failures.isEmpty && !r.cancelled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(r.failures.isEmpty && !r.cancelled ? Theme.color(.onlyInSource) : Theme.color(.onlyInTarget))
                Text(r.cancelled ? "Sync stopped" : r.failures.isEmpty ? "Sync complete" : "Sync finished with problems")
                    .font(.title2.weight(.semibold))
            }
            Text("Copied \(r.copied.formatted()), replaced \(r.replaced.formatted()), moved \(r.trashed.formatted()) to Trash · \(Format.bytes(r.bytesWritten)) written")
                .foregroundStyle(Theme.muted)
            if !r.failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(r.failures, id: \.self) { f in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.relativePath).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                                Text(f.message).font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
            HStack {
                Spacer()
                Button("Done") { model.closeSyncSheet() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primary)
                    .controlSize(.large)
            }
        }
    }
}
