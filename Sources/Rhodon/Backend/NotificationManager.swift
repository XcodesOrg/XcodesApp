import Foundation
import Observation
import os.log
import UserNotifications
import RhodonKit

/// Representation of the 3 states of the Notifications permission prompt which may either have not been shown, or was
/// shown and denied or accepted
/// Unknown is value to indicate that we have not yet determined the status and should not be used other than as a
/// default value before determining the actual status
public enum NotificationPermissionPromptStatus: Int, Sendable {
    case unknown, notShown, shownAndDenied, shownAndAccepted
}

public enum RhodonNotificationCategory: String, Sendable {
    case normal
    case error
}

public enum RhodonNotificationType: String, Identifiable, CaseIterable, CustomStringConvertible, Sendable {
    case newVersionAvailable
    case finishedInstalling

    public var id: Self {
        self
    }

    public var description: String {
        switch self {
        case .newVersionAvailable:
            "New version is available"
        case .finishedInstalling:
            "Finished installing"
        }
    }
}

@Observable
public class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let notificationCenter = UNUserNotificationCenter.current()

    var notificationStatus = NotificationPermissionPromptStatus.unknown

    override public init() {
        super.init()
        loadNotificationStatus()

        notificationCenter.delegate = self
    }

    public func loadNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings(completionHandler: { [weak self] settings in
            let status = NotificationManager.systemPromptStatusFromSettings(settings)
            Task {
                await self?.updateNotificationStatus(status)
            }
        })
    }

    private class func systemPromptStatusFromSettings(_ settings: UNNotificationSettings)
        -> NotificationPermissionPromptStatus {
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notShown
        case .authorized, .provisional:
            return .shownAndAccepted
        case .denied:
            return .shownAndDenied
        @unknown default:
            return .unknown
        }
    }

    public func requestAccess() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            Task {
                await self?.handleAuthorizationResponse(granted: granted, error: error)
            }
        }
    }

    @MainActor
    private func updateNotificationStatus(_ status: NotificationPermissionPromptStatus) {
        notificationStatus = status
    }

    @MainActor
    private func handleAuthorizationResponse(granted: Bool, error: Error?) {
        if let error {
            // Handle the error here.
            Logger.appState.error("Error requesting notification accesss: \(error.legibleLocalizedDescription)")
        } else {
            Logger.appState.log("User has \(granted ? "Granted" : "NOT GRANTED") notification permission")
        }
        loadNotificationStatus()
    }

    func scheduleNotification(title: String?, body: String, category: RhodonNotificationCategory) {
        let content = UNMutableNotificationContent()
        if let title {
            content.title = title
        }
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.rawValue

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.3, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        notificationCenter.add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }
}
