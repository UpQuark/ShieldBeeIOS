//
//  ShieldBugApp.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import SwiftUI
import BackgroundTasks

@main
struct ShieldBugApp: App {
    @ObservedObject private var store = ShieldBeeStore.shared
    @Environment(\.scenePhase) private var scenePhase

    private static let bgTaskID = "shieldbug.ShieldBug.scheduleEvaluation"

    init() {
        // Ensure VPNManager is alive from the start so it can observe
        // blockListDidChange before the first tab is rendered.
        _ = VPNManager.shared

        // Register background schedule evaluation. Must be called before the
        // app finishes launching (i.e. here in init, not in body).
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            task.expirationHandler = { task.setTaskCompleted(success: false) }
            Task { @MainActor in
                Self.rescheduleBackgroundTask()
                ScheduleManager.shared.evaluate()
                task.setTaskCompleted(success: true)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.sbOrange)
                .preferredColorScheme(colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:     ScheduleManager.shared.evaluate()
            case .background: Task { @MainActor in Self.rescheduleBackgroundTask() }
            default:          break
            }
        }
    }

    /// Submits a BGAppRefreshTaskRequest timed to fire at the next schedule event.
    /// If no schedules are active, does nothing (no point waking the app).
    @MainActor
    static func rescheduleBackgroundTask() {
        let enabled = ShieldBeeStore.shared.schedules.filter { $0.isEnabled && !$0.activeDays.isEmpty }
        guard !enabled.isEmpty else { return }

        let req = BGAppRefreshTaskRequest(identifier: bgTaskID)
        req.earliestBeginDate = ScheduleManager.shared.nextEvent(schedules: enabled)?.date
            ?? Date(timeIntervalSinceNow: 15 * 60)  // fallback: try again in 15 min
        try? BGTaskScheduler.shared.submit(req)
    }

    private var colorScheme: ColorScheme? {
        switch store.preferences.theme {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}
