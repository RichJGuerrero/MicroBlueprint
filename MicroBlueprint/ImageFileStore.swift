import AppKit
import Foundation

/// Manages on-disk storage for images embedded in notes as "📎 View Image" links.
///
/// Images are stored as opaque `.dat` files named by UUID under the app's
/// Application Support directory.  The attributed string carries only the tiny
/// UUID string, so NSKeyedArchiver serialises bytes — not megabytes — on every
/// auto-save keystroke regardless of how many images a note contains.
enum ImageFileStore {

    // MARK: - Directory

    static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return base.appendingPathComponent("MicroBlueprint/Images", isDirectory: true)
    }

    // MARK: - CRUD

    /// Writes image bytes to disk atomically and returns the new UUID key.
    /// Returns `nil` if the write fails.
    @discardableResult
    static func save(_ data: Data) -> String? {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let uuid = UUID().uuidString
        let url = directory.appendingPathComponent("\(uuid).dat")
        do {
            try data.write(to: url, options: .atomic)
            return uuid
        } catch {
            return nil
        }
    }

    /// Loads image bytes for a UUID key. Returns `nil` if the file is missing.
    static func load(uuid: String) -> Data? {
        let url = directory.appendingPathComponent("\(uuid).dat")
        return try? Data(contentsOf: url)
    }

    /// Deletes the image file for a UUID key (call when a link is removed).
    static func delete(uuid: String) {
        let url = directory.appendingPathComponent("\(uuid).dat")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Migration

    /// Scans `string` for `.imageData` attributes whose value is raw `Data`
    /// (the legacy inline format) and migrates each one to an on-disk file,
    /// replacing the value with the UUID `String`.
    ///
    /// Returns the original string unchanged if no migration is needed,
    /// so this is safe to call unconditionally on every note load.
    static func migratingInlineImages(in string: NSAttributedString) -> NSAttributedString {
        // Quick check — avoid allocating a mutable copy if nothing needs migration.
        var needsMigration = false
        string.enumerateAttribute(
            .imageData,
            in: NSRange(location: 0, length: string.length)
        ) { value, _, _ in
            if value is Data { needsMigration = true }
        }
        guard needsMigration else { return string }

        let mutable = NSMutableAttributedString(attributedString: string)
        mutable.enumerateAttribute(
            .imageData,
            in: NSRange(location: 0, length: mutable.length)
        ) { value, range, _ in
            guard let data = value as? Data,
                  let uuid = ImageFileStore.save(data) else { return }
            mutable.removeAttribute(.imageData, range: range)
            mutable.addAttribute(.imageData, value: uuid as NSString, range: range)
        }
        return NSAttributedString(attributedString: mutable)
    }
}
