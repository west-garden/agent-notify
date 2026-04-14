import UserNotifications

protocol Notifying {
    func notify(_ payload: NotificationPayload)
    func clearNotifications(for sessionIDs: Set<String>)
}

extension Notifying {
    func clearNotifications(for sessionIDs: Set<String>) {}
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

    func clearNotifications(for sessionIDs: Set<String>) {
        let identifiers = Array(sessionIDs)
        guard !identifiers.isEmpty else {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
