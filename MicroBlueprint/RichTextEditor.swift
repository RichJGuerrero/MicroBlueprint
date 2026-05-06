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

        // Spell and grammar checking — native red/green underlines.
        // Autocorrect is intentionally left OFF so the app never silently rewrites notes.
        // The retroactive scan of already-loaded text happens in viewDidMoveToWindow,
        // once the view is attached to a window and the text system is fully ready.
        textView.isContinuousSpellCheckingEnabled = isEditable
        textView.isGrammarCheckingEnabled = isEditable
        textView.isAutomaticSpellingCorrectionEnabled = false

        scrollView.documentView = textView
        editorController.textView = textView

        // Keep the cursor at least 80 pt above the bottom of the visible area.
        // NSScrollView.contentInsets shrinks the clip rectangle so that
        // scrollRangeToVisible treats the last 80 pt as out-of-bounds and
        // automatically scrolls up to compensate — no extra delegate work needed.
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 80, right: 0)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        editorController.textView = textView
        (textView as? FocusableTextView)?.editorController = editorController

        // Keep edit state in sync. Track whether spell checking was previously active
        // so we know when to run a retroactive scan after re-entering edit mode.
        let wasSpellCheckEnabled = textView.isContinuousSpellCheckingEnabled
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isContinuousSpellCheckingEnabled = isEditable
        textView.isGrammarCheckingEnabled = isEditable

        if !context.coordinator.isUpdatingFromTextView,
           textView.attributedString().isEqual(to: attributedText) == false {
            let selection = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedText)
            textView.setSelectedRange(NSRange(
                location: min(selection.location, attributedText.length),
                length: min(selection.length, max(0, attributedText.length - min(selection.location, attributedText.length)))
            ))
            // New note loaded — run a full retroactive scan so existing content gets underlines.
            if isEditable {
                DispatchQueue.main.async { textView.checkTextInDocument(nil) }
            }
        } else if isEditable && !wasSpellCheckEnabled {
            // Returning from Study Mode — restore underlines on the current note.
            DispatchQueue.main.async { textView.checkTextInDocument(nil) }
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
            // Highlight is a deliberate selection-based action; the cursor should never
            // carry it forward when it moves into or out of highlighted text.
            if textView.typingAttributes[.backgroundColor] != nil {
                var attrs = textView.typingAttributes
                attrs.removeValue(forKey: .backgroundColor)
                textView.typingAttributes = attrs
            }
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The first time this view lands in a window, run a full spell/grammar scan
        // so text that was loaded before the window existed gets its underlines.
        guard window != nil, isContinuousSpellCheckingEnabled else { return }
        checkTextInDocument(nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // Highlight must never bleed into freshly typed characters or newlines.
        // NSTextView sets typingAttributes from the text immediately before the
        // cursor, so if that text is highlighted the next character would inherit
        // the background colour. Strip it here, before the character lands.
        if typingAttributes[.backgroundColor] != nil {
            var attrs = typingAttributes
            attrs.removeValue(forKey: .backgroundColor)
            typingAttributes = attrs
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// Ensures the cursor is never flush with the bottom of the visible area.
    /// The 80 pt contentInsets.bottom handles most cases; this catches edge cases
    /// like the first keypress on a very long note that hasn't scrolled yet.
    override func scrollRangeToVisible(_ range: NSRange) {
        super.scrollRangeToVisible(range)
        guard let scrollView = enclosingScrollView,
              let layoutManager,
              let textContainer else { return }

        let safeLen = textStorage?.length ?? 0
        let loc = min(range.location, safeLen)
        let len = min(range.length, max(0, safeLen - loc))
        guard loc != NSNotFound else { return }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: loc, length: len),
            actualCharacterRange: nil
        )
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let o = textContainerOrigin
        let cursorBottom = glyphRect.maxY + o.y

        let visible = scrollView.documentVisibleRect
        let buffer: CGFloat = 80
        if cursorBottom + buffer > visible.maxY {
            let newY = max(0, cursorBottom + buffer - visible.height)
            enclosingScrollView?.documentView?.scroll(NSPoint(x: 0, y: newY))
        }
    }

    override func keyDown(with event: NSEvent) {
        if shouldNestBulletList(for: event) {
            return
        }

        if shouldContinueBulletList(for: event) {
            return
        }

        if shouldUnNestBulletList(for: event) {
            return
        }

        super.keyDown(with: event)
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
        addBulletMenu(to: menu)

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

    private func addBulletMenu(to menu: NSMenu) {
        let bulletItem = NSMenuItem(title: "Bullet List", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Bullet List")

        for style in BulletStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(contextApplyBulletStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.isEnabled = isEditable
            submenu.addItem(item)
        }

        bulletItem.submenu = submenu
        bulletItem.isEnabled = isEditable
        menu.addItem(bulletItem)
    }

    private func prepareForContextAction() {
        window?.makeFirstResponder(self)
        editorController?.textView = self
    }

    private func shouldContinueBulletList(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isEditable,
              modifiers.isDisjoint(with: [.command, .control, .option]),
              event.charactersIgnoringModifiers == "\r",
              let textStorage,
              let bulletLine = bulletLineInfo(at: selectedRange().location) else {
            return false
        }

        let selection = selectedRange()
        let attributes: [NSAttributedString.Key: Any]
        if selection.location > 0 {
            attributes = textStorage.attributes(at: selection.location - 1, effectiveRange: nil)
        } else {
            attributes = typingAttributes
        }

        let insertedText = NSAttributedString(
            string: "\n\(bulletLine.indentation)\(bulletLine.style.marker)",
            attributes: attributes
        )
        guard shouldChangeText(in: selection, replacementString: insertedText.string) else {
            return true
        }

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: selection, with: insertedText)
        textStorage.endEditing()
        didChangeText()
        setSelectedRange(NSRange(location: selection.location + insertedText.length, length: 0))
        return true
    }

    private func shouldNestBulletList(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isEditable,
              modifiers.isEmpty,
              event.charactersIgnoringModifiers == "\t",
              selectedRange().length == 0,
              let textStorage,
              let bulletLine = bulletLineInfo(at: selectedRange().location) else {
            return false
        }

        let nestedStyle = editorController?.activeBulletStyle.opposite ?? bulletLine.style.opposite
        let replacementRange = NSRange(
            location: bulletLine.lineRange.location,
            length: NSMaxRange(bulletLine.markerRange) - bulletLine.lineRange.location
        )
        let replacementString = "\(bulletLine.indentation)    \(nestedStyle.marker)"
        let attributes = textStorage.attributes(at: bulletLine.markerRange.location, effectiveRange: nil)
        let replacementText = NSAttributedString(string: replacementString, attributes: attributes)

        guard shouldChangeText(in: replacementRange, replacementString: replacementString) else {
            return true
        }

        let selection = selectedRange()
        let offset = replacementText.length - replacementRange.length
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: replacementRange, with: replacementText)
        textStorage.endEditing()
        didChangeText()
        setSelectedRange(NSRange(location: selection.location + max(0, offset), length: 0))
        return true
    }

    /// Backspace at the typing position of an indented bullet snaps back one indentation
    /// level instead of requiring the user to delete characters one by one.
    ///
    /// Trigger conditions:
    ///   • Plain Backspace (no ⌘ / ⌥ / ⌃ modifier — those have their own delete semantics)
    ///   • Cursor is a caret (no selection)
    ///   • The current line is an indented bullet (at least one indentation level)
    ///   • The caret sits exactly at the end of the indent + marker prefix
    ///     (i.e. the "typing position" — nothing has been typed on this line yet,
    ///      or the user has moved the cursor back to the very start of the content area)
    private func shouldUnNestBulletList(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isEditable,
              modifiers.isDisjoint(with: [.command, .control, .option]),
              event.keyCode == 51,             // Backspace key
              selectedRange().length == 0,     // caret, not a selection
              let textStorage,
              let bulletLine = bulletLineInfo(at: selectedRange().location),
              !bulletLine.indentation.isEmpty  // must be a nested (indented) bullet
        else { return false }

        // Only intercept when the caret is exactly at the end of the indent+marker —
        // i.e. nothing has been typed yet on this line.
        let markerEnd = NSMaxRange(bulletLine.markerRange)
        guard selectedRange().location == markerEnd else { return false }

        // Step back one indentation level (remove up to 4 spaces from the end of the
        // indentation string, matching what shouldNestBulletList adds).
        let trimCount = min(4, bulletLine.indentation.count)
        let parentIndent = String(bulletLine.indentation.dropLast(trimCount))

        // Look up what bullet style the parent indentation level is actually using,
        // so • lists un-nest to • and - lists un-nest to -.
        let parentStyle = bulletStyle(forIndentation: parentIndent) ?? bulletLine.style
        let newPrefix = "\(parentIndent)\(parentStyle.marker)"

        // Replace the entire indent+marker span with the shorter parent-level prefix.
        let replacementRange = NSRange(
            location: bulletLine.lineRange.location,
            length: markerEnd - bulletLine.lineRange.location
        )
        let attributes = textStorage.attributes(
            at: bulletLine.markerRange.location, effectiveRange: nil
        )
        let replacementText = NSAttributedString(string: newPrefix, attributes: attributes)

        guard shouldChangeText(in: replacementRange, replacementString: newPrefix) else {
            return true
        }

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: replacementRange, with: replacementText)
        textStorage.endEditing()
        didChangeText()

        // Land the caret right after the new (shorter) marker.
        setSelectedRange(NSRange(
            location: bulletLine.lineRange.location + newPrefix.count,
            length: 0
        ))
        return true
    }

    /// Scans the document outward from the current cursor position to find the first
    /// bullet line whose indentation exactly matches `indentation`, and returns its style.
    /// Searches backwards first (the parent is almost always above), then forwards.
    /// Returns nil if no matching bullet line exists (caller should fall back to a default).
    private func bulletStyle(forIndentation indentation: String) -> BulletStyle? {
        let nsString = string as NSString
        let cursorLoc = selectedRange().location

        // ── Search backwards ──────────────────────────────────────────────────
        var searchLoc = cursorLoc
        while searchLoc > 0 {
            // Step to the start of the previous line.
            let prevLineRange = nsString.lineRange(for: NSRange(location: searchLoc - 1, length: 0))
            if let info = bulletLineInfo(at: prevLineRange.location),
               info.indentation == indentation {
                return info.style
            }
            if prevLineRange.location == 0 { break }
            searchLoc = prevLineRange.location
        }

        // ── Search forwards (fallback) ────────────────────────────────────────
        searchLoc = cursorLoc
        while searchLoc < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: searchLoc, length: 0))
            if let info = bulletLineInfo(at: lineRange.location),
               info.indentation == indentation {
                return info.style
            }
            let next = NSMaxRange(lineRange)
            if next <= searchLoc { break }   // guard against zero-length line loops
            searchLoc = next
        }

        return nil
    }

    private struct BulletLineInfo {
        let lineRange: NSRange
        let indentation: String
        let markerRange: NSRange
        let style: BulletStyle
    }

    private func bulletLineInfo(at location: Int) -> BulletLineInfo? {
        let nsString = string as NSString
        guard nsString.length > 0 else { return nil }

        let safeLocation = min(location, nsString.length)
        let lineRange = nsString.lineRange(for: NSRange(location: safeLocation, length: 0))
        var markerLocation = lineRange.location

        while markerLocation < NSMaxRange(lineRange), markerLocation < nsString.length {
            let character = nsString.character(at: markerLocation)
            if character == 32 || character == 9 {
                markerLocation += 1
            } else {
                break
            }
        }

        let indentationLength = markerLocation - lineRange.location
        let indentation = indentationLength > 0
            ? nsString.substring(with: NSRange(location: lineRange.location, length: indentationLength))
            : ""

        for style in BulletStyle.allCases {
            let markerLength = style.marker.count
            guard markerLocation + markerLength <= nsString.length else { continue }
            if nsString.substring(with: NSRange(location: markerLocation, length: markerLength)) == style.marker {
                return BulletLineInfo(
                    lineRange: lineRange,
                    indentation: indentation,
                    markerRange: NSRange(location: markerLocation, length: markerLength),
                    style: style
                )
            }
        }

        return nil
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

    @objc private func contextApplyBulletStyle(_ sender: NSMenuItem) {
        prepareForContextAction()
        guard let rawValue = sender.representedObject as? String,
              let style = BulletStyle(rawValue: rawValue) else { return }
        editorController?.toggleBullets(style)
    }
}
