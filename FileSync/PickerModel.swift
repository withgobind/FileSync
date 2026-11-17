import AppKit

/// State for the in-app folder picker: mounted drives, common places, and a one-level folder browser.
@MainActor
@Observable
final class PickerModel {
    struct Place: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let name: String
        let detail: String?
        let isDrive: Bool
    }

    struct Folder: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let name: String
    }

    let side: Side
    private(set) var drives: [Place] = []
    let places: [Place]
    private(set) var current: URL
    private(set) var folders: [Folder] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    var selection: URL?
    private var loadTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(side: Side, start: URL?) {
        self.side = side
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var p: [Place] = [Place(url: home, name: NSUserName(), detail: nil, isDrive: false)]
        for (dir, _) in [(FileManager.SearchPathDirectory.desktopDirectory, 0), (.documentDirectory, 0), (.downloadsDirectory, 0),
                         (.picturesDirectory, 0), (.moviesDirectory, 0), (.musicDirectory, 0)] {
            if let u = fm.urls(for: dir, in: .userDomainMask).first, fm.fileExists(atPath: u.path) {
                p.append(Place(url: u, name: fm.displayName(atPath: u.path), detail: nil, isDrive: false))
            }
        }
        places = p
        current = start ?? URL(fileURLWithPath: "/Volumes")
        reloadDrives()
        if start == nil, let first = drives.first(where: { $0.url.path != "/" }) ?? drives.first {
            current = first.url
        }
        open(current)
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadDrives() }
            })
        }
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        loadTask?.cancel()
    }

    /// The folder that "Use" will pick: the highlighted subfolder, else the folder being viewed.
    var chosen: URL { selection ?? current }
    var chosenName: String { FileManager.default.displayName(atPath: chosen.path) }

    /// Path components from the drive root down to the current folder, for the breadcrumb.
    var breadcrumb: [Folder] {
        var parts: [Folder] = []
        var u = current.standardizedFileURL
        let root = volumeRoot(of: u)
        while true {
            parts.insert(Folder(url: u, name: FileManager.default.displayName(atPath: u.path)), at: 0)
            if u.path == root.path || u.path == "/" || u.path == "/System/Volumes/Data" { break }
            u = u.deletingLastPathComponent()
        }
        if parts.count > 5 {
            parts = [parts[0], Folder(url: parts[parts.count - 4].url, name: "…")] + parts.suffix(3)
        }
        return parts
    }

    func open(_ url: URL) {
        current = url.standardizedFileURL
        selection = nil
        loadError = nil
        isLoading = true
        loadTask?.cancel()
        let url = current
        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[Folder], Error> in
                do {
                    let items = try FileManager.default.contentsOfDirectory(
                        at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                        options: [.skipsHiddenFiles])
                    let dirs = items.compactMap { u -> Folder? in
                        let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                        guard v?.isDirectory == true, v?.isPackage != true else { return nil }
                        return Folder(url: u, name: FileManager.default.displayName(atPath: u.path))
                    }
                    return .success(dirs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                } catch {
                    return .failure(error)
                }
            }.value
            guard !Task.isCancelled, url == self.current else { return }
            switch result {
            case .success(let f): self.folders = f
            case .failure: self.folders = []; self.loadError = "Can't open this folder. macOS may need permission: System Settings › Privacy & Security › Files and Folders."
            }
            self.isLoading = false
        }
    }

    func goUp() {
        guard canGoUp else { return }
        open(current.deletingLastPathComponent())
    }

    var canGoUp: Bool {
        current.path != "/" && current.path != volumeRoot(of: current).path
    }

    func isCurrentDrive(_ place: Place) -> Bool {
        place.isDrive ? volumeRoot(of: current).path == place.url.path : current.path == place.url.path
    }

    func reloadDrives() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        drives = urls.compactMap { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            guard v?.volumeIsBrowsable != false else { return nil }
            var detail: String?
            // External drives often report 0 for "important usage"; fall back to plain free space.
            let important = v?.volumeAvailableCapacityForImportantUsage ?? 0
            let free = important > 0 ? important : Int64(v?.volumeAvailableCapacity ?? 0)
            if let total = v?.volumeTotalCapacity {
                detail = "\(Format.bytes(free)) free of \(Format.bytes(Int64(total)))"
            }
            return Place(url: u, name: v?.volumeName ?? u.lastPathComponent, detail: detail, isDrive: true)
        }
    }

    private func volumeRoot(of url: URL) -> URL {
        let root = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume ?? URL(fileURLWithPath: "/")
        // The startup disk's data volume shows as Macintosh HD.
        return root.path == "/System/Volumes/Data" ? URL(fileURLWithPath: "/") : root
    }
}
extension PickerModel: Identifiable {}
