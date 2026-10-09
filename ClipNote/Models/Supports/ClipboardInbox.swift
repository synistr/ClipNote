//
//  ClipboardInbox.swift
//  ClipNote
//
//  Hands clipboards saved by the Clipboard Reader notification extension to the app.
//  App Groups aren't available, so this goes through a shared keychain access group.
//

import Foundation
import Security

nonisolated
enum ClipboardInbox {
    // Darwin notification posted after adding to the inbox
    static let didAddNotification = "com.fkeil.ClipNote.ClipboardInbox.didAdd"

    private static let service = "com.fkeil.ClipNote.ClipboardInbox"

    enum InboxError: Error {
        case keychain(OSStatus)
    }

    static func add(_ contents: [ClipboardContent]) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(contents)

        // No access group: items go to the first group in keychain-access-groups, shared by the app and extension
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: UUID().uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw InboxError.keychain(status) }

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(didAddNotification as CFString),
            nil, nil, true
        )
    }

    // Removes and returns everything in the inbox, oldest first
    static func takeAll() -> [ClipboardContent] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]]
        else { return [] }

        let accounts = items
            .sorted { ($0[kSecAttrCreationDate as String] as? Date ?? .distantPast) < ($1[kSecAttrCreationDate as String] as? Date ?? .distantPast) }
            .compactMap { $0[kSecAttrAccount as String] as? String }

        var contents: [ClipboardContent] = []
        for account in accounts {
            let itemQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            var dataQuery = itemQuery
            dataQuery[kSecReturnData as String] = true
            dataQuery[kSecMatchLimit as String] = kSecMatchLimitOne

            var dataRef: CFTypeRef?
            if SecItemCopyMatching(dataQuery as CFDictionary, &dataRef) == errSecSuccess,
               let data = dataRef as? Data,
               let decoded = try? PropertyListDecoder().decode([ClipboardContent].self, from: data) {
                contents += decoded
            }
            SecItemDelete(itemQuery as CFDictionary)
        }
        return contents
    }
}
