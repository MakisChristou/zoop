import UserNotifications

/// Injectable boundary for scheduling/permission tests without posting real alerts.
@MainActor struct ReminderNotificationClient {
    var authorization: () async -> UNAuthorizationStatus
    var pending: () async -> [UNNotificationRequest]
    var delivered: () async -> [UNNotification]
    var add: (UNNotificationRequest) async throws -> Void
    var removePending: ([String]) -> Void
    var removeDelivered: ([String]) -> Void
    static var live: Self {
        let center = UNUserNotificationCenter.current()
        return Self(authorization: { await center.notificationSettings().authorizationStatus },
                    pending: { await center.pendingNotificationRequests() }, delivered: { await center.deliveredNotifications() },
                    add: { try await center.add($0) }, removePending: { center.removePendingNotificationRequests(withIdentifiers: $0) },
                    removeDelivered: { center.removeDeliveredNotifications(withIdentifiers: $0) })
    }
}
