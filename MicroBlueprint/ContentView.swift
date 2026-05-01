import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root layout

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
        // App-wide study-mode toggle shortcut (⌘⌥S)
        .background(
            Button("") { store.studyMode.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .opacity(0)
                .frame(width: 0, height: 0)
        )
    }

    private func clampedLeftWidth(in totalWidth: CGFloat) -> CGFloat {
        min(max(220, leftPanelWidth), max(220, totalWidth * 0.44))
    }

    private func clampedRightWidth(in totalWidth: CGFloat) -> CGFloat {
        min(max(210, rightPanelWidth), max(210, totalWidth * 0.36))
    }
}

// MARK: - Top bar

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

            Divider().frame(height: 20)

            Button {
                store.createNote()
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("New Note (⌘N)")

            Button {
                store.deleteSelectedNote()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(store.selectedNote == nil)
            .help("Delete note")

            Divider().frame(height: 20)

            // Bold / Italic / Underline — system shortcuts (⌘B / ⌘I / ⌘U) already handled by NSTextView
            editorButton("bold",      help: "Bold (⌘B)")      { editorController.bold() }
            editorButton("italic",    help: "Italic (⌘I)")    { editorController.italic() }
            editorButton("underline", help: "Underline (⌘U)") { editorController.underline() }

            // Heading — ⌘⌥H
            Button(action: { editorController.heading() }) {
                Image(systemName: "textformat.size").frame(width: 24, height: 24)
            }
            .keyboardShortcut("h", modifiers: [.command, .option])
            .help("Heading (⌘⌥H)")
            .disabled(store.studyMode || store.selectedNote == nil)

            // Bullets — ⌘⌥L
            Button(action: { editorController.toggleBullets() }) {
                Image(systemName: "list.bullet").frame(width: 24, height: 24)
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .help("Bullet list (⌘⌥L)")
            .disabled(store.studyMode || store.selectedNote == nil)

            // Highlight + color picker — ⌘⇧H
            HStack(spacing: 2) {
                Button(action: { editorController.highlight() }) {
                    Image(systemName: "highlighter").frame(width: 24, height: 24)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .help("Highlight (⌘⇧H)")

                HighlightColorMenu()
            }
            .disabled(store.studyMode || store.selectedNote == nil)

            Spacer(minLength: 16)

            Picker("", selection: $store.studyMode) {
                Text("Edit").tag(false)
                Text("Study").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 132)
            .help("Edit or study mode (⌘⌥S)")
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func editorButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).frame(width: 24, height: 24)
        }
        .help(help)
        .disabled(store.studyMode || store.selectedNote == nil)
    }
}

// MARK: - Highlight color picker

private struct HighlightColorMenu: View {
    @EnvironmentObject private var editorController: EditorController

    var body: some View {
        Menu {
            ForEach(HighlightColor.allCases) { color in
                Button {
                    editorController.selectHighlightColor(color)
                } label: {
                    Label(
                        color.title,
                        systemImage: color == editorController.activeHighlightColor ? "checkmark.circle.fill" : "circle.fill"
                    )
                }
            }
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(Color(nsColor: editorController.activeHighlightColor.nsColor))
                    .frame(width: 9, height: 9)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .frame(width: 25, height: 24)
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Choose highlight color")
    }
}

// MARK: - Sidebar

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
                    TagList()
                    NoteList()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
        }
    }
}

// MARK: - Folder / scope list

private struct FolderList: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionHeader("Library")

            ScopeButton(
                title: "All Notes",
                systemImage: "tray.full",
                scope: .all,
                count: store.notes.count
            )

            // Due for Review scope — only show when there are reviewable notes
            if store.notes.count > 0 {
                ReviewDueScopeButton()
            }

            ScopeButton(
                title: "Unfiled",
                systemImage: "tray",
                scope: .unfiled,
                count: store.notes.filter { $0.folderID == nil }.count
            )
            .onDrop(of: [.plainText], isTargeted: nil) { providers in
                handleDrop(providers, folderID: nil)
            }

            if !store.folders.isEmpty {
                SectionHeader("Projects")
                    .padding(.top, 6)
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
            Task { @MainActor in store.moveNote(noteID, to: folderID) }
        }
        return true
    }
}

private struct ReviewDueScopeButton: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(store.folderScope == .reviewDue ? Color.primary : Color.orange)
            Text("Due for Review")
            Spacer()
            if store.reviewDueCount > 0 {
                Text("\(store.reviewDueCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(store.folderScope == .reviewDue ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { store.selectFolderScope(.reviewDue) }
    }
}

private struct FolderRow: View {
    @EnvironmentObject private var store: NotesStore
    let folder: BlueprintFolder

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder").foregroundStyle(.secondary)
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
        .onTapGesture { store.selectFolderScope(.folder(folder.id)) }
        .contextMenu {
            Button("New Note Here") { store.createNote(in: folder.id) }
            Button("Delete Project") { store.deleteFolder(folder.id) }
        }
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let text = (item as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? item as? String
                guard let text, let noteID = UUID(uuidString: text) else { return }
                Task { @MainActor in store.moveNote(noteID, to: folder.id) }
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
            Image(systemName: systemImage).foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(store.folderScope == scope ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { store.selectFolderScope(scope) }
    }
}

// MARK: - Tag list (sidebar)

private struct TagList: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        if !store.allTags.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader("Tags")
                ForEach(store.allTags, id: \.self) { tag in
                    TagScopeButton(tag: tag)
                }
            }
        }
    }
}

private struct TagScopeButton: View {
    @EnvironmentObject private var store: NotesStore
    let tag: String

    var noteCount: Int {
        store.notes.filter { $0.tags.contains(tag) }.count
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag").foregroundStyle(.secondary)
            Text(tag).lineLimit(1)
            Spacer()
            Text("\(noteCount)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(store.folderScope == .tagged(tag) ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { store.selectFolderScope(.tagged(tag)) }
    }
}

// MARK: - Note list

private struct NoteList: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionHeader("Notes")
                Spacer()
                Button { store.createNote() } label: {
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
            HStack(spacing: 4) {
                Text(note.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                // Orange dot for overdue notes that have been reviewed before
                if note.isDueForReview, note.lastReviewedAt != nil {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            HStack {
                Text(note.smartPreview)
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
        .background(
            store.selectedNoteID == note.id
                ? Color.accentColor.opacity(0.18)
                : Color(nsColor: .controlBackgroundColor).opacity(0.35)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { store.selectNote(note.id) }
        .onDrag { NSItemProvider(object: note.id.uuidString as NSString) }
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

// MARK: - Editor shell

private struct EditorShell: View {
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var editorController: EditorController
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let note = store.selectedNote {
                // Title row
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("Untitled Note", text: Binding(
                        get: { note.title },
                        set: { store.renameNote(note.id, to: $0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .semibold))
                    .focused($titleFocused)

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

                // Reading-time banner — only in study mode, only when there's content
                if store.studyMode, note.estimatedReadMinutes > 0 {
                    HStack {
                        Spacer()
                        Label(
                            "~\(note.estimatedReadMinutes) min read · \(note.wordCount) words",
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 6)
                }

                // Editor — wrapped to support the study-mode "Mark Reviewed" overlay
                ZStack(alignment: .bottomTrailing) {
                    RichTextEditor(
                        attributedText: Binding(
                            get: { store.selectedAttributedBody },
                            set: { store.updateSelectedBody($0) }
                        ),
                        isEditable: !store.studyMode,
                        editorController: editorController
                    )

                    if store.studyMode {
                        MarkReviewedButton(note: note)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Note Selected", systemImage: "doc.text")
                } description: {
                    Text("Create a note or choose one from the left panel.")
                } actions: {
                    Button("New Note") { store.createNote() }
                }
            }
        }
        // Auto-focus title when a new note is created
        .onChange(of: store.shouldFocusTitle) { _, newValue in
            if newValue {
                titleFocused = true
                store.shouldFocusTitle = false
            }
        }
    }
}

private struct MarkReviewedButton: View {
    @EnvironmentObject private var store: NotesStore
    let note: BlueprintNote

    private var reviewedToday: Bool {
        guard let r = note.lastReviewedAt else { return false }
        return Calendar.current.isDateInToday(r)
    }

    var body: some View {
        Button {
            store.markReviewed(note.id)
        } label: {
            Label(
                reviewedToday ? "Reviewed Today" : "Mark Reviewed",
                systemImage: reviewedToday ? "checkmark.circle.fill" : "checkmark.circle"
            )
        }
        .buttonStyle(.borderedProminent)
        .tint(reviewedToday ? .green : .accentColor)
        .padding(20)
    }
}

// MARK: - Inspector

private struct InspectorView: View {
    @EnvironmentObject private var store: NotesStore
    @State private var showingQuiz = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Inspector")
                    .font(.headline)
                    .padding(.bottom, 16)

                if let note = store.selectedNote {
                    noteContent(note)
                } else {
                    Text("Select a note to see details.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $showingQuiz) {
            QuizView(notes: store.filteredNotes)
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private func noteContent(_ note: BlueprintNote) -> some View {
        // Project
        inspectorSection("Project") {
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

        Divider().padding(.vertical, 14)

        // Tags
        TagEditor(note: note)

        Divider().padding(.vertical, 14)

        // Info
        inspectorSection("Info") {
            InfoRow(title: "Created", value: note.createdAt.formatted(date: .abbreviated, time: .shortened))
            InfoRow(title: "Updated", value: note.updatedAt.formatted(date: .abbreviated, time: .shortened))
            InfoRow(title: "Words", value: "\(note.wordCount)")
            if note.estimatedReadMinutes > 0 {
                InfoRow(title: "Read time", value: "~\(note.estimatedReadMinutes) min")
            }
        }

        Divider().padding(.vertical, 14)

        // Review
        ReviewSection(note: note)

        Divider().padding(.vertical, 14)

        // Highlight legend
        HighlightLegend()

        Divider().padding(.vertical, 14)

        // Study tools
        inspectorSection("Study Tools") {
            Button {
                if !store.studyMode, let id = store.selectedNoteID {
                    store.markReviewed(id)
                }
                store.studyMode.toggle()
            } label: {
                Label(
                    store.studyMode ? "Return to Edit" : "Study View",
                    systemImage: store.studyMode ? "pencil" : "book.open"
                )
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showingQuiz = true
            } label: {
                Label("Quiz Me", systemImage: "questionmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(store.filteredNotes.isEmpty)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                exportNote(note)
            } label: {
                Label("Export as Text", systemImage: "arrow.up.doc")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func exportNote(_ note: BlueprintNote) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(note.title).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? note.plainBody.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Tag editor (Inspector)

private struct TagEditor: View {
    @EnvironmentObject private var store: NotesStore
    let note: BlueprintNote
    @State private var newTagInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !note.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(note.tags, id: \.self) { tag in
                            HStack(spacing: 3) {
                                Text(tag)
                                    .font(.caption)
                                Button {
                                    store.updateTags(note.id, tags: note.tags.filter { $0 != tag })
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            HStack {
                TextField("Add tag…", text: $newTagInput)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit { addTag() }
                if !newTagInput.isEmpty {
                    Button { addTag() } label: {
                        Image(systemName: "return")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 5))

            // A+ domain quick-add suggestions
            if newTagInput.isEmpty && note.tags.count < 3 {
                let suggestions = suggestedTags(excluding: note.tags)
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(suggestions, id: \.self) { tag in
                                Button {
                                    var updated = note.tags
                                    updated.append(tag)
                                    store.updateTags(note.id, tags: updated)
                                } label: {
                                    Text("+ \(tag)")
                                        .font(.caption2)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func addTag() {
        let tag = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !tag.isEmpty, !note.tags.contains(tag) else {
            newTagInput = ""
            return
        }
        var updated = note.tags
        updated.append(tag)
        store.updateTags(note.id, tags: updated)
        newTagInput = ""
    }

    private func suggestedTags(excluding current: [String]) -> [String] {
        let all = [
            "1.0-mobile", "2.0-networking", "3.0-hardware",
            "4.0-virtualization", "5.0-troubleshooting",
            "6.0-security", "7.0-os", "printers"
        ]
        return all.filter { !current.contains($0) }
    }
}

// MARK: - Review section (Inspector)

private struct ReviewSection: View {
    @EnvironmentObject private var store: NotesStore
    let note: BlueprintNote

    private var lastReviewedText: String {
        guard let r = note.lastReviewedAt else { return "Never" }
        if Calendar.current.isDateInToday(r) { return "Today" }
        if Calendar.current.isDateInYesterday(r) { return "Yesterday" }
        return r.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            InfoRow(title: "Last reviewed", value: lastReviewedText)

            HStack {
                Text("Interval")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(
                    "\(note.reviewInterval) day\(note.reviewInterval == 1 ? "" : "s")",
                    value: Binding(
                        get: { note.reviewInterval },
                        set: { store.updateReviewInterval(note.id, days: $0) }
                    ),
                    in: 1...30
                )
                .font(.caption)
                .fixedSize()
            }

            Button {
                store.markReviewed(note.id)
            } label: {
                let reviewedToday = note.lastReviewedAt.map { Calendar.current.isDateInToday($0) } ?? false
                Label(
                    reviewedToday ? "Reviewed Today ✓" : "Mark as Reviewed",
                    systemImage: reviewedToday ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
            .buttonStyle(.bordered)
            .tint((note.lastReviewedAt.map { Calendar.current.isDateInToday($0) } ?? false) ? .green : .accentColor)
            .font(.caption)
        }
    }
}

// MARK: - Highlight legend (Inspector)

private struct HighlightLegend: View {
    @AppStorage("MicroBlueprint.legend.yellow") private var legendYellow = ""
    @AppStorage("MicroBlueprint.legend.green")  private var legendGreen  = ""
    @AppStorage("MicroBlueprint.legend.blue")   private var legendBlue   = ""
    @AppStorage("MicroBlueprint.legend.pink")   private var legendPink   = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Highlight Legend")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Label each color so your highlights stay consistent.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            ForEach(HighlightColor.allCases) { color in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 10, height: 10)
                    TextField(color.title, text: legendBinding(for: color))
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: color.nsColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private func legendBinding(for color: HighlightColor) -> Binding<String> {
        switch color {
        case .yellow: return $legendYellow
        case .green:  return $legendGreen
        case .blue:   return $legendBlue
        case .pink:   return $legendPink
        }
    }
}

// MARK: - Quiz view

struct QuizView: View {
    @EnvironmentObject private var store: NotesStore
    @Environment(\.dismiss) private var dismiss

    let notes: [BlueprintNote]

    @State private var queue: [BlueprintNote] = []
    @State private var currentIndex = 0
    @State private var showAnswer = false
    @State private var correctCount = 0
    @State private var missedCount = 0
    @State private var finished = false

    private var currentNote: BlueprintNote? {
        currentIndex < queue.count ? queue[currentIndex] : nil
    }

    private var progress: Double {
        queue.isEmpty ? 1 : Double(currentIndex) / Double(queue.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("End Quiz") { dismiss() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Spacer()
                if !finished {
                    Text("\(min(currentIndex + 1, queue.count)) of \(queue.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .padding(.horizontal, 0)

            Spacer(minLength: 0)

            if finished {
                summaryView
            } else if let note = currentNote {
                cardView(for: note)
            } else {
                Text("No notes to quiz.")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 440, idealHeight: 520)
        .onAppear { queue = notes.shuffled() }
    }

    // MARK: Card

    @ViewBuilder
    private func cardView(for note: BlueprintNote) -> some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Text("What do you know about:")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(note.title)
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if !note.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(note.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 40)

            if showAnswer {
                ScrollView {
                    Text(note.plainBody.isEmpty ? "(No content)" : note.plainBody)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 440, alignment: .leading)
                        .padding(.horizontal, 40)
                }
                .frame(maxHeight: 180)

                HStack(spacing: 16) {
                    Button {
                        advance(note, remembered: false)
                    } label: {
                        Label("Missed it", systemImage: "xmark.circle")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button {
                        advance(note, remembered: true)
                    } label: {
                        Label("Got it", systemImage: "checkmark.circle")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .keyboardShortcut(.return, modifiers: [])
                }
            } else {
                VStack(spacing: 10) {
                    Button("Show Answer") { showAnswer = true }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.space, modifiers: [])

                    Text("Space to reveal")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: Summary

    private var summaryView: some View {
        VStack(spacing: 22) {
            let pct = queue.isEmpty ? 0 : Int(Double(correctCount) / Double(queue.count) * 100)

            Image(systemName: pct >= 80 ? "star.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(pct >= 80 ? .yellow : .accentColor)

            Text("Quiz Complete")
                .font(.title2.weight(.semibold))

            HStack(spacing: 48) {
                scoreStat(label: "Got it", value: correctCount, color: .green)
                scoreStat(label: "Missed", value: missedCount,  color: .red)
                scoreStat(label: "Score",  value: pct,          color: .primary, suffix: "%")
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(40)
    }

    private func scoreStat(label: String, value: Int, color: Color, suffix: String = "") -> some View {
        VStack(spacing: 4) {
            Text("\(value)\(suffix)")
                .font(.title.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Logic

    private func advance(_ note: BlueprintNote, remembered: Bool) {
        if remembered { correctCount += 1 } else { missedCount += 1 }
        store.markReviewed(note.id)
        showAnswer = false

        if currentIndex + 1 >= queue.count {
            finished = true
        } else {
            currentIndex += 1
        }
    }
}

// MARK: - Shared sub-views

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}

private enum ResizeSide { case left, right }

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
                        if startWidth == 0 { startWidth = width }
                        let delta = side == .left ? value.translation.width : -value.translation.width
                        width = min(max(210, startWidth + delta), totalWidth * 0.46)
                    }
                    .onEnded { _ in startWidth = 0 }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search notes", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
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
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
    }
}
