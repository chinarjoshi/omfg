import UIKit

struct SyntaxRule {
    let pattern: NSRegularExpression
    let attributes: [NSAttributedString.Key: Any]
}

struct OrgSyntaxRules {
    let all: [SyntaxRule]

    init() {
        all = [
            Self.header1Rule,
            Self.header2Rule,
            Self.header3Rule,
            Self.todoRule,
            Self.doneRule,
            Self.linkRule,
            Self.boldRule,
            Self.italicRule,
            Self.timestampRule
        ]
    }

    private static var header1Rule: SyntaxRule {
        SyntaxRule(
            pattern: try! NSRegularExpression(pattern: "^\\* .+$", options: .anchorsMatchLines),
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.white
            ]
        )
    }

    private static var header2Rule: SyntaxRule {
        SyntaxRule(
            pattern: try! NSRegularExpression(pattern: "^\\*\\* .+$", options: .anchorsMatchLines),
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor.white
            ]
        )
    }

    private static var header3Rule: SyntaxRule {
        SyntaxRule(
            pattern: try! NSRegularExpression(pattern: "^\\*\\*\\* .+$", options: .anchorsMatchLines),
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
        )
    }

    private static var todoRule: SyntaxRule {
        SyntaxRule(
            pattern: try! NSRegularExpression(pattern: "\\bTODO\\b"),
            attributes: [
                .foregroundColor: UIColor.systemRed,
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
            ]
        )
    }

    private static var doneRule: SyntaxRule {
        SyntaxRule(
            pattern: try! NSRegularExpression(pattern: "\\bDONE\\b"),
            attributes: [
                .foregroundColor: UIColor.systemGreen,
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
            ]
        )
    }

    private static var linkRule: SyntaxRule {
        SyntaxRule(
            pattern: try! NSRegularExpression(pattern: "\\[\\[[^\\]]+\\]\\]"),
            attributes: [
                .foregroundColor: UIColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
    }

    private static var boldRule: SyntaxRule {
        SyntaxRule(
            pattern: try! NSRegularExpression(pattern: "(?<=\\s|^)\\*[^\\*\\n]+\\*(?=\\s|$)", options: .anchorsMatchLines),
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
            ]
        )
    }

    private static var italicRule: SyntaxRule {
        SyntaxRule(
            pattern: try! NSRegularExpression(pattern: "(?<=\\s|^)/[^/\\n]+/(?=\\s|$)", options: .anchorsMatchLines),
            attributes: [
                .font: UIFont.italicSystemFont(ofSize: 16)
            ]
        )
    }

    private static var timestampRule: SyntaxRule {
        SyntaxRule(
            pattern: try! NSRegularExpression(pattern: "<[^>]+>"),
            attributes: [
                .foregroundColor: UIColor.systemPurple,
                .backgroundColor: UIColor.systemPurple.withAlphaComponent(0.1)
            ]
        )
    }
}
