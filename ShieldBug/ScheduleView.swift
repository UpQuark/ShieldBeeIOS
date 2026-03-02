//
//  ScheduleView.swift
//  ShieldBug
//
//  Manage time-based blocking schedules.
//

import SwiftUI

struct ScheduleView: View {
    @ObservedObject private var store = ShieldBeeStore.shared
    @State private var showingAddSchedule = false

    var body: some View {
        NavigationView {
            List {
                if store.schedules.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("No schedules")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Tap + to add a time window")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.schedules) { schedule in
                        ScheduleRow(schedule: schedule)
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            store.removeSchedule(id: store.schedules[idx].id)
                        }
                        ScheduleManager.shared.evaluate()
                    }
                }
            }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSchedule = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSchedule) {
                AddScheduleSheet { newSchedule in
                    store.addSchedule(newSchedule)
                    ScheduleManager.shared.evaluate()
                }
            }
        }
    }
}

// MARK: - Schedule Row

struct ScheduleRow: View {
    let schedule: BlockSchedule
    @ObservedObject private var store = ShieldBeeStore.shared

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(timeRangeText)
                    .font(.body)
                    .foregroundColor(schedule.isEnabled ? .primary : .secondary)
                DayPills(activeDays: schedule.activeDays)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { enabled in
                    var s = schedule
                    s.isEnabled = enabled
                    store.updateSchedule(s)
                    ScheduleManager.shared.evaluate()
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var timeRangeText: String {
        "\(formatTime(schedule.startHour, schedule.startMinute)) – \(formatTime(schedule.endHour, schedule.endMinute))"
    }
}

// MARK: - Day Pills

struct DayPills: View {
    let activeDays: Set<Int>
    private let labels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { day in
                let active = activeDays.contains(day)
                Text(labels[day - 1])
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .frame(width: 20, height: 20)
                    .background(active ? Color.sbOrange : Color(.systemGray5))
                    .foregroundColor(active ? .white : Color(.tertiaryLabel))
                    .clipShape(Circle())
            }
        }
    }
}

// MARK: - Add Schedule Sheet

struct AddScheduleSheet: View {
    @Environment(\.dismiss) var dismiss
    let onSave: (BlockSchedule) -> Void

    @State private var startDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endDate   = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var selectedDays: Set<Int> = [2, 3, 4, 5, 6] // Mon–Fri

    var body: some View {
        NavigationView {
            Form {
                Section("Time Range") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .hourAndMinute)
                    DatePicker("End",   selection: $endDate,   displayedComponents: .hourAndMinute)
                }
                Section("Days") {
                    DaySelector(selectedDays: $selectedDays)
                        .padding(.vertical, 4)
                }
            }
            .navigationTitle("New Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let cal = Calendar.current
                        var s = BlockSchedule()
                        s.startHour   = cal.component(.hour,   from: startDate)
                        s.startMinute = cal.component(.minute, from: startDate)
                        s.endHour     = cal.component(.hour,   from: endDate)
                        s.endMinute   = cal.component(.minute, from: endDate)
                        s.activeDays  = selectedDays
                        onSave(s)
                        dismiss()
                    }
                    .disabled(selectedDays.isEmpty)
                }
            }
        }
    }
}

// MARK: - Day Selector

struct DaySelector: View {
    @Binding var selectedDays: Set<Int>
    private let days: [(Int, String)] = [(1,"Sun"),(2,"Mon"),(3,"Tue"),(4,"Wed"),(5,"Thu"),(6,"Fri"),(7,"Sat")]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(days, id: \.0) { (index, label) in
                let selected = selectedDays.contains(index)
                Button {
                    if selected { selectedDays.remove(index) }
                    else        { selectedDays.insert(index) }
                } label: {
                    Text(label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(selected ? Color.sbOrange : Color(.systemGray5))
                        .foregroundColor(selected ? .white : .primary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Helpers

private func formatTime(_ hour: Int, _ minute: Int) -> String {
    let suffix = hour < 12 ? "AM" : "PM"
    let h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
    return String(format: "%d:%02d %@", h, minute, suffix)
}

#Preview {
    ScheduleView()
}
