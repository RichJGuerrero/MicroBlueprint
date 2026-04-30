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
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        folderID: UUID? = nil,
        title: String,
        body: NSAttributedString = NSAttributedString(string: "")
    ) {
        self.id = id
        self.folderID = folderID
        self.title = title
        self.bodyRTF = body.rtfData()
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var attributedBody: NSAttributedString {
        NSAttributedString(rtfData: bodyRTF)
    }

    var plainBody: String {
        attributedBody.string
    }
}

struct BlueprintArchive: Codable, Sendable {
    var folders: [BlueprintFolder]
    var notes: [BlueprintNote]
    var selectedNoteID: UUID?
    var selectedFolderID: UUID?
}

extension NSAttributedString {
    static func editorDefaultAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.labelColor
        ]
    }

    convenience init(rtfData: Data) {
        if let decoded = try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            self.init(attributedString: decoded)
        } else {
            self.init(string: "", attributes: Self.editorDefaultAttributes())
        }
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
        guard length > 0 else {
            return (try? NSAttributedString(string: "", attributes: Self.editorDefaultAttributes())
                .data(from: NSRange(location: 0, length: 0), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
        }

        return (try? data(
            from: NSRange(location: 0, length: length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }
}
