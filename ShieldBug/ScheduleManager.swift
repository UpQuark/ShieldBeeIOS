//
//  ScheduleManager.swift
//  ShieldBug
//
//  Evaluates block schedules and drives the VPN on/off accordingly.
//  Called on app foreground and at app launch.
//

import Foundation

struct ScheduleEvent {
    enum Kind { case start, end }
    let kind: Kind
    let date: Date
}

@MainActor
class ScheduleManager {
    static let shared = ScheduleManager()

    private init() {}

    // MARK: - Schedule evaluation

    /// Returns true if the current time falls inside any enabled schedule entry.
    func isActive(schedules: [BlockSchedule]) -> Bool {
        let cal = Calendar.current
        let now = Date()
        let weekday  = cal.component(.weekday, from: now)
        let nowMins  = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        return schedules.contains { s in
            guard s.isEnabled, s.activeDays.contains(weekday) else { return false }
            let start = s.startHour * 60 + s.startMinute
            let end   = s.endHour   * 60 + s.endMinute
            if start <= end {
                return nowMins >= start && nowMins < end
            } else {
                // Overnight schedule (e.g. 22:00 – 06:00)
                return nowMins >= start || nowMins < end
            }
        }
    }

    /// Returns the next schedule event (start or end) within the next 8 days.
    func nextEvent(schedules: [BlockSchedule]) -> ScheduleEvent? {
        let cal = Calendar.current
        let now = Date()
        let enabled = schedules.filter { $0.isEnabled && !$0.activeDays.isEmpty }
        guard !enabled.isEmpty else { return nil }

        let currentlyActive = isActive(schedules: enabled)
        var candidates: [ScheduleEvent] = []

        for schedule in enabled {
            for dayOffset in 0...7 {
                guard let dayDate = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                let weekday = cal.component(.weekday, from: dayDate)
                guard schedule.activeDays.contains(weekday) else { continue }

                if currentlyActive {
                    if let endDate = cal.date(bySettingHour: schedule.endHour,
                                              minute: schedule.endMinute,
                                              second: 0, of: dayDate),
                       endDate > now {
                        candidates.append(ScheduleEvent(kind: .end, date: endDate))
                    }
                } else {
                    if let startDate = cal.date(bySettingHour: schedule.startHour,
                                                minute: schedule.startMinute,
                                                second: 0, of: dayDate),
                       startDate > now {
                        candidates.append(ScheduleEvent(kind: .start, date: startDate))
                    }
                }
            }
        }

        return candidates.min(by: { $0.date < $1.date })
    }

    /// Human-readable label for the next event (e.g. "Starts today at 9:00 AM").
    func nextEventText(schedules: [BlockSchedule]) -> String? {
        guard let event = nextEvent(schedules: schedules) else { return nil }

        let cal = Calendar.current
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"

        let action = event.kind == .start ? "Starts" : "Ends"
        let timeStr = timeFmt.string(from: event.date)

        if cal.isDateInToday(event.date) {
            return "\(action) today at \(timeStr)"
        } else if cal.isDateInTomorrow(event.date) {
            return "\(action) tomorrow at \(timeStr)"
        } else {
            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "EEEE"
            return "\(action) \(dayFmt.string(from: event.date)) at \(timeStr)"
        }
    }

    // MARK: - VPN control

    /// Checks whether the current time is within a schedule and
    /// connects/disconnects the VPN accordingly.
    /// Only acts when at least one schedule is enabled — otherwise the
    /// manual toggle in the Setup tab remains in full control.
    func evaluate() {
        let enabled = ShieldBeeStore.shared.schedules.filter { $0.isEnabled && !$0.activeDays.isEmpty }
        guard !enabled.isEmpty else { return }

        if isActive(schedules: enabled) {
            if !VPNManager.shared.isConnected { VPNManager.shared.connect() }
        } else {
            if VPNManager.shared.isConnected { VPNManager.shared.disconnect() }
        }
    }
}
