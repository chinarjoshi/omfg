import UIKit

final class OrgTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()
    private let syntaxRules = OrgSyntaxRules()

    override var string: String {
        backingStore.string
    }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        let paragraphRange = (string as NSString).paragraphRange(for: editedRange)
        applyDefaultAttributes(in: paragraphRange)
        applySyntaxHighlighting(in: paragraphRange)
        super.processEditing()
    }

    private func applyDefaultAttributes(in range: NSRange) {
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
            .foregroundColor: UIColor.white
        ]
        backingStore.setAttributes(defaultAttrs, range: range)
    }

    private func applySyntaxHighlighting(in range: NSRange) {
        let text = string
        for rule in syntaxRules.all {
            rule.pattern.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                backingStore.addAttributes(rule.attributes, range: matchRange)
            }
        }
    }
}
