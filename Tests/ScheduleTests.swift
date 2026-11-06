import Foundation

@main
struct ScheduleTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let mondayMorning = makeDate("2026-11-02T08:15:00Z")

        let daily = ScheduleCalculator.nextRun(
            after: mondayMorning,
            frequency: .daily,
            hour: 9,
            minute: 30,
            calendar: calendar
        )
        expect(daily == makeDate("2026-11-02T09:30:00Z"), "Ежедневный запуск в тот же день")

        let passedDaily = ScheduleCalculator.nextRun(
            after: makeDate("2026-11-02T10:00:00Z"),
            frequency: .daily,
            hour: 9,
            minute: 30,
            calendar: calendar
        )
        expect(passedDaily == makeDate("2026-11-03T09:30:00Z"), "Ежедневный запуск на следующий день")

        let weekly = ScheduleCalculator.nextRun(
            after: mondayMorning,
            frequency: .weekly,
            hour: 18,
            minute: 45,
            weekday: .friday,
            calendar: calendar
        )
        expect(weekly == makeDate("2026-11-06T18:45:00Z"), "Еженедельный запуск в ближайшую пятницу")

        let nextWeek = ScheduleCalculator.nextRun(
            after: makeDate("2026-11-06T19:00:00Z"),
            frequency: .weekly,
            hour: 18,
            minute: 45,
            weekday: .friday,
            calendar: calendar
        )
        expect(nextWeek == makeDate("2026-11-13T18:45:00Z"), "Еженедельный запуск через неделю")

        guard let losAngelesTimeZone = TimeZone(identifier: "America/Los_Angeles") else {
            fatalError("Часовой пояс America/Los_Angeles недоступен")
        }
        var daylightSavingCalendar = Calendar(identifier: .gregorian)
        daylightSavingCalendar.timeZone = losAngelesTimeZone

        let springTransition = ScheduleCalculator.nextRun(
            after: makeDate("2026-03-08T08:00:00Z"),
            frequency: .daily,
            hour: 2,
            minute: 30,
            calendar: daylightSavingCalendar
        )
        expect(
            springTransition == makeDate("2026-03-08T10:00:00Z"),
            "Несуществующее время при переходе на летнее время переносится на первый допустимый момент"
        )

        let fallTransition = ScheduleCalculator.nextRun(
            after: makeDate("2026-11-01T07:00:00Z"),
            frequency: .daily,
            hour: 1,
            minute: 30,
            calendar: daylightSavingCalendar
        )
        expect(
            fallTransition == makeDate("2026-11-01T08:30:00Z"),
            "Повторяющееся время при переходе на зимнее время выбирается по политике first"
        )

        let monthly = ScheduleCalculator.nextRun(
            after: makeDate("2026-11-02T08:15:00Z"),
            frequency: .monthly,
            hour: 9,
            minute: 30,
            monthDays: [15],
            calendar: calendar
        )
        expect(monthly == makeDate("2026-11-15T09:30:00Z"), "Ежемесячный запуск в выбранный день текущего месяца")

        let monthlyMultipleDays = ScheduleCalculator.nextRun(
            after: makeDate("2026-11-10T10:00:00Z"),
            frequency: .monthly,
            hour: 9,
            minute: 30,
            monthDays: [5, 20],
            calendar: calendar
        )
        expect(monthlyMultipleDays == makeDate("2026-11-20T09:30:00Z"), "Ежемесячно учитываются выбранные дни месяца")

        let monthlyThirtyFirst = ScheduleCalculator.nextRun(
            after: makeDate("2026-02-01T00:00:00Z"),
            frequency: .monthly,
            hour: 9,
            minute: 0,
            monthDays: [31],
            calendar: calendar
        )
        expect(monthlyThirtyFirst == makeDate("2026-03-31T09:00:00Z"), "День 31-го пропускает месяцы без такой даты")

        let selectedDates = [
            ScheduleDate(date: makeDate("2026-11-05T00:00:00Z"), calendar: calendar)!,
            ScheduleDate(date: makeDate("2026-11-10T00:00:00Z"), calendar: calendar)!,
            ScheduleDate(date: makeDate("2026-11-02T00:00:00Z"), calendar: calendar)!
        ]
        let selectedDateRun = ScheduleCalculator.nextRun(
            after: makeDate("2026-11-05T08:00:00Z"),
            frequency: .selectedDates,
            hour: 9,
            minute: 30,
            selectedDates: selectedDates,
            calendar: calendar
        )
        expect(selectedDateRun == makeDate("2026-11-05T09:30:00Z"), "Одноразовая выбранная дата запускается в назначенное время")

        let followingSelectedDate = ScheduleCalculator.nextRun(
            after: makeDate("2026-11-05T10:00:00Z"),
            frequency: .selectedDates,
            hour: 9,
            minute: 30,
            selectedDates: selectedDates,
            calendar: calendar
        )
        expect(followingSelectedDate == makeDate("2026-11-10T09:30:00Z"), "Прошедшие выбранные даты пропускаются")

        let noSelectedDates = ScheduleCalculator.nextRun(
            after: mondayMorning,
            frequency: .selectedDates,
            hour: 9,
            minute: 30,
            calendar: calendar
        )
        expect(noSelectedDates == nil, "Без выбранных дат одноразовое расписание не планирует запуск")

        testLegacyScriptDecoding()

        print("Все тесты расписания пройдены")
    }

    private static func testLegacyScriptDecoding() {
        let legacyJSON = """
        [{
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "legacy.sh",
          "path": "/tmp/legacy.sh",
          "frequency": "weekly",
          "hour": 9,
          "minute": 15,
          "weekday": 2,
          "isEnabled": true,
          "nextRun": null,
          "lastRun": null,
          "lastExitCode": null,
          "lastLogPath": null
        }]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scripts = try! decoder.decode([ScriptItem].self, from: Data(legacyJSON.utf8))
        expect(scripts.first?.frequency == .weekly, "Старое недельное расписание остаётся доступным")
        expect(scripts.first?.monthDays == [1], "Для старых записей задан день месяца по умолчанию")
        expect(scripts.first?.selectedDates.isEmpty == true, "Старые записи не получают выбранные даты")
    }

    private static func makeDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)!
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fatalError("Тест не пройден: \(message)")
        }
    }
}
