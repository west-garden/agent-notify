import UserNotifications

protocol Notifying {
    func notify(_ payload: NotificationPayload)
}

final class NotificationService: Notifying {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func notify(_ payload: NotificationPayload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body

        let request = UNNotificationRequest(
            identifier: payload.sessionID,
            content: content,
            trigger: nil
        )

        center.add(request)
    }
}
