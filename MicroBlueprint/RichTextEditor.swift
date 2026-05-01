import AppKit
import SwiftUI

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var isEditable: Bool
    @ObservedObject var editorController: EditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = FocusableTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.usesFontPanel = true
        textView.usesInspectorBar = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 34, height: 28)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.typingAttributes = NSAttributedString.editorDefaultAttributes()
        textView.textStorage?.setAttributedString(attributedText)
        textView.editorController = editorController

        scrollView.documentView = textView
        editorController.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        editorController.textView = textView
        (textView as? FocusableTextView)?.editorController = editorController
        textView.isEditable = isEditable
        textView.isSelectable = true

        if !context.coordinator.isUpdatingFromTextView,
           textView.attributedString().isEqual(to: attributedText) == false {
            let selection = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedText)
            textView.setSelectedRange(NSRange(
                location: min(selection.location, attributedText.length),
                length: min(selection.length, max(0, attributedText.length - min(selection.location, attributedText.length)))
            ))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var isUpdatingFromTextView = false

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.editorController.textView = textView
            isUpdatingFromTextView = true
            parent.attributedText = NSAttributedString(attributedString: textView.attributedString())
            isUpdatingFromTextView = false
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.editorController.textView = textView
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.editorController.textView = textView
        }
    }
}

private final class FocusableTextView: NSTextView {
    weak var editorController: EditorController?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)

        let menu = super.menu(for: event) ?? NSMenu()
        guard editorController != nil else { return menu }

        if menu.items.isEmpty == false {
            menu.addItem(.separator())
        }

        let hasSelection = selectedRange().length > 0
        addFormattingItem("Bold", action: #selector(contextBold), to: menu, enabled: hasSelection)
        addFormattingItem("Italic", action: #selector(contextItalic), to: menu, enabled: hasSelection)
        addFormattingItem("Underline", action: #selector(contextUnderline), to: menu, enabled: hasSelection)
        menu.addItem(.separator())
        addHighlightMenu(to: menu, enabled: hasSelection)
        menu.addItem(.separator())
        addFormattingItem("Heading", action: #selector(contextHeading), to: menu, enabled: hasSelection)
        addFormattingItem("Body Text", action: #selector(contextBodyText), to: menu, enabled: hasSelection)
        addFormattingItem("Bullet List", action: #selector(contextBullets), to: menu, enabled: hasSelection)

        return menu
    }

    private func addFormattingItem(_ title: String, action: Selector, to menu: NSMenu, enabled: Bool) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled && isEditable
        menu.addItem(item)
    }

    private func addHighlightMenu(to menu: NSMenu, enabled: Bool) {
        let highlightItem = NSMenuItem(title: "Highlight", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Highlight")

        for color in HighlightColor.allCases {
            let item = NSMenuItem(title: color.title, action: #selector(contextApplyHighlightColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = color.rawValue
            item.isEnabled = enabled && isEditable
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let removeItem = NSMenuItem(title: "Remove Highlight", action: #selector(contextRemoveHighlight), keyEquivalent: "")
        removeItem.target = self
        removeItem.isEnabled = enabled && isEditable
        submenu.addItem(removeItem)

        highlightItem.submenu = submenu
        highlightItem.isEnabled = enabled && isEditable
        menu.addItem(highlightItem)
    }

    private func prepareForContextAction() {
        window?.makeFirstResponder(self)
        editorController?.textView = self
    }

    @objc private func contextBold() {
        prepareForContextAction()
        editorController?.bold()
    }

    @objc private func contextItalic() {
        prepareForContextAction()
        editorController?.italic()
    }

    @objc private func contextUnderline() {
        prepareForContextAction()
        editorController?.underline()
    }

    @objc private func contextApplyHighlightColor(_ sender: NSMenuItem) {
        prepareForContextAction()
        guard let rawValue = sender.representedObject as? String,
              let color = HighlightColor(rawValue: rawValue) else { return }
        editorController?.applyHighlight(color)
    }

    @objc private func contextRemoveHighlight() {
        prepareForContextAction()
        editorController?.removeHighlight()
    }

    @objc private func contextHeading() {
        prepareForContextAction()
        editorController?.heading()
    }

    @objc private func contextBodyText() {
        prepareForContextAction()
        editorController?.bodySize()
    }

    @objc private func contextBullets() {
        prepareForContextAction()
        editorController?.toggleBullets()
    }
}
