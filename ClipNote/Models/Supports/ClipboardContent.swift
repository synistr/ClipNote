//
//  ClipboardContent.swift
//  ClipNote
//
//  Created by Cizzuk on 2026/06/05.
//

import UniformTypeIdentifiers
import UIKit

// A clipboard item, converted to the file it's saved as
nonisolated
struct ClipboardContent: Codable {
    let fileExtension: String
    let data: Data

    static func read(from pasteboard: UIPasteboard) -> [ClipboardContent] {
        var contents: [ClipboardContent] = []

        for (index, item) in pasteboard.items.enumerated() {
            let indexSet = IndexSet(integer: index)
            func getData(for type: String) -> Data? {
                pasteboard.data(forPasteboardType: type, inItemSet: indexSet)?.first
            }

            // 1. Text or URL -> .txt
            var textContent: String?
            let textTypes = [
                UTType.plainText.identifier,
                UTType.utf8PlainText.identifier,
                UTType.text.identifier,
                UTType.rtf.identifier,
            ]

            if let matchedType = textTypes.first(where: { item.keys.contains($0) }),
               let data = getData(for: matchedType) {
                textContent = String(data: data, encoding: .utf8)

            } else if item.keys.contains(UTType.url.identifier),
                      let data = getData(for: UTType.url.identifier) {
                // This URL is maybe bplist, so need to convert to string
                // Parse to [Any]
                if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [Any] {
                    // Find URL
                    for entry in dict {
                        // Try parse as String
                        if let urlString = entry as? String,
                           // Try convert to URL
                           let url = URL(string: urlString) {
                            // Use absoluteString as text content
                            textContent = url.absoluteString
                            break
                        }
                    }
                }
            }

            if let text = textContent {
                contents.append(ClipboardContent(fileExtension: "txt", data: Data(text.utf8)))
                continue
            }

            // 2. File URL
            if item.keys.contains(UTType.fileURL.identifier),
               let data = getData(for: UTType.fileURL.identifier),
               let url = URL(dataRepresentation: data, relativeTo: nil),
               let fileData = try? Data(contentsOf: url) {
                contents.append(ClipboardContent(fileExtension: url.pathExtension, data: fileData))
                continue
            }

            // 3. Generic Data (Fallback) (No extension)
            for typeIdentifier in item.keys.sorted() {
                guard let type = UTType(typeIdentifier),
                      let data = getData(for: typeIdentifier) else { continue }

                contents.append(ClipboardContent(fileExtension: type.preferredFilenameExtension ?? "", data: data))
                break
            }
        }

        return contents
    }

    // Loads only the representations a note needs, like Clip does. Reading UIPasteboard.items instead
    // makes the source app hand over every representation of every item first, which can take so long
    // that the notification extension never gets to save.
    static func load(from itemProviders: [NSItemProvider]) async -> [ClipboardContent] {
        var contents: [ClipboardContent] = []
        for provider in itemProviders {
            if let content = await load(from: provider) {
                contents.append(content)
            }
        }
        return contents
    }

    private static func load(from provider: NSItemProvider) async -> ClipboardContent? {
        // 1. Text -> .txt
        let textTypes = [UTType.utf8PlainText, UTType.plainText, UTType.text]
        if textTypes.contains(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }),
           provider.canLoadObject(ofClass: String.self),
           let text = await loadText(from: provider) {
            return ClipboardContent(fileExtension: "txt", data: Data(text.utf8))
        }

        // 2. URL: web links -> .txt, files are copied
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           provider.canLoadObject(ofClass: URL.self),
           let url = await loadURL(from: provider) {
            if !url.isFileURL {
                return ClipboardContent(fileExtension: "txt", data: Data(url.absoluteString.utf8))
            }
            if let fileData = try? Data(contentsOf: url) {
                return ClipboardContent(fileExtension: url.pathExtension, data: fileData)
            }
        }

        // 3. Anything else (images etc.): the highest fidelity type that has a file extension
        for typeIdentifier in provider.registeredTypeIdentifiers {
            guard let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension,
                  let data = await loadData(typeIdentifier, from: provider)
            else { continue }
            return ClipboardContent(fileExtension: fileExtension, data: data)
        }

        return nil
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadData(_ typeIdentifier: String, from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
