import SwiftUI

/// Save the current master → target pair as a sync that runs on its own.
struct AutomateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(JobStore.self) private var store
    @Environment(Scheduler.self) private var scheduler
    @Environment(Permissions.self) private var permissions

    @State private var job = SyncJob(name: "", sourcePath: "", targetPath: "")
    @State private var isNew = true
    @State private var kind: Kind = .off
    @State private var hours = 6
    @State private var time = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var weekday = Calendar.current.component(.weekday, from: Date())
    @State private var confirmDelete = false

    enum Kind: String, CaseIterable, Identifiable {
        case off = "No schedule", hours = "Every few hours", daily = "Daily", weekly = "Weekly"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isNew ? "Automate this sync" : "Edit saved sync")
                    .font(.title2.weight(.semibold))
                Text("\(name(job.sourcePath)) → \(name(job.targetPath))")
                    .foregroundStyle(Theme.muted)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group("Name") {
                        TextField("Name", text: $job.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    group("When it runs") {
                        Toggle("As soon as both drives are connected", isOn: $job.runOnConnect)
                        HStack(spacing: 10) {
                            Picker("Schedule", selection: $kind) {
                                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            switch kind {
                            case .off:
                                EmptyView()
                            case .hours:
                                Stepper(hours == 1 ? "every hour" : "every \(hours) hours", value: $hours, in: 1...24)
                            case .daily:
                                Text("at")
                                DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                            case .weekly:
                                Text("on")
                                Picker("Day", selection: $weekday) {
                                    ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                                }
                                .labelsHidden().fixedSize()
                                Text("at")
                                DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                            }
                        }
                        Text("A schedule runs only while both drives are connected. A missed time runs once when they come back.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }

                    group("Then") {
                        Picker("", selection: $job.action) {
                            Text("Ask me first: notify me, nothing changes until I review").tag(AutoAction.askFirst)
                            Text("Sync automatically, then tell me what changed").tag(AutoAction.syncAutomatically)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        Toggle("Remove extras from the target (moved to the Trash)", isOn: $job.removeExtras)
                        if job.removeExtras && job.action == .syncAutomatically {
                            Label("Files that exist only in the target will go to the Trash without asking.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.color(.onlyInTarget))
                        }
                        Toggle("Compare file contents (slower)", isOn: $job.compareContents)
                    }

                    group("Permissions") {
                        PermissionRow(title: "Notifications", detail: "To tell you when changes are ready or a sync finished.",
                                      state: permissions.notifications, action: permissions.notifications == .denied ? "Open Settings" : "Allow") {
                            Task { await permissions.requestNotifications() }
                        }
                        PermissionRow(title: "Open at login", detail: "So File Sync is running when you plug a drive in.",
                                      state: permissions.openAtLogin, action: permissions.openAtLogin == .denied ? "Open Settings" : "Turn On") {
                            Task { await permissions.enableOpenAtLogin() }
                        }
                        PermissionRow(title: "Drive access", detail: "macOS may ask to allow access to files on removable volumes.",
                                      state: permissions.driveAccess[job.id] ?? .needed,
                                      action: permissions.driveAccess[job.id] == .denied ? "Open Settings" : "Check") {
                            if permissions.driveAccess[job.id] == .denied { permissions.openFilesAndFoldersSettings() }
                            else { permissions.checkDriveAccess(for: job) }
                        }
                    }
                }
                .padding(.trailing, 6)
            }

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                    Toggle("Paused", isOn: Binding(get: { !job.isEnabled }, set: { job.isEnabled = !$0 }))
                        .toggleStyle(.checkbox)
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.showAutomateSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Save Sync" : "Save Changes") { save() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(job.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 580, height: 740)
        .background(Theme.canvas)
        .confirmationDialog("Delete “\(job.name)”?", isPresented: $confirmDelete) {
            Button("Delete Saved Sync", role: .destructive) {
                store.delete(id: job.id)
                scheduler.clearPending(job.id)
                model.selectedJobID = nil
                model.showAutomateSheet = false
            }
        } message: {
            Text("Only the saved settings are removed. No files are touched.")
        }
        .task {
            load()
            await permissions.refresh()
            permissions.checkDriveAccess(for: job)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
        }
    }

    private func load() {
        if let id = model.selectedJobID, let existing = store.job(id: id) {
            job = existing
            isNew = false
        } else if let s = model.source, let t = model.target {
            job = SyncJob(name: "\(s.name) → \(t.name)", sourcePath: s.url.path, targetPath: t.url.path,
                          sourceBookmark: JobStore.bookmark(for: s.url), targetBookmark: JobStore.bookmark(for: t.url),
                          removeExtras: model.removeExtras, compareContents: model.options.compareContents)
            isNew = true
        }
        let cal = Calendar.current
        switch job.schedule {
        case .off: kind = .off
        case .everyHours(let h): kind = .hours; hours = h
        case .daily(let h, let m):
            kind = .daily; time = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? time
        case .weekly(let d, let h, let m):
            kind = .weekly; weekday = d; time = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? time
        }
    }

    private func save() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let h = c.hour ?? 21, m = c.minute ?? 0
        switch kind {
        case .off: job.schedule = .off
        case .hours: job.schedule = .everyHours(hours)
        case .daily: job.schedule = .daily(hour: h, minute: m)
        case .weekly: job.schedule = .weekly(weekday: weekday, hour: h, minute: m)
        }
        job.name = job.name.trimmingCharacters(in: .whitespaces)
        if isNew { job.lastRun = Date() }   // the pair was just reviewed by hand; don't fire immediately
        store.upsert(job)
        model.selectedJobID = job.id
        model.showAutomateSheet = false
        scheduler.check()
    }

    private func name(_ path: String) -> String { (path as NSString).lastPathComponent }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let state: Permissions.State
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.isGranted ? "checkmark" : (state == .denied ? "exclamationmark" : "circle.dotted"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(state.isGranted ? Theme.onPastel(.onlyInSource) : Theme.onPastel(.onlyInTarget))
                .frame(width: 20, height: 20)
                .background(Circle().fill(state.isGranted ? Theme.pastel(.onlyInSource) : Theme.pastel(.onlyInTarget)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            if state.isGranted {
                Text("Allowed").font(.callout).foregroundStyle(Theme.color(.onlyInSource))
            } else {
                Button(action, action: perform)
            }
        }
    }
}
