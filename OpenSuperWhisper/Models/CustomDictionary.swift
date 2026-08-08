import Foundation

/// A single custom-dictionary rule: whenever `original` is recognized in a
/// transcription it is rewritten to `replacement`. Useful for fixing proper
/// nouns, brand names and domain jargon that the speech models consistently
/// mis-transcribe (e.g. "git hub" -> "GitHub").
struct CustomDictionaryEntry: Codable, Identifiable, Equatable, Hashable {

    /// What the replacement does to the spaces around it.
    ///
    /// Dictating punctuation needs this. A rule turning the spoken "open quote" into `"` leaves
    /// `he said " hello "` if it only swaps the words, because the spaces that separated them
    /// are still there. Punctuation has to glue to the word it belongs to.
    enum Spacing: String, Codable {
        /// Replace the words and nothing else. Right for names and jargon.
        case standalone
        /// Also eat the space that follows, for an opening mark: `open quote hello` → `"hello`.
        case attachesRight
        /// Also eat the space before, for a closing mark: `hello close quote` → `hello"`.
        case attachesLeft
    }

    var id: UUID
    var original: String
    var replacement: String

    /// Other things the user might say for the same result. Whisper is not consistent about
    /// "open quote" versus "opening quote" versus "quote", and making someone add a whole row
    /// per phrasing means retyping the replacement every time.
    var alternates: [String]
    var spacing: Spacing

    init(id: UUID = UUID(), original: String = "", replacement: String = "",
         alternates: [String] = [], spacing: Spacing = .standalone) {
        self.id = id
        self.original = original
        self.replacement = replacement
        self.alternates = alternates
        self.spacing = spacing
    }

    /// Hand-written so dictionaries saved before `alternates` and `spacing` existed still load;
    /// the synthesised decoder would throw on the missing keys and drop every entry.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        original = try container.decode(String.self, forKey: .original)
        replacement = try container.decode(String.self, forKey: .replacement)
        alternates = try container.decodeIfPresent([String].self, forKey: .alternates) ?? []
        spacing = try container.decodeIfPresent(Spacing.self, forKey: .spacing) ?? .standalone
    }

    /// Every phrasing this rule matches, the primary one first.
    var triggers: [String] {
        ([original] + alternates)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum CustomDictionary {

    /// Applies the user's dictionary replacements to a transcription.
    ///
    /// Matching is case-insensitive and constrained to word boundaries so that
    /// substrings inside larger words are left untouched (e.g. a rule for "cat"
    /// will not touch "category"). The replacement string is inserted verbatim,
    /// preserving the casing the user typed.
    static func apply(_ text: String, entries: [CustomDictionaryEntry]) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }

        var result = text
        for entry in entries {
            let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip incomplete rows. A row with no trigger has nothing to match; an empty
            // `replacement` would silently DELETE every occurrence from the output — a natural
            // intermediate state when the user has filled "Heard" but not yet "Replace with".
            // Both are treated as no-ops rather than data loss.
            guard !replacement.isEmpty else { continue }

            // Longest first, so "opening quote" isn't half-eaten by a "quote" alternate on the
            // same rule.
            for trigger in entry.triggers.sorted(by: { $0.count > $1.count }) {
                let escaped = NSRegularExpression.escapedPattern(for: trigger)
                // Only add a \b assertion where the adjacent character of the search
                // term is itself a word character — otherwise the boundary never
                // matches for terms that start/end with punctuation (e.g. "C++").
                let leadingBoundary = isWordCharacter(trigger.first) ? "\\b" : ""
                let trailingBoundary = isWordCharacter(trigger.last) ? "\\b" : ""

                // Punctuation has to swallow the space on the side it belongs to, or an opening
                // quote lands as `he said " hello`. Only horizontal space is eaten: a rule must
                // not silently pull two paragraphs together.
                let eatBefore = entry.spacing == .attachesLeft ? "[ \\t]*" : ""
                let eatAfter = entry.spacing == .attachesRight ? "[ \\t]*" : ""
                let pattern = eatBefore + leadingBoundary + escaped + trailingBoundary + eatAfter

                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                else { continue }

                let range = NSRange(result.startIndex..., in: result)
                // Use the trimmed replacement (consistent with promptBoost) so a stray leading/
                // trailing space in the rule doesn't produce double spaces in the output.
                let template = NSRegularExpression.escapedTemplate(for: replacement)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range,
                                                        withTemplate: template)
            }
        }
        return result
    }

    /// The de-duplicated list of replacement terms (the "correct" forms). This is
    /// the single source of the words we boost on both engines: Whisper via the
    /// initial prompt (`promptBoost`) and Parakeet via custom-vocabulary boosting
    /// (`FluidAudioEngine`). Order is preserved; de-duplication is case-insensitive.
    static func boostTerms(entries: [CustomDictionaryEntry]) -> [String] {
        var seen = Set<String>()
        return entries
            .map { $0.replacement.trimmingCharacters(in: .whitespacesAndNewlines) }
            // Punctuation rules ("open quote" → `"`) have nothing to teach a model about
            // spelling, and boosting a bare quote mark would just litter the prompt.
            .filter { $0.rangeOfCharacter(from: .alphanumerics) != nil }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Builds an initial-prompt fragment from the dictionary's replacement terms
    /// so a prompt-conditioned model (Whisper) is biased toward producing the
    /// correct spelling in the first place.
    static func promptBoost(entries: [CustomDictionaryEntry]) -> String {
        boostTerms(entries: entries).joined(separator: ", ")
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character = character else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }
}
