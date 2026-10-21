import Foundation

/// State shared by the quick search views across openings of the
/// keyboard-shortcut window.
@MainActor
final class QuickSearchContext: ObservableObject {
    static let shared = QuickSearchContext()

    private init() {}

    /// Bumped each time the shortcut opens the search, so the view can reset.
    @Published private(set) var openCount = 0

    /// The login whose password was just copied. For two minutes it stays on
    /// top, so the 2FA step that follows is Shift+Return with no typing.
    @Published private(set) var recentRecordID: UUID?
    private var recentAt = Date.distantPast

    var freshRecentRecordID: UUID? {
        Date().timeIntervalSince(recentAt) < 120 ? recentRecordID : nil
    }

    func didOpen() {
        openCount += 1
    }

    func rememberPasswordCopy(of id: UUID) {
        recentRecordID = id
        recentAt = Date()
    }

    func clearRecent() {
        recentRecordID = nil
    }
}
