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

    @State private var showDeepBreath = false
    @State private var showPIN = false
    /// Timestamp of the last time the user successfully passed all guards.
    /// Guards are skipped if the app re-foregrounds within 60 seconds (brief app switch).
    @State private var lastUnlockedAt: Date? = nil

    private static let bgTaskID = "shieldbug.ShieldBug.scheduleEvaluation"

    init() {
        _ = VPNManager.shared

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
                .overlay {
                    if showDeepBreath {
                        DeepBreathOverlay(duration: store.preferences.deepBreathDuration) {
                            showDeepBreath = false
                            if KeychainManager.hasPin {
                                showPIN = true
                            } else {
                                lastUnlockedAt = Date()
                            }
                        }
                        .transition(.opacity)
                    } else if showPIN {
                        PINEntryView(mode: .gate) {
                            showPIN = false
                            lastUnlockedAt = Date()
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: showDeepBreath)
                .animation(.easeInOut(duration: 0.25), value: showPIN)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                ScheduleManager.shared.evaluate()
                triggerGuards()
            case .background:
                Task { @MainActor in Self.rescheduleBackgroundTask() }
            default:
                break
            }
        }
    }

    // MARK: - Guards

    private func triggerGuards() {
        // Skip within 60-second grace window (e.g. brief switch to another app)
        if let last = lastUnlockedAt, Date().timeIntervalSince(last) < 60 { return }

        let breathActive = store.preferences.deepBreathEnabled && store.preferences.deepBreathDuration > 0
        let pinActive    = KeychainManager.hasPin

        guard breathActive || pinActive else { return }

        if breathActive {
            showDeepBreath = true   // PIN follows after Deep Breath completes
        } else {
            showPIN = true
        }
    }

    // MARK: - Background task

    @MainActor
    static func rescheduleBackgroundTask() {
        let enabled = ShieldBeeStore.shared.schedules.filter { $0.isEnabled && !$0.activeDays.isEmpty }
        guard !enabled.isEmpty else { return }
        let req = BGAppRefreshTaskRequest(identifier: bgTaskID)
        req.earliestBeginDate = ScheduleManager.shared.nextEvent(schedules: enabled)?.date
            ?? Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    // MARK: - Theme

    private var colorScheme: ColorScheme? {
        switch store.preferences.theme {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}
