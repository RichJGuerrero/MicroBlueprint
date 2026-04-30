import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var editorController: EditorController
    @AppStorage("MicroBlueprint.leftPanelWidth") private var leftPanelWidth = 300.0
    @AppStorage("MicroBlueprint.rightPanelWidth") private var rightPanelWidth = 260.0

    var body: some View {
        VStack(spacing: 0) {
            TopBar()

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if store.showLeftPanel {
                        SidebarView()
                            .frame(width: clampedLeftWidth(in: geometry.size.width))
                            .background(.regularMaterial)

                        ResizeHandle(width: $leftPanelWidth, side: .left, totalWidth: geometry.size.width)
                    }

                    EditorShell()
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))

                    if store.showRightPanel {
                        ResizeHandle(width: $rightPanelWidth, side: .right, totalWidth: geometry.size.width)

                        InspectorView()
                            .frame(width: clampedRightWidth(in: geometry.size.width))
                            .background(.regularMaterial)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            editorController.focusEditor()
        }
    }

    private func clampedLeftWidth(in totalWidth: CGFloat) -> CGFloat {
        min(max(220, leftPanelWidth), max(220, totalWidth * 0.44))
    }

    private func clampedRightWidth(in totalWidth: CGFloat) -> CGFloat {
        min(max(210, rightPanelWidth), max(210, totalWidth * 0.36))
    }
}

private struct TopBar: View {
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var editorController: EditorController

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.showLeftPanel.toggle()
            } label: {
                Image(systemName: store.showLeftPanel ? "sidebar.left" : "sidebar.leading")
            }
            .help("Toggle left panel")

            Button {
                store.showRightPanel.toggle()
            } label: {
                Image(systemName: store.showRightPanel ? "sidebar.right" : "sidebar.trailing")
            }
            .help("Toggle right panel")

            Divider()
                .frame(height: 20)

            Button {
                store.createNote()
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
            .help("Create note")

            Button {
                store.deleteSelectedNote()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(store.selectedNote == nil)
            .help("Delete note")

            Divider()
                .frame(height: 20)

            editorButton("bold", help: "Bold") { editorController.bold() }
            editorButton("italic", help: "Italic") { editorController.italic() }
            editorButton("underline", help: "Underline") { editorController.underline() }
            editorButton("list.bullet", help: "Bullet list") { editorController.toggleBullets() }
            editorButton("textformat.size", help: "Heading") { editorController.heading() }
            editorButton("highlighter", help: "Highlight") { editorController.highlight() }

            Spacer(minLength: 16)

            Picker("", selection: $store.studyMode) {
                Text("Edit").tag(false)
                Text("Study").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 132)
            .help("Edit or study mode")
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func editorButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 24, height: 24)
        }
        .help(help)
        .disabled(store.studyMode || store.selectedNote == nil)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MicroBlueprint")
                    .font(.headline)
                Spacer()
                Button {
                    store.createFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Create project")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SearchField(text: $store.searchQuery)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FolderList()
                    NoteList()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
        }
    }
}

private struct FolderList: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionHeader("Projects")

            ScopeButton(title: "All Notes", systemImage: "tray.full", scope: .all, count: store.notes.count)
            ScopeButton(title: "Unfiled", systemImage: "tray", scope: .unfiled, count: store.notes.filter { $0.folderID == nil }.count)
                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                    handleDrop(providers, folderID: nil)
                }

            ForEach(store.folders) { folder in
                FolderRow(folder: folder)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], folderID: UUID?) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            let text = (item as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? item as? String
            guard let text, let noteID = UUID(uuidString: text) else { return }
            Task { @MainActor in
                store.moveNote(noteID, to: folderID)
            }
        }
        return true
    }
}

private struct FolderRow: View {
    @EnvironmentObject private var store: NotesStore
    let folder: BlueprintFolder

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            TextField("Project", text: Binding(
                get: { folder.name },
                set: { store.renameFolder(folder.id, to: $0) }
            ))
            .textFieldStyle(.plain)

            Text("\(store.notes.filter { $0.folderID == folder.id }.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(store.folderScope == .folder(folder.id) ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectFolderScope(.folder(folder.id))
        }
        .contextMenu {
            Button("New Note Here") { store.createNote(in: folder.id) }
            Button("Delete Project") { store.deleteFolder(folder.id) }
        }
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let text = (item as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? item as? String
                guard let text, let noteID = UUID(uuidString: text) else { return }
                Task { @MainActor in
                    store.moveNote(noteID, to: folder.id)
                }
            }
            return true
        }
    }
}

private struct ScopeButton: View {
    @EnvironmentObject private var store: NotesStore
    let title: String
    let systemImage: String
    let scope: FolderScope
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(store.folderScope == scope ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectFolderScope(scope)
        }
    }
}

private struct NoteList: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionHeader("Notes")
                Spacer()
                Button {
                    store.createNote()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create note")
            }

            ForEach(store.filteredNotes) { note in
                NoteRow(note: note)
            }

            if store.filteredNotes.isEmpty {
                Text("No notes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
            }
        }
    }
}

private struct NoteRow: View {
    @EnvironmentObject private var store: NotesStore
    let note: BlueprintNote

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            HStack {
                Text(note.plainBody.nonEmptyPreview)
                    .lineLimit(1)
                Spacer()
                Text(note.updatedAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(store.selectedNoteID == note.id ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectNote(note.id)
        }
        .onDrag {
            NSItemProvider(object: note.id.uuidString as NSString)
        }
        .contextMenu {
            Menu("Move To") {
                Button("Unfiled") { store.moveNote(note.id, to: nil) }
                ForEach(store.folders) { folder in
                    Button(folder.name) { store.moveNote(note.id, to: folder.id) }
                }
            }
            Button("Delete Note") { store.deleteNote(note.id) }
        }
    }
}

private struct EditorShell: View {
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var editorController: EditorController

    var body: some View {
        VStack(spacing: 0) {
            if let note = store.selectedNote {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("Untitled Note", text: Binding(
                        get: { note.title },
                        set: { store.renameNote(note.id, to: $0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .semibold))

                    Text(store.folderName(for: note.folderID))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 6)

                RichTextEditor(
                    attributedText: Binding(
                        get: { store.selectedAttributedBody },
                        set: { store.updateSelectedBody($0) }
                    ),
                    isEditable: !store.studyMode,
                    editorController: editorController
                )
            } else {
                ContentUnavailableView {
                    Label("No Note Selected", systemImage: "doc.text")
                } description: {
                    Text("Create a note or choose one from the left panel.")
                } actions: {
                    Button("New Note") {
                        store.createNote()
                    }
                }
            }
        }
    }
}

private struct InspectorView: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Inspector")
                .font(.headline)

            if let note = store.selectedNote {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Project", selection: Binding(
                        get: { note.folderID },
                        set: { store.moveNote(note.id, to: $0) }
                    )) {
                        Text("Unfiled").tag(UUID?.none)
                        ForEach(store.folders) { folder in
                            Text(folder.name).tag(Optional(folder.id))
                        }
                    }
                    .labelsHidden()
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(title: "Created", value: note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    InfoRow(title: "Updated", value: note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    InfoRow(title: "Words", value: "\(wordCount(note.plainBody))")
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Study Tools")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button {
                        store.studyMode.toggle()
                    } label: {
                        Label(store.studyMode ? "Return to Edit" : "Open Study View", systemImage: store.studyMode ? "pencil" : "book")
                    }
                    .buttonStyle(.bordered)

                    // Future expansion point: AI summarization, transcript import,
                    // flashcard creation, and quiz generation can attach to the
                    // selected note here without changing the editor surface.
                }
            } else {
                Text("Select a note to see details.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(18)
    }

    private func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }
}

private enum ResizeSide {
    case left
    case right
}

private struct ResizeHandle: View {
    @Binding var width: Double
    let side: ResizeSide
    let totalWidth: CGFloat
    @State private var startWidth = 0.0

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.65))
            .frame(width: 5)
            .overlay {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.001))
                    .frame(width: 12)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if startWidth == 0 {
                            startWidth = width
                        }
                        let delta = side == .left ? value.translation.width : -value.translation.width
                        width = min(max(210, startWidth + delta), totalWidth * 0.46)
                    }
                    .onEnded { _ in
                        startWidth = 0
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search notes", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
    }
}

private extension String {
    var nonEmptyPreview: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Empty note" : trimmed
    }
}
