import Foundation

final class ScriptScheduler {
    private let store: ScriptStore
    private let runner: ScriptRunner
    private var timer: Timer?

    init(store: ScriptStore, runner: ScriptRunner) {
        self.store = store
        self.runner = runner
    }

    func start() {
        guard timer == nil else { return }

        tick()
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()
        let dueScripts = store.scripts.filter { script in
            guard script.isEnabled, let nextRun = script.nextRun else { return false }
            return nextRun <= now
        }

        for script in dueScripts {
            store.advanceSchedule(id: script.id, after: now)
            runner.run(script)
        }
    }
}
