import Foundation
import os.log
import UserNotifications

/// Representation of the 3 states of the Notifications permission prompt which may either have not been shown, or was shown and denied or accepted
/// Unknown is value to indicate that we have not yet determined the status and should not be used other than as a default value before determining the actual status
public enum NotificationPermissionPromptStatus: Int {
    case unknown, notShown, shownAndDenied, shownAndAccepted
}

public enum XcodesNotificationCategory: String {
    case normal
    case error
}

public enum XcodesNotificationType: String, Identifiable, CaseIterable, CustomStringConvertible {
    case newVersionAvailable
    case finishedInstalling

    public var id: Self { self }
    
    public var description: String {
        switch self {
            case .newVersionAvailable:
                return localizeString("Notification.NewVersionAvailable")
            case .finishedInstalling:
                return localizeString("Notification.FinishedInstalling")
        }
    }
}

@MainActor
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    private let notificationCenter = UNUserNotificationCenter.current()
    private var notificationStatusTask: Task<Void, Never>?
    private var notificationStatusTaskID: UUID?
    private var requestAccessTask: Task<Void, Never>?
    private var requestAccessTaskID: UUID?
    
    @Published var notificationStatus = NotificationPermissionPromptStatus.unknown
    
    nonisolated public override init() {
        super.init()
        Task { @MainActor [weak self] in
            guard let self else { return }
            loadNotificationStatus()
            notificationCenter.delegate = self
        }
    }

    deinit {
        notificationStatusTask?.cancel()
        requestAccessTask?.cancel()
    }
    
    public func loadNotificationStatus() {
        notificationStatusTask?.cancel()
        let taskID = UUID()
        notificationStatusTaskID = taskID
        notificationStatusTask = Task { [weak self] in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard !Task.isCancelled else {
                await self?.clearNotificationStatusTask(id: taskID)
                return
            }

            let status = NotificationManager.systemPromptStatusFromSettings(settings)
            await self?.setNotificationStatus(status, ifNotificationStatusTaskID: taskID)
            await self?.clearNotificationStatusTask(id: taskID)
        }
    }
    
    private class func systemPromptStatusFromSettings(_ settings: UNNotificationSettings) -> NotificationPermissionPromptStatus {
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
        notificationStatusTask?.cancel()
        notificationStatusTask = nil
        notificationStatusTaskID = nil
        requestAccessTask?.cancel()
        let taskID = UUID()
        requestAccessTaskID = taskID
        requestAccessTask = Task { [weak self] in
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                guard !Task.isCancelled else {
                    await self?.clearRequestAccessTask(id: taskID)
                    return
                }

                Logger.appState.log("User has \(granted ? "Granted" : "NOT GRANTED") notification permission")
            } catch {
                guard !Task.isCancelled else {
                    await self?.clearRequestAccessTask(id: taskID)
                    return
                }

                Logger.appState.error("Error requesting notification accesss: \(error.legibleLocalizedDescription)")
            }

            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard !Task.isCancelled else {
                await self?.clearRequestAccessTask(id: taskID)
                return
            }

            let status = NotificationManager.systemPromptStatusFromSettings(settings)
            await self?.setNotificationStatus(status, ifRequestAccessTaskID: taskID)
            await self?.clearRequestAccessTask(id: taskID)
        }
    }

    @MainActor
    private func setNotificationStatus(
        _ status: NotificationPermissionPromptStatus,
        ifNotificationStatusTaskID notificationStatusTaskID: UUID? = nil,
        ifRequestAccessTaskID requestAccessTaskID: UUID? = nil
    ) {
        if let notificationStatusTaskID, notificationStatusTaskID != self.notificationStatusTaskID {
            return
        }

        if let requestAccessTaskID, requestAccessTaskID != self.requestAccessTaskID {
            return
        }

        notificationStatus = status
    }

    @MainActor
    private func clearNotificationStatusTask(id: UUID) {
        guard id == notificationStatusTaskID else { return }

        notificationStatusTask = nil
        notificationStatusTaskID = nil
    }

    @MainActor
    private func clearRequestAccessTask(id: UUID) {
        guard id == requestAccessTaskID else { return }

        requestAccessTask = nil
        requestAccessTaskID = nil
    }
    
    func scheduleNotification(title: String?, body: String, category: XcodesNotificationCategory) {
          
        let content = UNMutableNotificationContent()
        if let title = title {
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
    
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler( [.banner, .badge, .sound])
    }
}
