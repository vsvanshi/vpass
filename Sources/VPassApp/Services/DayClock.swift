import AppKit
import Combine
import Foundation

/// Publishes the current calendar day so views that render day-based text
/// ("Expires in 7d") re-evaluate when the day rolls over. SwiftUI cannot see a
/// bare `Date()` read inside a view body, so a long-running window keeps
/// showing whatever day it was launched on until something else invalidates it.
@MainActor
final class DayClock: ObservableObject {
    static let shared = DayClock()

    @Published private(set) var today: Date

    private var midnightTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init(calendar: Calendar = .current) {
        today = calendar.startOfDay(for: Date())

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        )
        // NSCalendarDayChanged does not fire while the machine is asleep, so
        // also re-check whenever the app comes back to the foreground.
        observers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        )

        scheduleMidnightTick()
    }

    // No deinit: this is a process-lifetime singleton, and a nonisolated
    // deinit cannot touch the main-actor timer/observers anyway.

    private func refresh(calendar: Calendar = .current) {
        let startOfToday = calendar.startOfDay(for: Date())
        if startOfToday != today {
            today = startOfToday
        }
        scheduleMidnightTick(calendar: calendar)
    }

    private func scheduleMidnightTick(calendar: Calendar = .current) {
        midnightTimer?.invalidate()
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: today) else {
            return
        }
        // One second past midnight, so `startOfDay` has definitely advanced.
        let timer = Timer(fireAt: nextMidnight.addingTimeInterval(1), interval: 0, target: self,
                          selector: #selector(midnightFired), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    @objc private func midnightFired() {
        refresh()
    }

    /// Whole days from today to the start of `date`'s day. Negative when past.
    func daysUntil(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
    }
}
