import Foundation

/// Deterministic offline cleanup; replacements are simultaneous, never recursively reprocessed.
/// Sendability is safe because the profile/rules are immutable and NSRegularExpression is thread-safe.
public struct DictationTextProcessor: @unchecked Sendable {
    public let profile: DictationProfile
    private let expression: NSRegularExpression
    private let aliases: [String: String]
    private let punctuation: [String: String]

    /// Validate a configurable profile and compile longest-match-first token rules once.
    public init(profile: DictationProfile = DictationProfile()) throws {
        try profile.validate()
        self.profile = profile
        aliases = Dictionary(uniqueKeysWithValues: profile.replacements.map { ($0.spoken, $0.command) })
        punctuation = profile.spokenPunctuation ? [
            "new paragraph": "\n\n", "new line": "\n",
            "question mark": "?", "exclamation point": "!", "exclamation mark": "!",
            "full stop": ".", "period": ".", "comma": ",", "semicolon": ";", "colon": ":",
            "open parenthesis": "(", "close parenthesis": ")",
        ] : [:]
        // Slash tokens are protected before matching any spoken words. The
        // lookarounds exclude matching inside identifiers, paths, and commands.
        let left = "(?<![\\p{L}\\p{N}_/:-])"
        let right = "(?![\\p{L}\\p{N}_/-])"
        var patterns = [
            "\(left)(?<command>/(?:skill:)?[a-z0-9]+(?:-[a-z0-9]+)*)\(right)[.,!?;:]*(?=\\s|$)",
        ]
        if !aliases.isEmpty {
            patterns.append("\(left)(?<alias>\(Self.phrasePattern(Array(aliases.keys))))\(right)[.,!?;:]*")
        }
        if !punctuation.isEmpty {
            patterns.append("\(left)(?<punctuation>\(Self.phrasePattern(Array(punctuation.keys))))\(right)[.,!?;:]*")
        }
        if profile.filterFillerWords {
            // Do not delete meaningful "like", "well", "you know", or French "ben".
            patterns.append("\(left)(?<filler>um|uh)\(right)[,]*")
        }
        expression = try NSRegularExpression(pattern: patterns.joined(separator: "|"), options: .caseInsensitive)
    }

    /// Produce editable text only; nonempty output has exactly one optional trailing space.
    public func process(_ text: String) -> String {
        let source = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
        var output = ""
        var cursor = 0
        for match in matches {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if let command = capture("command", match: match, source: source) {
                output += command // Sentence punctuation is outside this capture.
            } else if !aliases.isEmpty, let alias = capture("alias", match: match, source: source) {
                output += aliases[Self.normalizedPhrase(alias)] ?? alias
            } else if !punctuation.isEmpty, let spoken = capture("punctuation", match: match, source: source) {
                output += punctuation[Self.normalizedPhrase(spoken)] ?? spoken
            }
            cursor = NSMaxRange(match.range)
        }
        output += source.substring(from: cursor)
        output = output.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: " +([.,!?;:)])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([(]) +", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? "" : output + (profile.appendSpace ? " " : "")
    }

    /// Join already processed/edited text to a draft without gluing words or running cleanup again.
    public func joining(_ transcript: String, to draft: String) -> String {
        guard !transcript.isEmpty else { return draft }
        let needsSpace = !draft.isEmpty && draft.last?.isWhitespace == false && transcript.first?.isWhitespace == false
        return draft + (needsSpace ? " " : "") + transcript
    }

    private func capture(_ name: String, match: NSTextCheckingResult, source: NSString) -> String? {
        let range = match.range(withName: name)
        return range.location == NSNotFound ? nil : source.substring(with: range)
    }

    private static func normalizedPhrase(_ phrase: String) -> String {
        phrase.lowercased(with: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func phrasePattern(_ phrases: [String]) -> String {
        phrases.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
            .map { $0.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[ \\t]+") }
            .joined(separator: "|")
    }
}
