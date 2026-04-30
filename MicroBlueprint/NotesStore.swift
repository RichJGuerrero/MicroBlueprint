import AppKit
import Combine
import Foundation

enum FolderScope: Equatable {
    case all
    case unfiled
    case folder(UUID)
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

    private let storageURL: URL
    private var saveTask: Task<Void, Never>?

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        load()
    }

    var selectedNote: BlueprintNote? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    var selectedFolderID: UUID? {
        if case .folder(let id) = folderScope {
            return id
        }
        return nil
    }

    var filteredNotes: [BlueprintNote] {
        let scoped = notes.filter { note in
            switch folderScope {
            case .all:
                true
            case .unfiled:
                note.folderID == nil
            case .folder(let folderID):
                note.folderID == folderID
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
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var selectedAttributedBody: NSAttributedString {
        selectedNote?.attributedBody ?? NSAttributedString(string: "", attributes: NSAttributedString.editorDefaultAttributes())
    }

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

    @discardableResult
    func createNote(title rawTitle: String? = nil, in folderID: UUID? = nil) -> UUID {
        let targetFolderID = folderID ?? selectedFolderID
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
        updateNote(noteID) { note in
            note.title = rawTitle.nonEmptyTrimmed ?? "Untitled Note"
        }
    }

    func updateSelectedBody(_ attributedString: NSAttributedString) {
        guard let selectedNoteID else { return }
        updateNote(selectedNoteID) { note in
            note.bodyRTF = attributedString.rtfData()
        }
    }

    func moveNote(_ noteID: UUID, to folderID: UUID?) {
        updateNote(noteID) { note in
            note.folderID = folderID
        }
    }

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
                "• Test the theory, then document findings.",
                "",
                "Use highlights for command names, port numbers, and exam traps."
            ]
        )

        let hardware = NSAttributedString(
            markdownishSample: "Hardware Quick Review",
            lines: [
                "RAM, storage, power, and thermal symptoms often overlap.",
                "Keep notes atomic enough to review quickly before practice tests."
            ]
        )

        folders = [aPlus, general]
        notes = [
            BlueprintNote(folderID: aPlus.id, title: "Troubleshooting Methodology", body: troubleshooting),
            BlueprintNote(folderID: aPlus.id, title: "Hardware Symptoms", body: hardware),
            BlueprintNote(title: "Unfiled Scratch Note", body: NSAttributedString(string: "Drop this into a project when it has a home.", attributes: NSAttributedString.editorDefaultAttributes()))
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
        while existing.contains("\(base) \(counter)") {
            counter += 1
        }
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
