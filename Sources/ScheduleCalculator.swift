import Foundation

enum ScheduleCalculator {
    static func nextRun(
        after date: Date,
        frequency: ScheduleFrequency,
        hour: Int,
        minute: Int,
        weekday: ScheduleWeekday = .monday,
        monthDays: [Int] = [1],
        selectedDates: [ScheduleDate] = [],
        calendar: Calendar = .current
    ) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        switch frequency {
        case .daily, .weekly:
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            components.second = 0
            if frequency == .weekly {
                components.weekday = weekday.rawValue
            }

            return calendar.nextDate(
                after: date,
                matching: components,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )

        case .monthly:
            return nextMonthlyRun(
                after: date,
                hour: hour,
                minute: minute,
                monthDays: monthDays,
                calendar: calendar
            )

        case .selectedDates:
            return selectedDates
                .sorted()
                .compactMap { occurrence(on: $0, hour: hour, minute: minute, after: date, calendar: calendar) }
                .min()
        }
    }

    private static func nextMonthlyRun(
        after date: Date,
        hour: Int,
        minute: Int,
        monthDays: [Int],
        calendar: Calendar
    ) -> Date? {
        let days = Array(Set(monthDays.filter { (1...31).contains($0) })).sorted()
        guard !days.isEmpty,
              let firstMonth = calendar.dateInterval(of: .month, for: date)?.start else {
            return nil
        }

        // A selected day of month (including the 29th–31st) occurs within two years.
        for monthOffset in 0..<24 {
            guard let month = calendar.date(byAdding: .month, value: monthOffset, to: firstMonth),
                  let components = calendar.dateComponents([.year, .month], from: month).yearMonth,
                  let daysInMonth = calendar.range(of: .day, in: .month, for: month) else {
                continue
            }

            let occurrences = days.compactMap { day -> Date? in
                guard daysInMonth.contains(day) else { return nil }
                let scheduleDate = ScheduleDate(year: components.year, month: components.month, day: day)
                return occurrence(on: scheduleDate, hour: hour, minute: minute, after: date, calendar: calendar)
            }
            if let nextDate = occurrences.min() {
                return nextDate
            }
        }
        return nil
    }

    private static func occurrence(
        on scheduleDate: ScheduleDate,
        hour: Int,
        minute: Int,
        after date: Date,
        calendar: Calendar
    ) -> Date? {
        guard scheduleDate.isValid(in: calendar),
              let dayStart = calendar.date(from: DateComponents(
                year: scheduleDate.year,
                month: scheduleDate.month,
                day: scheduleDate.day
              )) else {
            return nil
        }

        var matchingComponents = DateComponents()
        matchingComponents.year = scheduleDate.year
        matchingComponents.month = scheduleDate.month
        matchingComponents.day = scheduleDate.day
        matchingComponents.hour = hour
        matchingComponents.minute = minute
        matchingComponents.second = 0

        guard let candidate = calendar.nextDate(
            after: dayStart.addingTimeInterval(-1),
            matching: matchingComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ), candidate > date else {
            return nil
        }

        let actualDate = calendar.dateComponents([.year, .month, .day], from: candidate)
        guard actualDate.year == scheduleDate.year,
              actualDate.month == scheduleDate.month,
              actualDate.day == scheduleDate.day else {
            return nil
        }
        return candidate
    }
}

private extension DateComponents {
    var yearMonth: (year: Int, month: Int)? {
        guard let year, let month else { return nil }
        return (year, month)
    }
}
