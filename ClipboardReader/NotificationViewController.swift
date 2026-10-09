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
    private var isFinished = false

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

        Task {
            // Let the expanded notification draw first: reading the clipboard can block the main thread,
            // and before the first frame that leaves the notification blank. Clip also reads it later.
            try? await Task.sleep(for: .milliseconds(300))

            // Read through item providers on the main thread, like Clip
            let contents = await ClipboardContent.load(from: UIPasteboard.general.itemProviders)
            finish(saving: contents, notificationIdentifier: identifier)
        }

        Task {
            // If reading the clipboard stalls, open ClipNote, which saves it instead
            try? await Task.sleep(for: .seconds(6))
            guard !isFinished else { return }
            isFinished = true
            extensionContext?.performNotificationDefaultAction()
        }
    }

    private func finish(saving contents: [ClipboardContent], notificationIdentifier: String) {
        guard !isFinished else { return }
        isFinished = true

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
