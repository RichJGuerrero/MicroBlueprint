import AppKit
import Combine

@MainActor
final class EditorController: ObservableObject {
    weak var textView: NSTextView?

    func focusEditor() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func bold() {
        toggleFontTrait(.boldFontMask)
    }

    func italic() {
        toggleFontTrait(.italicFontMask)
    }

    func underline() {
        toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue) { value in
            if let value = value as? Int {
                return value != 0
            }
            if let value = value as? NSNumber {
                return value.intValue != 0
            }
            return false
        }
    }

    func heading() {
        applyFont(size: 26, weight: .semibold)
    }

    func bodySize() {
        applyFont(size: 16, weight: .regular)
    }

    func highlight() {
        applyAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.45))
    }

    func removeHighlight() {
        guard let textView = editableTextView(), let storage = textView.textStorage else { return }
        let range = effectiveSelection(in: textView)
        guard range.length > 0 else {
            var attributes = textView.typingAttributes
            attributes.removeValue(forKey: .backgroundColor)
            textView.typingAttributes = attributes
            restoreSelection(range, in: textView)
            return
        }
        applyStorageEdit(to: textView, range: range) {
            storage.removeAttribute(.backgroundColor, range: range)
        }
    }

    func toggleBullets() {
        guard let textView = editableTextView(), let storage = textView.textStorage else { return }
        let nsString = textView.string as NSString
        let selectedRange = textView.selectedRange()
        let lineRange = nsString.lineRange(for: selectedRange)
        let selectedLines = storage.attributedSubstring(from: lineRange)
        let mutable = NSMutableAttributedString(attributedString: selectedLines)
        let mutableString = mutable.string as NSString

        var starts: [Int] = []
        var cursor = 0
        while cursor < mutableString.length {
            starts.append(cursor)
            let line = mutableString.lineRange(for: NSRange(location: cursor, length: 0))
            cursor = NSMaxRange(line)
        }

        let nonEmptyStarts = starts.filter { start in
            let line = mutableString.lineRange(for: NSRange(location: start, length: 0))
            return mutableString.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        let allBulleted = !nonEmptyStarts.isEmpty && nonEmptyStarts.allSatisfy { start in
            mutableString.substring(with: NSRange(location: start, length: min(2, mutableString.length - start))) == "• "
        }

        for start in nonEmptyStarts.reversed() {
            if allBulleted {
                mutable.deleteCharacters(in: NSRange(location: start, length: 2))
            } else {
                let attributes = start < mutable.length
                    ? mutable.attributes(at: start, effectiveRange: nil)
                    : NSAttributedString.editorDefaultAttributes()
                mutable.insert(NSAttributedString(string: "• ", attributes: attributes), at: start)
            }
        }

        guard textView.shouldChangeText(in: lineRange, replacementString: mutable.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: lineRange, with: mutable)
        storage.endEditing()
        textView.didChangeText()
        restoreSelection(NSRange(location: lineRange.location, length: mutable.length), in: textView)
    }

    private func applyFont(size: CGFloat, weight: NSFont.Weight) {
        guard let textView = editableTextView(), let storage = textView.textStorage else { return }
        let range = effectiveSelection(in: textView)

        if range.length == 0 {
            var attributes = textView.typingAttributes
            let existing = attributes[.font] as? NSFont
            attributes[.font] = sizedFont(from: existing, size: size, weight: weight)
            textView.typingAttributes = attributes
            restoreSelection(range, in: textView)
            return
        }

        let runs = fontRuns(in: storage, range: range, fallbackSize: size)
        applyStorageEdit(to: textView, range: range) {
            for (font, subrange) in runs {
                storage.addAttribute(
                    .font,
                    value: sizedFont(from: font, size: size, weight: weight),
                    range: subrange
                )
            }
        }
    }

    private func applyAttribute(_ key: NSAttributedString.Key, value: Any) {
        guard let textView = editableTextView(), let storage = textView.textStorage else { return }
        let range = effectiveSelection(in: textView)

        if range.length == 0 {
            var attributes = textView.typingAttributes
            attributes[key] = value
            textView.typingAttributes = attributes
            restoreSelection(range, in: textView)
            return
        }

        applyStorageEdit(to: textView, range: range) {
            storage.addAttribute(key, value: value, range: range)
        }
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView = editableTextView(), let storage = textView.textStorage else { return }
        let range = effectiveSelection(in: textView)

        if range.length == 0 {
            var attributes = textView.typingAttributes
            let existing = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 16)
            let hasTrait = NSFontManager.shared.traits(of: existing).contains(trait)
            attributes[.font] = convertedFont(existing, trait: trait, enabled: !hasTrait)
            textView.typingAttributes = attributes
            restoreSelection(range, in: textView)
            return
        }

        let shouldEnable = storage.range(range, containsFontTrait: trait) == false
        let runs = fontRuns(in: storage, range: range, fallbackSize: 16)
        applyStorageEdit(to: textView, range: range) {
            for (font, subrange) in runs {
                storage.addAttribute(
                    .font,
                    value: convertedFont(font, trait: trait, enabled: shouldEnable),
                    range: subrange
                )
            }
        }
    }

    private func toggleAttribute(
        _ key: NSAttributedString.Key,
        value: Any,
        isActive: (Any?) -> Bool
    ) {
        guard let textView = editableTextView(), let storage = textView.textStorage else { return }
        let range = effectiveSelection(in: textView)

        if range.length == 0 {
            var attributes = textView.typingAttributes
            if isActive(attributes[key]) {
                attributes.removeValue(forKey: key)
            } else {
                attributes[key] = value
            }
            textView.typingAttributes = attributes
            restoreSelection(range, in: textView)
            return
        }

        let shouldRemove = storage.range(range, containsAttribute: key, matching: isActive)
        applyStorageEdit(to: textView, range: range) {
            if shouldRemove {
                storage.removeAttribute(key, range: range)
            } else {
                storage.addAttribute(key, value: value, range: range)
            }
        }
    }

    private func editableTextView() -> NSTextView? {
        guard let textView, textView.isEditable else { return nil }
        return textView
    }

    private func applyStorageEdit(to textView: NSTextView, range: NSRange, edit: () -> Void) {
        guard range.length > 0,
              textView.shouldChangeText(in: range, replacementString: nil) else { return }

        let selection = textView.selectedRange()
        textView.textStorage?.beginEditing()
        edit()
        textView.textStorage?.endEditing()
        textView.didChangeText()
        restoreSelection(selection, in: textView)
    }

    private func effectiveSelection(in textView: NSTextView) -> NSRange {
        let selected = textView.selectedRange()
        if selected.length > 0 {
            return selected
        }
        return NSRange(location: selected.location, length: 0)
    }

    private func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(range.location, length)
        return NSRange(location: location, length: min(range.length, max(0, length - location)))
    }

    private func restoreSelection(_ range: NSRange, in textView: NSTextView) {
        let selection = clamped(range, to: textView.attributedString().length)
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(selection)
    }

    private func convertedFont(_ font: NSFont, trait: NSFontTraitMask, enabled: Bool) -> NSFont {
        if enabled {
            return NSFontManager.shared.convert(font, toHaveTrait: trait)
        }
        return NSFontManager.shared.convert(font, toNotHaveTrait: trait)
    }

    private func sizedFont(from font: NSFont?, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
        var sized = NSFont.systemFont(ofSize: size, weight: weight)
        if traits.contains(.boldFontMask) {
            sized = NSFontManager.shared.convert(sized, toHaveTrait: .boldFontMask)
        }
        if traits.contains(.italicFontMask) {
            sized = NSFontManager.shared.convert(sized, toHaveTrait: .italicFontMask)
        }
        return sized
    }

    private func fontRuns(
        in storage: NSTextStorage,
        range: NSRange,
        fallbackSize: CGFloat
    ) -> [(font: NSFont, range: NSRange)] {
        var runs: [(font: NSFont, range: NSRange)] = []
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            runs.append((value as? NSFont ?? NSFont.systemFont(ofSize: fallbackSize), subrange))
        }
        return runs
    }
}

private extension NSTextStorage {
    func range(_ range: NSRange, containsFontTrait trait: NSFontTraitMask) -> Bool {
        var containsTrait = true
        enumerateAttribute(.font, in: range) { value, _, stop in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: 16)
            if NSFontManager.shared.traits(of: font).contains(trait) == false {
                containsTrait = false
                stop.pointee = true
            }
        }
        return containsTrait
    }

    func range(
        _ range: NSRange,
        containsAttribute key: NSAttributedString.Key,
        matching isActive: (Any?) -> Bool
    ) -> Bool {
        var containsAttribute = true
        enumerateAttribute(key, in: range) { value, _, stop in
            if isActive(value) == false {
                containsAttribute = false
                stop.pointee = true
            }
        }
        return containsAttribute
    }
}
