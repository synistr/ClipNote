//
//  NotificationViewController.swift
//  ClipNote Clipboard Reader
//
//  Based on Clip's ClipboardReader by Riley Testut.
//

import UIKit
import UserNotifications
import UserNotificationsUI

// Saves the clipboard when the "Clipboard Changed" notification is expanded.
// The app can't read the clipboard from the background, but an expanded notification can.
class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func didReceive(_ notification: UNNotification) {
        let identifier = notification.request.identifier

        Task {
            let contents = await Task.detached(priority: .userInitiated) {
                ClipboardContent.read(from: UIPasteboard.general)
            }.value

            finish(saving: contents, notificationIdentifier: identifier)
        }
    }

    private func finish(saving contents: [ClipboardContent], notificationIdentifier: String) {
        guard !contents.isEmpty else {
            // Can't dismiss the extension before reading the clipboard, so only now
            extensionContext?.dismissNotificationContentExtension()
            postFailure(String(localized: "The clipboard is empty, or pasting wasn't allowed."))
            return
        }

        do {
            try ClipboardInbox.add(contents)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            extensionContext?.dismissNotificationContentExtension()
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
        } catch {
            // Too large to hand over through the keychain: open ClipNote, which saves the clipboard itself
            print("Failed to add clipboard to inbox: \(error)")
            extensionContext?.performNotificationDefaultAction()
        }
    }

    private func postFailure(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Failed to Save Clipboard")
        content.body = message

        let request = UNNotificationRequest(identifier: "SaveError", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
