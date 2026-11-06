import Foundation

private enum ScriptRunnerError: LocalizedError {
    case scriptUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable(let path):
            return "Файл скрипта недоступен для чтения: \(path)"
        }
    }
}

final class ScriptRunner {
    var onRunningCountChange: ((Int) -> Void)?

    private let store: ScriptStore
    private var runningScriptIDs: Set<UUID> = []

    init(store: ScriptStore) {
        self.store = store
    }

    func run(_ script: ScriptItem) {
        guard !runningScriptIDs.contains(script.id) else { return }

        runningScriptIDs.insert(script.id)
        store.setRunning(true, id: script.id)
        onRunningCountChange?(runningScriptIDs.count)

        let logURL = store.logsDirectoryURL.appendingPathComponent("\(UUID().uuidString).log")

        DispatchQueue.global(qos: .utility).async {
            let result = self.execute(script: script, logURL: logURL)

            DispatchQueue.main.async {
                self.store.complete(
                    id: script.id,
                    exitCode: result.exitCode,
                    logPath: result.logPath,
                    date: Date()
                )
                self.runningScriptIDs.remove(script.id)
                self.store.setRunning(false, id: script.id)
                self.onRunningCountChange?(self.runningScriptIDs.count)

                NotificationManager.shared.showCompletion(
                    scriptName: script.name,
                    exitCode: result.exitCode,
                    error: result.error
                )
            }
        }
    }

    private func execute(
        script: ScriptItem,
        logURL: URL
    ) -> (exitCode: Int32?, error: Error?, logPath: String?) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)

        do {
            let output = try FileHandle(forWritingTo: logURL)
            defer { try? output.close() }

            let header = """
            BashMacDuler
            Скрипт: \(script.name)
            Путь: \(script.path)
            Команда: /bin/bash \(script.path)
            Начало: \(Date())


            """
            output.write(Data(header.utf8))

            guard isValidScriptFile(script.fileURL) else {
                throw ScriptRunnerError.scriptUnavailable(script.path)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path]
            process.currentDirectoryURL = script.fileURL.deletingLastPathComponent()
            process.standardOutput = output
            process.standardError = output

            try process.run()
            process.waitUntilExit()

            let footer = "\nЗавершено: \(Date())\nКод завершения: \(process.terminationStatus)\n"
            output.write(Data(footer.utf8))
            return (process.terminationStatus, nil, logURL.path)
        } catch {
            var logPath: String?
            if let output = try? FileHandle(forWritingTo: logURL) {
                _ = try? output.seekToEnd()
                output.write(Data("\nОшибка запуска: \(error.localizedDescription)\n".utf8))
                try? output.close()
                logPath = logURL.path
            }
            return (nil, error, logPath)
        }
    }

    private func isValidScriptFile(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path),
              fileManager.isReadableFile(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileType = attributes[.type] as? FileAttributeType else {
            return false
        }
        return fileType == .typeRegular
    }
}
