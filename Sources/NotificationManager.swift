import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("BashMacDuler: ошибка разрешения уведомлений: \(error.localizedDescription)")
            } else if !granted {
                NSLog("BashMacDuler: уведомления не разрешены пользователем")
            }
        }
    }

    func showCompletion(scriptName: String, exitCode: Int32?, error: Error?) {
        let content = UNMutableNotificationContent()
        content.title = scriptName

        if let error = error {
            content.body = "Не удалось запустить скрипт: \(error.localizedDescription)"
        } else if exitCode == 0 {
            content.body = "Скрипт успешно завершён."
        } else {
            content.body = "Скрипт завершился с ошибкой (код \(exitCode ?? -1)). Лог доступен в BashMacDuler."
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("BashMacDuler: не удалось показать уведомление: \(error.localizedDescription)")
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
