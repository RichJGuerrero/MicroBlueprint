import AppKit
import Foundation

struct BlueprintFolder: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct BlueprintNote: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var folderID: UUID?
    var title: String
    var bodyRTF: Data
    var tags: [String]
    var lastReviewedAt: Date?
    var reviewInterval: Int   // days between reviews
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        folderID: UUID? = nil,
        title: String,
        body: NSAttributedString = NSAttributedString(string: ""),
        tags: [String] = [],
        reviewInterval: Int = 1
    ) {
        self.id = id
        self.folderID = folderID
        self.title = title
        self.bodyRTF = body.rtfData()
        self.tags = tags
        self.lastReviewedAt = nil
        self.reviewInterval = reviewInterval
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // Custom decoder for backward compatibility — old saves lack tags/lastReviewedAt/reviewInterval
    enum CodingKeys: String, CodingKey {
        case id, folderID, title, bodyRTF, tags, lastReviewedAt, reviewInterval, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self, forKey: .id)
        folderID       = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        title          = try c.decode(String.self, forKey: .title)
        bodyRTF        = try c.decode(Data.self, forKey: .bodyRTF)
        tags           = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        lastReviewedAt = try? c.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        reviewInterval = (try? c.decodeIfPresent(Int.self, forKey: .reviewInterval)) ?? 1
        createdAt      = try c.decode(Date.self, forKey: .createdAt)
        updatedAt      = try c.decode(Date.self, forKey: .updatedAt)
    }

    // MARK: - Computed

    var attributedBody: NSAttributedString {
        NSAttributedString(rtfData: bodyRTF)
    }

    var plainBody: String {
        attributedBody.string
    }

    /// True when the note has never been reviewed, or when the review interval has elapsed.
    var isDueForReview: Bool {
        guard let lastReviewedAt else { return true }
        return Date().timeIntervalSince(lastReviewedAt) >= TimeInterval(max(1, reviewInterval)) * 86_400
    }

    /// A preview line that skips content that duplicates the title.
    var smartPreview: String {
        let titleLower = title.lowercased()
        let lines = plainBody
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let meaningful = lines.first {
            let l = $0.lowercased()
            return !l.hasPrefix(titleLower) && !titleLower.hasPrefix(l)
        }
        return meaningful ?? lines.first ?? "Empty note"
    }

    var wordCount: Int {
        plainBody.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// Rough estimate at 200 wpm; returns 0 for empty notes.
    var estimatedReadMinutes: Int {
        wordCount == 0 ? 0 : max(1, wordCount / 200)
    }
}

struct BlueprintArchive: Codable, Sendable {
    var folders: [BlueprintFolder]
    var notes: [BlueprintNote]
    var selectedNoteID: UUID?
    var selectedFolderID: UUID?
}

// MARK: - NSAttributedString helpers

extension NSAttributedString {
    static func editorDefaultAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.labelColor
        ]
    }

    convenience init(rtfData: Data) {
        // Prefer NSKeyedArchiver (preserves custom attributes like .imageData).
        // Fall back to plain RTF for notes saved before the format switch.
        let decoded: NSAttributedString?
        if let d = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSAttributedString.self, from: rtfData
        ) {
            decoded = d
        } else if let d = try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            decoded = d
        } else {
            decoded = nil
        }

        guard let decoded else {
            self.init(string: "", attributes: Self.editorDefaultAttributes())
            return
        }

        // Migrate any legacy inline NSData image payloads to on-disk UUID files.
        // Notes that are already in the new format pass through unchanged (no-op).
        self.init(attributedString: ImageFileStore.migratingInlineImages(in: decoded))
    }

    convenience init(markdownishSample title: String, lines: [String]) {
        let body = NSMutableAttributedString()
        body.append(NSAttributedString(
            string: "\(title)\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 24),
                .foregroundColor: NSColor.labelColor
            ]
        ))
        for line in lines {
            body.append(NSAttributedString(
                string: "\(line)\n",
                attributes: Self.editorDefaultAttributes()
            ))
        }
        self.init(attributedString: body)
    }

    func rtfData() -> Data {
        // NSKeyedArchiver preserves all custom attributes (e.g. .imageData) that RTF
        // would silently drop. Older notes stored as RTF are decoded transparently in
        // init(rtfData:) via the RTF fallback path, then re-saved in this format.
        (try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: false)) ?? Data()
    }
}
