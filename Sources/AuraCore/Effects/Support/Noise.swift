import Foundation

/// 2D simplex noise (Gustavson's reference implementation), output roughly in -1...1.
public enum Noise {
    private static let perm: [UInt8] = {
        var rng = SplitMix64(seed: 0xA0_7A_F1_A3E)
        var p = Array(0...255).map(UInt8.init)
        for i in stride(from: 255, to: 0, by: -1) {
            p.swapAt(i, rng.int(below: i + 1))
        }
        return p + p
    }()

    private static let gradients: [SIMD2<Float>] = (0..<12).map { i in
        let angle = Float(i) / 12 * 2 * .pi
        return SIMD2(cosf(angle), sinf(angle))
    }

    private static let f2: Float = 0.5 * (sqrtf(3) - 1)
    private static let g2: Float = (3 - sqrtf(3)) / 6

    public static func simplex(_ x: Float, _ y: Float) -> Float {
        let s = (x + y) * f2
        let i = (x + s).rounded(.down)
        let j = (y + s).rounded(.down)
        let t = (i + j) * g2
        let x0 = x - (i - t)
        let y0 = y - (j - t)
        let i1: Float = x0 > y0 ? 1 : 0
        let j1: Float = x0 > y0 ? 0 : 1
        let x1 = x0 - i1 + g2
        let y1 = y0 - j1 + g2
        let x2 = x0 - 1 + 2 * g2
        let y2 = y0 - 1 + 2 * g2
        let ii = Int(i) & 255
        let jj = Int(j) & 255
        let g0 = gradients[Int(perm[ii + Int(perm[jj])]) % 12]
        let g1 = gradients[Int(perm[ii + Int(i1) + Int(perm[jj + Int(j1)])]) % 12]
        let gc = gradients[Int(perm[ii + 1 + Int(perm[jj + 1])]) % 12]
        return 70 * (corner(g0, x0, y0) + corner(g1, x1, y1) + corner(gc, x2, y2))
    }

    /// Fractal sum of simplex octaves, roughly -1...1.
    public static func fbm(_ x: Float, _ y: Float, octaves: Int = 3) -> Float {
        var sum: Float = 0
        var amplitude: Float = 0.5
        var frequency: Float = 1
        var norm: Float = 0
        for _ in 0..<octaves {
            sum += amplitude * simplex(x * frequency, y * frequency)
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return sum / norm
    }

    @inline(__always)
    private static func corner(_ g: SIMD2<Float>, _ x: Float, _ y: Float) -> Float {
        let t = 0.5 - x * x - y * y
        if t < 0 { return 0 }
        let t2 = t * t
        return t2 * t2 * (g.x * x + g.y * y)
    }
}

@inlinable
func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

@inlinable
func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}
