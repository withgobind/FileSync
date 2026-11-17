import SwiftUI

/// Left column: start a new comparison, or pick a saved sync to see its status and run it.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(JobStore.self) private var store
    @Environment(Scheduler.self) private var scheduler

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.newComparison() } label: {
                Label("New comparison", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(model.selectedJobID == nil ? Theme.accent.opacity(0.55) : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .padding(10)

            Text("SAVED SYNCS")
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 4) {
                    if store.jobs.isEmpty {
                        Text("Pick two folders, then press Automate to save them here. Saved syncs run when their drives connect or on a schedule.")
                            .font(.callout)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10)
                            .padding(.top, 4)
                    }
                    ForEach(store.jobs) { job in
                        JobRow(job: job, selected: model.selectedJobID == job.id)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card.opacity(0.55))
    }
}

private struct JobRow: View {
    let job: SyncJob
    let selected: Bool
    @Environment(AppModel.self) private var model
    @Environment(Scheduler.self) private var scheduler

    var body: some View {
        let up = scheduler.connected[job.id] ?? scheduler.available(job)
        let waiting = scheduler.pending[job.id] != nil
        Button { Services.shared.open(jobID: job.id, review: false) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(job.name).fontWeight(.medium).lineLimit(1)
                    Spacer(minLength: 4)
                    if scheduler.running == job.id {
                        ProgressView().controlSize(.mini)
                    } else if waiting {
                        Pill(text: "Review", fill: Theme.pastel(.onlyInTarget), ink: Theme.onPastel(.onlyInTarget))
                    } else if !job.isEnabled {
                        Pill(text: "Paused", fill: Theme.stroke, ink: Theme.muted)
                    }
                }
                Text("\(name(job.sourcePath)) → \(name(job.targetPath))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(up ? Theme.pastel(.onlyInSource) : Theme.stroke)
                        .overlay(Circle().strokeBorder(up ? Theme.color(.onlyInSource).opacity(0.6) : Theme.muted.opacity(0.4)))
                        .frame(width: 8, height: 8)
                    Text(up ? "Connected" : "Not connected")
                    Text("·")
                    Text(triggerText)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                if let summary = job.lastSummary {
                    Text(summary).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.accent.opacity(0.55) : Theme.card.opacity(0.0001)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .contextMenu {
            Button("Sync Now") { scheduler.runNow(job.id) }.disabled(!up || scheduler.running != nil)
            if waiting { Button("Review Changes…") { Services.shared.open(jobID: job.id, review: true) } }
            Button("Edit…") { Services.shared.open(jobID: job.id, review: false); model.showAutomateSheet = true }
        }
    }

    private var triggerText: String {
        var parts: [String] = []
        if job.runOnConnect { parts.append("On connect") }
        if job.schedule != .off { parts.append(ScheduleMath.describe(job.schedule)) }
        return parts.isEmpty ? "Manual" : parts.joined(separator: " + ")
    }

    private func name(_ path: String) -> String { (path as NSString).lastPathComponent }
}

struct Pill: View {
    let text: String
    let fill: Color
    let ink: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(fill))
    }
}
