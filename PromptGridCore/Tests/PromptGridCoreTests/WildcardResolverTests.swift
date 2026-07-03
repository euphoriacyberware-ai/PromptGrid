import Testing
import Foundation
@testable import PromptGridCore

/// Deterministic RNG so wildcard picks are reproducible in tests.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite("WildcardResolver")
struct WildcardResolverTests {

    @Test("Text without groups is unchanged")
    func noGroups() {
        var rng = SeededRNG(seed: 1)
        #expect(WildcardResolver.resolve("a plain prompt", using: &rng) == "a plain prompt")
    }

    @Test("A group resolves to one of its trimmed options")
    func resolvesToOption() {
        var rng = SeededRNG(seed: 42)
        let out = WildcardResolver.resolve("a { misty | clear } sky", using: &rng)
        #expect(out == "a misty sky" || out == "a clear sky")
    }

    @Test("Multiple groups resolve independently")
    func multipleGroups() {
        var rng = SeededRNG(seed: 7)
        let out = WildcardResolver.resolve("{red|blue} {cat|dog}", using: &rng)
        let (color, animal) = (out.split(separator: " ")[0], out.split(separator: " ")[1])
        #expect(color == "red" || color == "blue")
        #expect(animal == "cat" || animal == "dog")
    }

    @Test("Malformed groups are left literal")
    func malformedLiteral() {
        var rng = SeededRNG(seed: 1)
        #expect(WildcardResolver.resolve("empty {} braces", using: &rng) == "empty {} braces")
        #expect(WildcardResolver.resolve("unclosed {a|b", using: &rng) == "unclosed {a|b")
        #expect(WildcardResolver.resolve("no open a|b}", using: &rng) == "no open a|b}")
    }

    @Test("Given a fixed seed, resolution is deterministic")
    func deterministic() {
        var a = SeededRNG(seed: 99)
        var b = SeededRNG(seed: 99)
        let text = "{one|two|three|four} and {alpha|beta|gamma}"
        #expect(WildcardResolver.resolve(text, using: &a) == WildcardResolver.resolve(text, using: &b))
    }
}

@Suite("SeedGenerator")
struct SeedGeneratorTests {
    @Test("Seeds fall within the UInt32 range")
    func withinRange() {
        var rng = SeededRNG(seed: 5)
        for _ in 0..<1000 {
            let seed = SeedGenerator.random(using: &rng)
            #expect(seed >= 0 && seed <= Int(UInt32.max))
        }
    }
}
