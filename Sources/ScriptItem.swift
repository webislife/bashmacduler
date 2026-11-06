import Foundation

enum ScheduleFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case selectedDates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "Ежедневно"
        case .weekly: return "Еженедельно"
        case .monthly: return "Ежемесячно"
        case .selectedDates: return "Выбранные даты"
        }
    }
}

enum ScheduleWeekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sunday: return "Воскресенье"
        case .monday: return "Понедельник"
        case .tuesday: return "Вторник"
        case .wednesday: return "Среда"
        case .thursday: return "Четверг"
        case .friday: return "Пятница"
        case .saturday: return "Суббота"
        }
    }
}

struct ScheduleDate: Codable, Hashable, Comparable, Identifiable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
    }

    var id: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    var title: String {
        String(format: "%02d.%02d.%04d", day, month, year)
    }

    func isValid(in calendar: Calendar) -> Bool {
        guard year > 0,
              (1...12).contains(month),
              let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart) else {
            return false
        }
        return daysInMonth.contains(day)
    }

    static func < (lhs: ScheduleDate, rhs: ScheduleDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

struct ScriptItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var path: String
    var frequency: ScheduleFrequency
    var hour: Int
    var minute: Int
    var weekday: ScheduleWeekday
    var monthDays: [Int]
    var selectedDates: [ScheduleDate]
    var isEnabled: Bool
    var nextRun: Date?
    var lastRun: Date?
    var lastExitCode: Int32?
    var lastLogPath: String?

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        frequency: ScheduleFrequency,
        hour: Int,
        minute: Int,
        weekday: ScheduleWeekday,
        monthDays: [Int] = [1],
        selectedDates: [ScheduleDate] = [],
        isEnabled: Bool = true,
        nextRun: Date? = nil,
        lastRun: Date? = nil,
        lastExitCode: Int32? = nil,
        lastLogPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.frequency = frequency
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
        self.monthDays = monthDays
        self.selectedDates = selectedDates
        self.isEnabled = isEnabled
        self.nextRun = nextRun
        self.lastRun = lastRun
        self.lastExitCode = lastExitCode
        self.lastLogPath = lastLogPath
    }

    var fileURL: URL {
        URL(fileURLWithPath: path)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case frequency
        case hour
        case minute
        case weekday
        case monthDays
        case selectedDates
        case isEnabled
        case nextRun
        case lastRun
        case lastExitCode
        case lastLogPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        frequency = try container.decode(ScheduleFrequency.self, forKey: .frequency)
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
        weekday = try container.decodeIfPresent(ScheduleWeekday.self, forKey: .weekday) ?? .monday
        monthDays = try container.decodeIfPresent([Int].self, forKey: .monthDays) ?? [1]
        selectedDates = try container.decodeIfPresent([ScheduleDate].self, forKey: .selectedDates) ?? []
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        nextRun = try container.decodeIfPresent(Date.self, forKey: .nextRun)
        lastRun = try container.decodeIfPresent(Date.self, forKey: .lastRun)
        lastExitCode = try container.decodeIfPresent(Int32.self, forKey: .lastExitCode)
        lastLogPath = try container.decodeIfPresent(String.self, forKey: .lastLogPath)
    }
}
