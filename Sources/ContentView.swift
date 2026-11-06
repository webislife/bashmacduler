import AppKit
import SwiftUI

private enum ContentAlert: Identifiable {
    case duplicate
    case error(String)

    var id: String {
        switch self {
        case .duplicate:
            return "duplicate"
        case .error(let message):
            return "error-\(message)"
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: ScriptStore
    let runner: ScriptRunner

    @State private var activeAlert: ContentAlert?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BashMacDuler")
                        .font(.title2.bold())
                    Text("Скрипты выполняются, пока приложение запущено. Пропущенный во время сна запуск выполнится после пробуждения.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Добавить скрипт…") {
                    chooseScripts()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding()

            Divider()

            if store.scripts.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                    Text("Пока нет скриптов")
                        .font(.headline)
                    Text("Нажмите «Добавить скрипт…» и выберите файл.\nЗапускается через /bin/bash, права на исполнение не нужны.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                List {
                    ForEach(store.scripts) { script in
                        ScriptRow(
                            script: script,
                            isRunning: store.runningScriptIDs.contains(script.id),
                            onRun: { runner.run(script) },
                            onUpdate: { store.update($0) },
                            onDelete: { store.remove(id: script.id) }
                        )
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                if store.runningScriptIDs.isEmpty {
                    Text("Все скрипты завершены")
                        .foregroundColor(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text("Выполняется: \(store.runningScriptIDs.count)")
                }
                Spacer()
                Text("Логи: ~/Library/Application Support/ScriptBar/Logs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Выйти") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 720, minHeight: 460)
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .duplicate:
                return Alert(
                    title: Text("Файл уже добавлен"),
                    message: Text("Один или несколько выбранных скриптов уже есть в списке."),
                    dismissButton: .default(Text("ОК"))
                )
            case .error(let message):
                return Alert(
                    title: Text("Ошибка"),
                    message: Text(message),
                    dismissButton: .default(Text("ОК"), action: store.clearUserFacingError)
                )
            }
        }
        .onAppear(perform: presentStoreError)
        .onChange(of: store.userFacingError) { _ in
            presentStoreError()
        }
    }

    private func chooseScripts() {
        let panel = NSOpenPanel()
        panel.title = "Добавить bash-скрипты"
        panel.message = "Можно выбрать один или несколько файлов, в том числе без расширения .sh"
        panel.prompt = "Добавить"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else { return }

        var foundDuplicate = false
        for url in panel.urls {
            if store.add(url: url) == .duplicate {
                foundDuplicate = true
            }
        }
        if let message = store.userFacingError {
            activeAlert = .error(message)
        } else if foundDuplicate {
            activeAlert = .duplicate
        }
    }

    private func presentStoreError() {
        if let message = store.userFacingError {
            activeAlert = .error(message)
        }
    }
}

private struct ScriptRow: View {
    let script: ScriptItem
    let isRunning: Bool
    let onRun: () -> Void
    let onUpdate: (ScriptItem) -> Void
    let onDelete: () -> Void

    @State private var showsDeleteAlert = false
    @State private var dateToAdd = Date()

    private var binding: Binding<ScriptItem> {
        Binding(
            get: { script },
            set: { onUpdate($0) }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: script.hour,
                    minute: script.minute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                var updatedScript = script
                updatedScript.hour = components.hour ?? script.hour
                updatedScript.minute = components.minute ?? script.minute
                onUpdate(updatedScript)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                statusIcon
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(script.name)
                        .font(.headline)
                    Text(script.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isRunning {
                        Text("Выполняется…")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    } else if let lastRun = script.lastRun {
                        Text(lastRunDescription(lastRun))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 12)

                Button("Запустить", action: onRun)
                    .disabled(isRunning)
                Toggle("Расписание", isOn: binding.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button("Удалить") {
                    showsDeleteAlert = true
                }
                .disabled(isRunning)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Picker("", selection: binding.frequency) {
                        ForEach(ScheduleFrequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160, alignment: .leading)

                    if script.frequency == .weekly {
                        Picker("", selection: binding.weekday) {
                            ForEach(ScheduleWeekday.allCases) { weekday in
                                Text(weekday.title).tag(weekday)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 145)
                    }

                    DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 95)

                    Spacer(minLength: 0)
                }
                .disabled(!script.isEnabled)

                if script.frequency == .monthly {
                    monthDayPicker
                        .disabled(!script.isEnabled)
                } else if script.frequency == .selectedDates {
                    selectedDatesPicker
                        .disabled(!script.isEnabled)
                }
            }

            HStack {
                if script.isEnabled {
                    if let nextRun = script.nextRun {
                        Text("Следующий запуск: \(Self.format(nextRun))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(emptyScheduleDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Автоматический запуск выключен")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let logPath = script.lastLogPath {
                    Button("Открыть лог") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 8)
        .alert("Удалить задание?", isPresented: $showsDeleteAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive, action: onDelete)
        } message: {
            Text("Сам файл «\(script.name)» останется на диске.")
        }
    }

    private var monthDayPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Дни месяца:")
                .font(.caption)
                .foregroundColor(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 7),
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(1...31, id: \.self) { day in
                    let isSelected = script.monthDays.contains(day)
                    Button(String(day)) {
                        toggleMonthDay(day)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(isSelected ? .accentColor : .secondary)
                    .disabled(isSelected && script.monthDays.count == 1)
                    .accessibilityLabel("День месяца \(day)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var selectedDatesPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Добавить дату:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $dateToAdd, displayedComponents: .date)
                    .labelsHidden()
                Button("Добавить") {
                    addSelectedDate()
                }
                .disabled(ScheduleDate(date: dateToAdd).map(script.selectedDates.contains) ?? true)
            }

            if script.selectedDates.isEmpty {
                Text("Выберите одну или несколько календарных дат.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 115), alignment: .leading)],
                    alignment: .leading,
                    spacing: 5
                ) {
                    ForEach(script.selectedDates.sorted()) { date in
                        HStack(spacing: 5) {
                            Text(date.title)
                                .font(.caption)
                            Button {
                                removeSelectedDate(date)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Удалить дату \(date.title)")
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    private var emptyScheduleDescription: String {
        if script.frequency == .selectedDates {
            return script.selectedDates.isEmpty ? "Выберите даты запуска" : "Все выбранные даты прошли"
        }
        return "Расписание не содержит будущих запусков"
    }

    private func toggleMonthDay(_ day: Int) {
        var updatedScript = script
        if updatedScript.monthDays.contains(day) {
            updatedScript.monthDays.removeAll { $0 == day }
        } else {
            updatedScript.monthDays.append(day)
            updatedScript.monthDays.sort()
        }
        onUpdate(updatedScript)
    }

    private func addSelectedDate() {
        guard let date = ScheduleDate(date: dateToAdd), !script.selectedDates.contains(date) else { return }
        var updatedScript = script
        updatedScript.selectedDates.append(date)
        updatedScript.selectedDates.sort()
        onUpdate(updatedScript)
    }

    private func removeSelectedDate(_ date: ScheduleDate) {
        var updatedScript = script
        updatedScript.selectedDates.removeAll { $0 == date }
        onUpdate(updatedScript)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isRunning {
            ProgressView()
                .controlSize(.small)
        } else if script.lastRun == nil {
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        } else if script.lastExitCode == 0 {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }

    private func lastRunDescription(_ date: Date) -> String {
        let result: String
        if script.lastExitCode == 0 {
            result = "успешно"
        } else if let exitCode = script.lastExitCode {
            result = "ошибка, код \(exitCode)"
        } else {
            result = "ошибка запуска"
        }
        return "Последний запуск: \(Self.format(date)) · \(result)"
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.string(from: date)
    }
}
