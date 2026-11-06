import Combine
import Foundation

enum ScriptAddResult: Equatable {
    case added
    case duplicate
    case invalidFile
    case persistenceFailure
}

final class ScriptStore: ObservableObject {
    @Published private(set) var scripts: [ScriptItem] = []
    @Published private(set) var runningScriptIDs: Set<UUID> = []
    @Published private(set) var userFacingError: String?

    let logsDirectoryURL: URL

    private let storageURL: URL
    private let fileManager: FileManager
    private var settingsLoadFailed = false

    private static let logRetentionInterval: TimeInterval = 30 * 24 * 60 * 60

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        let resolvedDirectoryURL = directoryURL
            ?? applicationSupport.appendingPathComponent("ScriptBar", isDirectory: true)
        storageURL = resolvedDirectoryURL.appendingPathComponent("scripts.json")
        logsDirectoryURL = resolvedDirectoryURL.appendingPathComponent("Logs", isDirectory: true)

        do {
            try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            reportError("Не удалось создать каталог логов: \(error.localizedDescription)")
        }
        load()
        pruneOldLogs()
    }

    @discardableResult
    func add(url: URL) -> ScriptAddResult {
        guard !settingsLoadFailed else { return .persistenceFailure }

        let standardizedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard isValidScriptFile(standardizedURL) else {
            reportError("Файл «\(url.lastPathComponent)» не найден, не является обычным файлом или недоступен для чтения.")
            return .invalidFile
        }

        guard !scripts.contains(where: {
            $0.fileURL.resolvingSymlinksInPath().standardizedFileURL == standardizedURL
        }) else {
            return .duplicate
        }

        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .minute, .weekday], from: now)
        let weekday = ScheduleWeekday(rawValue: components.weekday ?? 2) ?? .monday
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0

        var script = ScriptItem(
            name: standardizedURL.lastPathComponent,
            path: standardizedURL.path,
            frequency: .daily,
            hour: hour,
            minute: minute,
            weekday: weekday
        )
        script.nextRun = ScheduleCalculator.nextRun(
            after: now,
            frequency: script.frequency,
            hour: script.hour,
            minute: script.minute,
            weekday: script.weekday,
            monthDays: script.monthDays,
            selectedDates: script.selectedDates
        )

        scripts.append(script)
        guard save() else {
            scripts.removeLast()
            return .persistenceFailure
        }
        return .added
    }

    func update(_ script: ScriptItem) {
        guard !settingsLoadFailed else { return }
        guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        guard (0...23).contains(script.hour), (0...59).contains(script.minute) else {
            reportError("Укажите корректное время запуска.")
            return
        }
        let monthDays = Array(Set(script.monthDays)).sorted()
        guard script.frequency != .monthly || (!monthDays.isEmpty && monthDays.allSatisfy { (1...31).contains($0) }) else {
            reportError("Для ежемесячного запуска выберите хотя бы один день месяца от 1 до 31.")
            return
        }
        let selectedDates = Array(Set(script.selectedDates)).sorted()
        guard selectedDates.allSatisfy({ $0.isValid(in: .current) }) else {
            reportError("Выберите корректные календарные даты.")
            return
        }

        var updatedScript = script
        updatedScript.monthDays = monthDays
        updatedScript.selectedDates = selectedDates
        updatedScript.nextRun = script.isEnabled
            ? ScheduleCalculator.nextRun(
                after: Date(),
                frequency: script.frequency,
                hour: script.hour,
                minute: script.minute,
                weekday: script.weekday,
                monthDays: monthDays,
                selectedDates: selectedDates
            )
            : nil

        let previousScript = scripts[index]
        scripts[index] = updatedScript
        if !save() {
            scripts[index] = previousScript
        }
    }

    func remove(id: UUID) {
        guard !settingsLoadFailed else { return }
        guard !runningScriptIDs.contains(id) else { return }
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        let removedScript = scripts[index]
        scripts.removeAll(where: { $0.id == id })
        if !save() {
            scripts.insert(removedScript, at: min(index, scripts.count))
        }
    }

    func advanceSchedule(id: UUID, after date: Date) {
        guard !settingsLoadFailed else { return }
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        var script = scripts[index]
        guard script.isEnabled else { return }

        if script.frequency == .selectedDates,
           let today = ScheduleDate(date: date) {
            script.selectedDates.removeAll { $0 <= today }
        }
        script.nextRun = ScheduleCalculator.nextRun(
            after: date,
            frequency: script.frequency,
            hour: script.hour,
            minute: script.minute,
            weekday: script.weekday,
            monthDays: script.monthDays,
            selectedDates: script.selectedDates
        )
        scripts[index] = script
        // Даже при ошибке сохранения сдвигаем расписание в памяти, чтобы
        // следующий тик планировщика не запустил просроченное задание повторно.
        _ = save()
    }

    func setRunning(_ isRunning: Bool, id: UUID) {
        if isRunning {
            runningScriptIDs.insert(id)
        } else {
            runningScriptIDs.remove(id)
        }
    }

    func complete(id: UUID, exitCode: Int32?, logPath: String?, date: Date) {
        guard !settingsLoadFailed else { return }
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts[index].lastRun = date
        scripts[index].lastExitCode = exitCode
        scripts[index].lastLogPath = logPath
        _ = save()
    }

    func clearUserFacingError() {
        userFacingError = nil
    }

    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            scripts = try decoder.decode([ScriptItem].self, from: data)

            var needsSave = false
            let now = Date()
            for index in scripts.indices where scripts[index].isEnabled && scripts[index].nextRun == nil {
                let script = scripts[index]
                let nextRun = ScheduleCalculator.nextRun(
                    after: now,
                    frequency: script.frequency,
                    hour: script.hour,
                    minute: script.minute,
                    weekday: script.weekday,
                    monthDays: script.monthDays,
                    selectedDates: script.selectedDates
                )
                if let nextRun {
                    scripts[index].nextRun = nextRun
                    needsSave = true
                }
            }
            if needsSave {
                save()
            }
        } catch {
            settingsLoadFailed = true
            reportError("Не удалось загрузить настройки. Исходный файл сохранён без изменений; пока ошибка не устранена, изменения отключены. \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func save() -> Bool {
        guard !settingsLoadFailed else {
            return false
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(scripts)
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storageURL, options: .atomic)
            userFacingError = nil
            return true
        } catch {
            reportError("Не удалось сохранить настройки: \(error.localizedDescription)")
            return false
        }
    }

    private func isValidScriptFile(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              fileManager.isReadableFile(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileType = attributes[.type] as? FileAttributeType else {
            return false
        }
        return fileType == .typeRegular
    }

    private func reportError(_ message: String) {
        userFacingError = message
        NSLog("BashMacDuler: \(message)")
    }

    private func pruneOldLogs(now: Date = Date()) {
        guard !settingsLoadFailed else { return }

        do {
            let logURLs = try fileManager.contentsOfDirectory(
                at: logsDirectoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
            )
            let retainedPaths = Set(scripts.compactMap { $0.lastLogPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path } })
            let cutoffDate = now.addingTimeInterval(-Self.logRetentionInterval)

            for logURL in logURLs where logURL.pathExtension.lowercased() == "log" {
                guard !retainedPaths.contains(logURL.standardizedFileURL.path) else { continue }
                let values = try logURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values.isRegularFile == true,
                      let modificationDate = values.contentModificationDate,
                      modificationDate < cutoffDate else {
                    continue
                }
                try fileManager.removeItem(at: logURL)
            }
        } catch {
            NSLog("BashMacDuler: не удалось очистить старые логи: \(error.localizedDescription)")
        }
    }
}
