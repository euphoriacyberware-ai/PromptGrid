//
//  SeedGenerator.swift
//  PromptGridCore
//
//  The client always owns the seed (Specification §2.3) — it is generated here,
//  stored on the `Run`, and sent explicitly; never read back from a gRPC
//  response. The dependency packs the seed into a `UInt32` (negative/unset seeds
//  are randomized server-side), so valid client seeds are `0...UInt32.max`.
//

import Foundation

public enum SeedGenerator {
    public static let range: ClosedRange<Int> = 0...Int(UInt32.max)

    public static func random() -> Int {
        Int.random(in: range)
    }

    public static func random<G: RandomNumberGenerator>(using rng: inout G) -> Int {
        Int.random(in: range, using: &rng)
    }
}
