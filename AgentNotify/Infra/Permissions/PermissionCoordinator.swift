import UserNotifications

struct PermissionState {
    let notificationsGranted: Bool
    let automationLikelyGranted: Bool
}

final class PermissionCoordinator {
    func requestNotificationAuthorizationIfNeeded() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func currentState() async -> PermissionState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return PermissionState(
            notificationsGranted: settings.authorizationStatus == .authorized,
            automationLikelyGranted: true
        )
    }
}
