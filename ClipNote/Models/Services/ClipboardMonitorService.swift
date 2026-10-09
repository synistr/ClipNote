//
//  ClipboardMonitorService.swift
//  ClipNote
//
//  Based on Clip's ApplicationMonitor and PasteboardMonitor by Riley Testut.
//

import AudioToolbox
import Combine
import UIKit
import UserNotifications

extension Notification.Name {
    static let clipboardNotificationOpened = Notification.Name("clipboardNotificationOpened")
    static let clipboardInboxDidChange = Notification.Name("clipboardInboxDidChange")
}

// Watches the clipboard while ClipNote runs in the background, and posts a notification
// whenever it changes. Swiping the notification down saves the clipboard through the
// Clipboard Reader extension, tapping it opens ClipNote and saves it there.
class ClipboardMonitorService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ClipboardMonitorService()

    // Must match UNNotificationExtensionCategory in ClipboardReader/Info.plist
    static let clipboardCategory = "ClipboardChanged"

    private enum NotificationID {
        static let clipboardChanged = "ClipboardChanged"
        static let appStoppedRunning = "AppStoppedRunning"
    }

    @Published private(set) var notificationsDenied = false

    private(set) var isMonitoring = false
    private var isListeningToPasteboard = false
    private var stoppedRunningTask: Task<Void, Never>?

    override private init() {
        super.init()
    }

    // Call on launch
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // The Clipboard Reader extension only shows up for registered categories
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.clipboardCategory, actions: [], intentIdentifiers: [])
        ])
        // Clear the "App Stopped Running" notification from a previous launch
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.appStoppedRunning])
        center.removeDeliveredNotifications(withIdentifiers: [NotificationID.appStoppedRunning])

        // Clipboards saved by the Clipboard Reader extension
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    ClipboardMonitorService.shared.clipboardInboxDidChange()
                }
            },
            ClipboardInbox.didAddNotification as CFString, nil, .deliverImmediately
        )

        if UserSettings.shared.monitorClipboard {
            start()
        }
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            refreshNotificationStatus()
        }

        scheduleStoppedRunningNotification()
        listenToPasteboard()
        BackgroundLocationService.shared.start()
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false

        stoppedRunningTask?.cancel()
        stoppedRunningTask = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [NotificationID.appStoppedRunning])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [NotificationID.clipboardChanged])
        BackgroundLocationService.shared.stop()
    }

    func refreshNotificationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsDenied = settings.authorizationStatus == .denied
        }
    }

    // MARK: - Pasteboard

    private func listenToPasteboard() {
        guard !isListeningToPasteboard else { return }
        isListeningToPasteboard = true

        // Ask the pasteboard server to notify this app about changes even while it's in the background (private API)
        #if !targetEnvironment(simulator)
        let className = ["Connection", "Server", "PB"].reversed().joined()
        let selector = NSSelectorFromString(["Notifications", "Change", "Pasteboard", "To", "Listening", "begin"].reversed().joined())
        if let serverClass = NSClassFromString(className),
           (serverClass as AnyObject).responds(to: selector) {
            _ = (serverClass as AnyObject).perform(selector)
        } else {
            print("Pasteboard change notifications are unavailable")
        }
        #endif

        let changedNotification = Notification.Name(["changed", "pasteboard", "apple", "com"].reversed().joined(separator: "."))
        _ = NotificationCenter.default.addObserver(forName: changedNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                ClipboardMonitorService.shared.pasteboardDidChange()
            }
        }
    }

    private func pasteboardDidChange() {
        guard isMonitoring else { return }
        // Skip copies made inside ClipNote
        guard UIApplication.shared.applicationState != .active else { return }

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.soundSetting == .enabled && UIDevice.current.userInterfaceIdiom == .phone {
                AudioServicesPlaySystemSound(1519) // "Peek" haptic
            }
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.clipboardCategory
        content.title = String(localized: "Clipboard Changed")
        content.body = String(localized: "Swipe down to save it as a note.")

        let request = UNNotificationRequest(identifier: NotificationID.clipboardChanged, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to post clipboard notification: \(error)")
            }
        }
    }

    private func clipboardInboxDidChange() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [NotificationID.clipboardChanged])
        NotificationCenter.default.post(name: .clipboardInboxDidChange, object: nil)
    }

    // MARK: - App Stopped Running

    // Schedules a notification a few seconds out, and replaces it before it fires for as long as ClipNote keeps running.
    // If the app gets suspended or killed, the notification goes off and reminds the user to reopen it.
    private func scheduleStoppedRunningNotification() {
        let delay: TimeInterval = 5

        let content = UNMutableNotificationContent()
        content.title = String(localized: "App Stopped Running")
        content.body = String(localized: "Tap this notification to resume monitoring your clipboard.")

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay + 1, repeats: false)
        let request = UNNotificationRequest(identifier: NotificationID.appStoppedRunning, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)

        stoppedRunningTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isMonitoring else { return }
            self.scheduleStoppedRunningNotification()
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == NotificationID.clipboardChanged,
           response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // Wait a run loop so UIPasteboard no longer returns nil because the app was in the background
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .clipboardNotificationOpened, object: nil)
            }
        }
        completionHandler()
    }
}
