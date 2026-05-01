import AppKit
import Combine

enum HighlightColor: String, CaseIterable, Identifiable {
    case yellow
    case green
    case blue
    case pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .pink: "Pink"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow:
            NSColor.systemYellow.withAlphaComponent(0.45)
        case .green:
            NSColor.systemGreen.withAlphaComponent(0.35)
        case .blue:
            NSColor.systemBlue.withAlphaComponent(0.30)
        case .pink:
            NSColor.systemPink.withAlphaComponent(0.35)
        }
    }
}

enum BulletStyle: String, CaseIterable, Identifiable {
    case bullet
    case dash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bullet: "Bullet"
        case .dash: "Dash"
        }
    }

    var marker: String {
        switch self {
        case .bullet: "• "
        case .dash: "- "
        }
    }

    var opposite: BulletStyle {
        switch self {
        case .bullet: .dash
        case .dash: .bullet
        }
    }
}

@MainActor
final class EditorController: ObservableObject {
    weak var textView: NSTextView?
    @Published var activeHighlightColor: HighlightColor = .yellow
    @Published var activeBulletStyle: BulletStyle = .bullet

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
        toggleHighlight(activeHighlightColor)
    }

    func selectHighlightColor(_ color: HighlightColor) {
        activeHighlightColor = color
    }

    func selectBulletStyle(_ style: BulletStyle) {
        activeBulletStyle = style
    }

    func applyHighlight(_ color: HighlightColor) {
        activeHighlightColor = color
        applyHighlightColor(color)
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

    private func applyHighlightColor(_ color: HighlightColor) {
        guard let textView = editableTextView(), let storage = textView.textStorage else { return }
        let range = effectiveSelection(in: textView)
        guard range.length > 0 else { return }

        applyStorageEdit(to: textView, range: range) {
            storage.removeAttribute(.backgroundColor, range: range)
            storage.addAttribute(.backgroundColor, value: color.nsColor, range: range)
        }
    }

    private func toggleHighlight(_ color: HighlightColor) {
        guard let textView = editableTextView(), let storage = textView.textStorage else { return }
        let range = effectiveSelection(in: textView)
        guard range.length > 0 else { return }

        let shouldRemove = storage.rangeIsUniformlyHighlighted(range, with: color.nsColor)
        applyStorageEdit(to: textView, range: range) {
            if shouldRemove {
                storage.removeAttribute(.backgroundColor, range: range)
            } else {
                storage.removeAttribute(.backgroundColor, range: range)
                storage.addAttribute(.backgroundColor, value: color.nsColor, range: range)
            }
        }
    }

    func toggleBullets() {
        toggleBullets(activeBulletStyle)
    }

    func toggleBullets(_ style: BulletStyle) {
        activeBulletStyle = style
        guard let textView = editableTextView(), let storage = textView.textStorage else { return }
        let nsString = textView.string as NSString
        let selectedRange = textView.selectedRange()
        let lineRange = nsString.lineRange(for: selectedRange)
        let selectedLines = storage.attributedSubstring(from: lineRange)
        let mutable = NSMutableAttributedString(attributedString: selectedLines)
        let mutableString = mutable.string as NSString

        var lineStarts: [Int] = []
        var cursor = 0
        repeat {
            lineStarts.append(cursor)
            guard cursor < mutableString.length else { break }
            let line = mutableString.lineRange(for: NSRange(location: cursor, length: 0))
            cursor = NSMaxRange(line)
        } while cursor < mutableString.length

        let currentLineStart = selectedRange.location - lineRange.location
        let currentLineInfo = bulletInfo(in: mutableString, at: max(0, currentLineStart))
        let allUsingStyle = !lineStarts.isEmpty && lineStarts.allSatisfy { start in
            bulletInfo(in: mutableString, at: start)?.style == style
        }

        for start in lineStarts.reversed() {
            let info = bulletInfo(in: mutableString, at: start)
            if allUsingStyle, let info {
                mutable.deleteCharacters(in: info.markerRange)
            } else if let info {
                mutable.replaceCharacters(in: info.markerRange, with: style.marker)
            } else {
                let insertionPoint = bulletInsertionPoint(in: mutableString, at: start)
                let attributes = insertionPoint < mutable.length
                    ? mutable.attributes(at: insertionPoint, effectiveRange: nil)
                    : NSAttributedString.editorDefaultAttributes()
                mutable.insert(NSAttributedString(string: style.marker, attributes: attributes), at: insertionPoint)
            }
        }

        guard textView.shouldChangeText(in: lineRange, replacementString: mutable.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: lineRange, with: mutable)
        storage.endEditing()
        textView.didChangeText()

        let selection: NSRange
        if selectedRange.length == 0 {
            let offset: Int
            if allUsingStyle, let currentLineInfo {
                offset = selectedRange.location - lineRange.location > currentLineInfo.markerRange.location
                    ? -min(style.marker.count, selectedRange.location - lineRange.location - currentLineInfo.markerRange.location)
                    : 0
            } else if currentLineInfo == nil {
                offset = style.marker.count
            } else {
                offset = 0
            }
            selection = NSRange(location: max(lineRange.location, selectedRange.location + offset), length: 0)
        } else {
            selection = NSRange(location: lineRange.location, length: mutable.length)
        }
        restoreSelection(selection, in: textView)
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

    private func bulletInfo(in string: NSString, at lineStart: Int) -> (markerRange: NSRange, style: BulletStyle)? {
        let insertionPoint = bulletInsertionPoint(in: string, at: lineStart)
        for style in BulletStyle.allCases {
            let markerLength = style.marker.count
            guard insertionPoint + markerLength <= string.length else { continue }
            if string.substring(with: NSRange(location: insertionPoint, length: markerLength)) == style.marker {
                return (NSRange(location: insertionPoint, length: markerLength), style)
            }
        }
        return nil
    }

    private func bulletInsertionPoint(in string: NSString, at lineStart: Int) -> Int {
        var location = lineStart
        while location < string.length {
            let character = string.character(at: location)
            if character == 32 || character == 9 {
                location += 1
            } else {
                break
            }
        }
        return location
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
    func rangeIsUniformlyHighlighted(_ range: NSRange, with color: NSColor) -> Bool {
        var isUniform = range.length > 0
        enumerateAttribute(.backgroundColor, in: range) { value, _, stop in
            guard let runColor = value as? NSColor,
                  runColor.isVisuallyEqual(to: color) else {
                isUniform = false
                stop.pointee = true
                return
            }
        }
        return isUniform
    }

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

private extension NSColor {
    func isVisuallyEqual(to other: NSColor) -> Bool {
        guard let lhs = usingColorSpace(.sRGB),
              let rhs = other.usingColorSpace(.sRGB) else {
            return isEqual(other)
        }

        let tolerance = 0.01
        return abs(lhs.redComponent - rhs.redComponent) < tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) < tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) < tolerance
            && abs(lhs.alphaComponent - rhs.alphaComponent) < tolerance
    }
}
