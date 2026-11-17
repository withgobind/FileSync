import Foundation

/// Turns a comparison into the list of actions a sync would take. Pure: touches nothing on disk.
enum Planner {
    static func plan(_ result: CompareResult, removeExtras: Bool) -> SyncPlan {
        var copies: [SyncAction] = []
        var replacements: [SyncAction] = []
        var trashes: [SyncAction] = []
        for item in result.items {
            switch item.kind {
            case .onlyInSource:
                copies.append(.copy(relativePath: item.relativePath, bytes: item.size))
            case .changed:
                replacements.append(.replace(relativePath: item.relativePath, bytes: item.size))
            case .onlyInTarget:
                if removeExtras {
                    trashes.append(.trash(relativePath: item.relativePath, bytes: item.size))
                }
            }
        }
        return SyncPlan(actions: copies + replacements + trashes)
    }
}
