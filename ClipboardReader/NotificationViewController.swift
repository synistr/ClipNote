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
    override func viewDidLoad() {
        super.viewDidLoad()

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()

        let label = UILabel()
        label.text = String(localized: "Saving to ClipNote…")
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [activityIndicator, label])
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func didReceive(_ notification: UNNotification) {
        let identifier = notification.request.identifier

        // Read the clipboard on the main thread through item providers, like Clip
        let itemProviders = UIPasteboard.general.itemProviders

        Task {
            let contents = await ClipboardContent.load(from: itemProviders)
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
