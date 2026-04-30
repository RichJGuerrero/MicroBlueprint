import SwiftUI

@main
struct MicroBlueprintApp: App {
    @StateObject private var store = NotesStore()
    @StateObject private var editorController = EditorController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(editorController)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Note") {
                    store.createNote()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("New Project") {
                    store.createFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("Editor") {
                Button("Bold") { editorController.bold() }
                    .keyboardShortcut("b", modifiers: [.command])
                Button("Italic") { editorController.italic() }
                    .keyboardShortcut("i", modifiers: [.command])
                Button("Underline") { editorController.underline() }
                    .keyboardShortcut("u", modifiers: [.command])
                Button("Highlight") { editorController.highlight() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Menu("Highlight Color") {
                    ForEach(HighlightColor.allCases) { color in
                        Button(color.title) {
                            editorController.selectHighlightColor(color)
                        }
                    }
                }
                Divider()
                Button("Toggle Study Mode") {
                    store.studyMode.toggle()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
