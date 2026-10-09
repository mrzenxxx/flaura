import Foundation

/// Small, fast, seedable PRNG (SplitMix64). Effects use it so tests can be deterministic.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform float in 0..<1.
    @inlinable
    public mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    /// Uniform float in `range`.
    @inlinable
    public mutating func float(_ range: ClosedRange<Float>) -> Float {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    @inlinable
    public mutating func int(below bound: Int) -> Int {
        bound <= 1 ? 0 : Int(next() % UInt64(bound))
    }

    /// True with probability `p`.
    @inlinable
    public mutating func chance(_ p: Float) -> Bool {
        unit() < p
    }
}
