//
//  WildcardResolver.swift
//  PromptGridCore
//
//  Flat wildcard groups (Specification §5): `{option 1|option 2|option 3}`.
//  A pure function — find `\{[^{}]+\}`, split each match on `|`, trim each
//  option, pick one at random. No nesting; malformed groups (unclosed `{`,
//  empty `{}`) are left as literal text rather than erroring.
//
//  Resolution happens once, at job creation, and is frozen into the
//  `GenerationJob`. Each prompt resolves independently.
//

import Foundation

public enum WildcardResolver {

    // `[^{}]+` requires at least one non-brace character, so `{}` never matches
    // (stays literal) and nested braces can't be captured.
    private static let pattern = try! NSRegularExpression(pattern: "\\{[^{}]+\\}")

    public static func resolve(_ text: String) -> String {
        var rng = SystemRandomNumberGenerator()
        return resolve(text, using: &rng)
    }

    public static func resolve<G: RandomNumberGenerator>(_ text: String, using rng: inout G) -> String {
        let ns = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = 0
        for match in matches {
            let range = match.range
            result += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))

            let group = ns.substring(with: range)            // includes braces
            let inner = String(group.dropFirst().dropLast()) // strip { }
            let options = inner
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            result += options.randomElement(using: &rng) ?? group

            cursor = range.location + range.length
        }
        result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        return result
    }
}
