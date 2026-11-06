import Foundation

final class NotificationManager {
    struct Record {
        let scriptName: String
        let exitCode: Int32?
        let error: Error?
    }

    static let shared = NotificationManager()
    private(set) var records: [Record] = []

    func showCompletion(scriptName: String, exitCode: Int32?, error: Error?) {
        records.append(Record(scriptName: scriptName, exitCode: exitCode, error: error))
    }
}

@main
struct RunnerTests {
    static func main() {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BashMacDuler Tests \(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = ScriptStore(directoryURL: temporaryDirectory)
        let successURL = temporaryDirectory.appendingPathComponent("success script.sh")
        let failureURL = temporaryDirectory.appendingPathComponent("failure script.sh")

        write("#!/bin/bash\nprintf 'success-output\\n'\nexit 0\n", to: successURL)
        write("#!/bin/bash\nprintf 'failure-output\\n' >&2\nexit 7\n", to: failureURL)

        expect(store.add(url: successURL) == .added, "Добавление успешного скрипта")
        expect(store.add(url: successURL) == .duplicate, "Повторное добавление определяется как дубликат")
        expect(store.add(url: failureURL) == .added, "Добавление ошибочного скрипта")
        expect(
            store.add(url: temporaryDirectory.appendingPathComponent("missing.sh")) == .invalidFile,
            "Несуществующий файл не добавляется"
        )

        let runner = ScriptRunner(store: store)
        let success = store.scripts.first(where: { $0.name == successURL.lastPathComponent })!
        let failure = store.scripts.first(where: { $0.name == failureURL.lastPathComponent })!

        runner.run(success)
        runner.run(success)
        runner.run(failure)

        let timeout = Date().addingTimeInterval(10)
        while NotificationManager.shared.records.count < 2 && Date() < timeout {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        let records = NotificationManager.shared.records
        expect(records.count == 2, "Повторный запуск того же скрипта во время выполнения заблокирован")

        let successRecord = records.first(where: { $0.scriptName == success.name })
        let failureRecord = records.first(where: { $0.scriptName == failure.name })
        expect(successRecord?.exitCode == 0 && successRecord?.error == nil, "Уведомление об успехе")
        expect(failureRecord?.exitCode == 7 && failureRecord?.error == nil, "Уведомление об ошибке")

        let finishedSuccess = store.scripts.first(where: { $0.id == success.id })!
        let finishedFailure = store.scripts.first(where: { $0.id == failure.id })!
        expect(finishedSuccess.lastRun != nil && finishedSuccess.lastExitCode == 0, "Сохранение успешного результата")
        expect(finishedFailure.lastRun != nil && finishedFailure.lastExitCode == 7, "Сохранение ошибочного результата")
        expect(store.runningScriptIDs.isEmpty, "Снятие признака выполнения")

        let successLog = try! String(contentsOfFile: finishedSuccess.lastLogPath!, encoding: .utf8)
        let failureLog = try! String(contentsOfFile: finishedFailure.lastLogPath!, encoding: .utf8)
        expect(successLog.contains("success-output"), "stdout записан в лог")
        expect(successLog.contains("Код завершения: 0"), "Успешный код записан в лог")
        expect(failureLog.contains("failure-output"), "stderr записан в лог")
        expect(failureLog.contains("Код завершения: 7"), "Код ошибки записан в лог")

        testSelectedDateAdvance(store: store, script: finishedSuccess, directory: temporaryDirectory)
        testCorruptedSettingsArePreserved(in: temporaryDirectory)
        testLogRetention(in: temporaryDirectory)

        print("Все интеграционные тесты запуска пройдены")
    }

    private static func testSelectedDateAdvance(store: ScriptStore, script: ScriptItem, directory: URL) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let firstDateValue = calendar.date(byAdding: .day, value: 2, to: today),
              let secondDateValue = calendar.date(byAdding: .day, value: 4, to: today),
              let firstDate = ScheduleDate(date: firstDateValue, calendar: calendar),
              let secondDate = ScheduleDate(date: secondDateValue, calendar: calendar),
              let dueTime = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: firstDateValue) else {
            fatalError("Не удалось подготовить выбранные даты для теста")
        }

        var updatedScript = script
        updatedScript.frequency = .selectedDates
        updatedScript.hour = 9
        updatedScript.minute = 0
        updatedScript.selectedDates = [firstDate, secondDate]
        store.update(updatedScript)

        let scheduled = store.scripts.first(where: { $0.id == script.id })!
        expect(scheduled.nextRun != nil, "Для выбранных будущих дат вычисляется следующий запуск")

        store.advanceSchedule(id: script.id, after: dueTime)
        let advanced = store.scripts.first(where: { $0.id == script.id })!
        expect(advanced.selectedDates == [secondDate], "После запуска текущая и прошедшие выбранные даты удаляются")
        expect(advanced.nextRun != nil, "После запуска следующая выбранная дата остаётся запланированной")

        let reloadedStore = ScriptStore(directoryURL: directory)
        let reloaded = reloadedStore.scripts.first(where: { $0.id == script.id })!
        expect(reloaded.selectedDates == [secondDate], "Выбранные даты сохраняются в JSON")
    }

    private static func testCorruptedSettingsArePreserved(in directory: URL) {
        let damagedDirectory = directory.appendingPathComponent("Damaged Settings", isDirectory: true)
        let logsDirectory = damagedDirectory.appendingPathComponent("Logs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            fatalError("Не удалось создать каталог теста повреждённых настроек: \(error)")
        }

        let settingsURL = damagedDirectory.appendingPathComponent("scripts.json")
        let originalData = Data("{ invalid json".utf8)
        do {
            try originalData.write(to: settingsURL)
        } catch {
            fatalError("Не удалось создать повреждённый файл настроек: \(error)")
        }

        let store = ScriptStore(directoryURL: damagedDirectory)
        expect(store.userFacingError != nil, "Ошибка чтения настроек доступна интерфейсу")
        let scriptURL = damagedDirectory.appendingPathComponent("new.sh")
        write("#!/bin/bash\nprintf 'new script\\n'\n", to: scriptURL)
        expect(store.add(url: scriptURL) == .persistenceFailure, "Запись блокируется после ошибки загрузки")

        let persistedData = try! Data(contentsOf: settingsURL)
        expect(persistedData == originalData, "Исходный повреждённый файл не перезаписан")
    }

    private static func testLogRetention(in directory: URL) {
        let retentionDirectory = directory.appendingPathComponent("Log Retention", isDirectory: true)
        let logsDirectory = retentionDirectory.appendingPathComponent("Logs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            fatalError("Не удалось создать каталог логов для теста: \(error)")
        }

        let oldLogURL = logsDirectory.appendingPathComponent("old.log")
        let retainedLogURL = logsDirectory.appendingPathComponent("last-run.log")
        let recentLogURL = logsDirectory.appendingPathComponent("recent.log")
        for url in [oldLogURL, retainedLogURL, recentLogURL] {
            write("test log", to: url)
        }

        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        for url in [oldLogURL, retainedLogURL] {
            do {
                try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
            } catch {
                fatalError("Не удалось выставить дату тестового лога: \(error)")
            }
        }

        let script = ScriptItem(
            name: "retained",
            path: "/tmp/retained.sh",
            frequency: .daily,
            hour: 9,
            minute: 0,
            weekday: .monday,
            lastLogPath: retainedLogURL.path
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode([script]).write(to: retentionDirectory.appendingPathComponent("scripts.json"))
        } catch {
            fatalError("Не удалось подготовить настройки теста логов: \(error)")
        }

        _ = ScriptStore(directoryURL: retentionDirectory)
        expect(!FileManager.default.fileExists(atPath: oldLogURL.path), "Старый лог удаляется при запуске приложения")
        expect(FileManager.default.fileExists(atPath: retainedLogURL.path), "Лог последнего запуска сохраняется")
        expect(FileManager.default.fileExists(atPath: recentLogURL.path), "Свежий лог сохраняется")
    }

    private static func write(_ contents: String, to url: URL) {
        do {
            try Data(contents.utf8).write(to: url)
        } catch {
            fatalError("Не удалось создать тестовый скрипт: \(error)")
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fatalError("Тест не пройден: \(message)")
        }
    }
}
