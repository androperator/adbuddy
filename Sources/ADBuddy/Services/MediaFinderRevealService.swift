import AppKit
import Foundation

@MainActor
protocol MediaFinderRevealing {
    func revealMedia(at fileURL: URL)
}

@MainActor
struct MediaFinderRevealService: MediaFinderRevealing {
    func revealMedia(at fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
