//
//  ClipboardSupport.swift
//  ClipNote
//
//  Created by Cizzuk on 2026/06/05.
//

import UniformTypeIdentifiers
import UIKit

class ClipboardSupport {
    static func copyFile(at url: URL, completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if FileTypes.isEditableText(url) {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    UIPasteboard.general.string = text
                }
            } else if FileTypes.isPreviewableImage(url) {
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    UIPasteboard.general.image = image
                }
            } else {
                if let fileData = try? Data(contentsOf: url) {
                    UIPasteboard.general.setData(fileData, forPasteboardType: "public.data")
                }
            }
            DispatchQueue.main.async { completion() }
        }
    }
    
    enum PasteError: Error {
        case noValidContent
    }
    
    static func newNoteFromClipboard(
        noteManager: NoteService,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let contents = ClipboardContent.read(from: UIPasteboard.general)
            
            if let handledURL = ClipboardSupport.saveNotes(contents, noteManager: noteManager) {
                completion(.success(handledURL))
            } else {
                completion(.failure(PasteError.noValidContent))
            }
        }
    }
    
    // Saves each clipboard item as a new note, returns the last one
    static func saveNotes(_ contents: [ClipboardContent], noteManager: NoteService) -> URL? {
        var lastHandled: URL?
        for content in contents {
            guard let destURL = noteManager.createFileURL(fileExtension: content.fileExtension) else { continue }
            try? content.data.write(to: destURL)
            lastHandled = destURL
        }
        return lastHandled
    }
}

