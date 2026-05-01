import AppKit
import Combine
import Foundation

enum FolderScope: Equatable {
    case all
    case unfiled
    case folder(UUID)
    case reviewDue
    case tagged(String)
}

@MainActor
final class NotesStore: ObservableObject {
    @Published var folders: [BlueprintFolder] = []
    @Published var notes: [BlueprintNote] = []
    @Published var selectedNoteID: UUID?
    @Published var folderScope: FolderScope = .all
    @Published var searchQuery = ""
    @Published var studyMode = false
    @Published var showLeftPanel = true
    @Published var showRightPanel = true
    @Published var shouldFocusTitle = false

    private let storageURL: URL
    private var saveTask: Task<Void, Never>?

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        load()
    }

    // MARK: - Derived state

    var selectedNote: BlueprintNote? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    var selectedFolderID: UUID? {
        if case .folder(let id) = folderScope { return id }
        return nil
    }

    /// All unique tags across every note, sorted alphabetically.
    var allTags: [String] {
        Array(Set(notes.flatMap(\.tags))).sorted()
    }

    /// Number of notes currently due for review.
    var reviewDueCount: Int {
        notes.filter(\.isDueForReview).count
    }

    var filteredNotes: [BlueprintNote] {
        let scoped = notes.filter { note in
            switch folderScope {
            case .all:              return true
            case .unfiled:          return note.folderID == nil
            case .folder(let id):   return note.folderID == id
            case .reviewDue:        return note.isDueForReview
            case .tagged(let tag):  return note.tags.contains(tag)
            }
        }

        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return scoped.sorted { $0.updatedAt > $1.updatedAt }
        }

        return scoped
            .filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.plainBody.localizedCaseInsensitiveContains(trimmed)
                || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) })
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var selectedAttributedBody: NSAttributedString {
        selectedNote?.attributedBody ?? NSAttributedString(string: "", attributes: NSAttributedString.editorDefaultAttributes())
    }

    // MARK: - Folder operations

    func createFolder(named rawName: String? = nil) {
        let name = uniqueName(base: rawName?.nonEmptyTrimmed ?? "New Project", existing: folders.map(\.name))
        let folder = BlueprintFolder(name: name)
        folders.insert(folder, at: 0)
        folderScope = .folder(folder.id)
        scheduleSave()
    }

    func renameFolder(_ folderID: UUID, to rawName: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].name = rawName.nonEmptyTrimmed ?? "Untitled Project"
        folders[index].updatedAt = Date()
        scheduleSave()
    }

    func deleteFolder(_ folderID: UUID) {
        folders.removeAll { $0.id == folderID }
        for index in notes.indices where notes[index].folderID == folderID {
            notes[index].folderID = nil
            notes[index].updatedAt = Date()
        }
        if case .folder(folderID) = folderScope {
            folderScope = .all
        }
        scheduleSave()
    }

    // MARK: - Note operations

    @discardableResult
    func createNote(title rawTitle: String? = nil, in folderID: UUID? = nil) -> UUID {
        // Prefer explicit folderID arg, then current folder scope
        let targetFolderID: UUID?
        if let folderID {
            targetFolderID = folderID
        } else if case .folder(let id) = folderScope {
            targetFolderID = id
        } else {
            targetFolderID = nil
        }

        let note = BlueprintNote(
            folderID: targetFolderID,
            title: rawTitle?.nonEmptyTrimmed ?? "Untitled Note",
            body: NSAttributedString(string: "", attributes: NSAttributedString.editorDefaultAttributes())
        )
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        if let targetFolderID {
            folderScope = .folder(targetFolderID)
        }
        studyMode = false
        shouldFocusTitle = true
        scheduleSave()
        return note.id
    }

    func deleteSelectedNote() {
        guard let selectedNoteID else { return }
        deleteNote(selectedNoteID)
    }

    func deleteNote(_ noteID: UUID) {
        notes.removeAll { $0.id == noteID }
        if selectedNoteID == noteID {
            selectedNoteID = filteredNotes.first?.id ?? notes.first?.id
        }
        scheduleSave()
    }

    func renameNote(_ noteID: UUID, to rawTitle: String) {
        updateNote(noteID) { $0.title = rawTitle.nonEmptyTrimmed ?? "Untitled Note" }
    }

    func updateSelectedBody(_ attributedString: NSAttributedString) {
        guard let selectedNoteID else { return }
        updateNote(selectedNoteID) { $0.bodyRTF = attributedString.rtfData() }
    }

    func moveNote(_ noteID: UUID, to folderID: UUID?) {
        updateNote(noteID) { $0.folderID = folderID }
    }

    // MARK: - Review & tagging

    func markReviewed(_ noteID: UUID) {
        updateNote(noteID) { $0.lastReviewedAt = Date() }
    }

    func updateTags(_ noteID: UUID, tags: [String]) {
        updateNote(noteID) { $0.tags = tags }
    }

    func updateReviewInterval(_ noteID: UUID, days: Int) {
        updateNote(noteID) { $0.reviewInterval = max(1, days) }
    }

    // MARK: - Selection & scope

    func selectFolderScope(_ scope: FolderScope) {
        folderScope = scope
        if let selectedNote, !filteredNotes.contains(where: { $0.id == selectedNote.id }) {
            selectedNoteID = filteredNotes.first?.id
        } else if selectedNoteID == nil {
            selectedNoteID = filteredNotes.first?.id
        }
    }

    func selectNote(_ noteID: UUID) {
        selectedNoteID = noteID
    }

    func folderName(for folderID: UUID?) -> String {
        guard let folderID else { return "Unfiled" }
        return folders.first(where: { $0.id == folderID })?.name ?? "Missing Project"
    }

    // MARK: - Private

    private func updateNote(_ noteID: UUID, mutation: (inout BlueprintNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        mutation(&notes[index])
        notes[index].updatedAt = Date()
        scheduleSave()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: storageURL)
            let archive = try JSONDecoder.blueprint.decode(BlueprintArchive.self, from: data)
            folders = archive.folders
            notes = archive.notes
            selectedNoteID = archive.selectedNoteID ?? archive.notes.first?.id
            if let folderID = archive.selectedFolderID {
                folderScope = .folder(folderID)
            }
        } catch {
            seedSampleData()
            scheduleSave()
        }
    }

    private func seedSampleData() {
        let aPlus = BlueprintFolder(name: "CompTIA A+ Study")
        let general = BlueprintFolder(name: "General Notes")

        let troubleshooting = NSAttributedString(
            markdownishSample: "Troubleshooting Flow",
            lines: [
                "• Identify the problem and gather symptoms.",
                "• Establish a theory of probable cause.",
                "• Test the theory to confirm or deny, then escalate if needed.",
                "• Establish a plan of action, implement it, and verify.",
                "• Document findings, actions, and outcomes.",
                "",
                "Tip: use highlights for commands, port numbers, and exam traps."
            ]
        )

        let hardware = NSAttributedString(
            markdownishSample: "Hardware Symptoms Cheat Sheet",
            lines: [
                "RAM issues: random crashes, BSODs, POST beep codes.",
                "Storage failure: slow boot, clicking sounds, missing files.",
                "Power issues: random shutdowns, won't POST, dead fans.",
                "Thermal: throttling, shutdowns under load, excessive heat.",
                "",
                "Keep notes atomic — one concept per note works best for review."
            ]
        )

        folders = [aPlus, general]
        notes = [
            BlueprintNote(
                folderID: aPlus.id,
                title: "Troubleshooting Methodology",
                body: troubleshooting,
                tags: ["5.0-troubleshooting"]
            ),
            BlueprintNote(
                folderID: aPlus.id,
                title: "Hardware Symptoms",
                body: hardware,
                tags: ["3.0-hardware"]
            ),
            BlueprintNote(
                title: "Unfiled Scratch Note",
                body: NSAttributedString(
                    string: "Drop this into a project when it has a home.",
                    attributes: NSAttributedString.editorDefaultAttributes()
                )
            )
        ]
        selectedNoteID = notes.first?.id
        folderScope = .folder(aPlus.id)
    }

    private func scheduleSave() {
        let archive = BlueprintArchive(
            folders: folders,
            notes: notes,
            selectedNoteID: selectedNoteID,
            selectedFolderID: selectedFolderID
        )
        let storageURL = storageURL

        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let data = try JSONEncoder.blueprint.encode(archive)
                try FileManager.default.createDirectory(
                    at: storageURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: storageURL, options: .atomic)
            } catch {
                assertionFailure("MicroBlueprint save failed: \(error)")
            }
        }
    }

    private func uniqueName(base: String, existing: [String]) -> String {
        guard existing.contains(base) else { return base }
        var counter = 2
        while existing.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    private static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("MicroBlueprint", isDirectory: true)
            .appendingPathComponent("blueprint-data.json")
    }
}

private extension JSONEncoder {
    static var blueprint: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var blueprint: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
