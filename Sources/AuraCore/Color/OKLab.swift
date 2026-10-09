import Foundation

/// OKLab perceptual color space (Björn Ottosson, 2020). Interpolating here keeps gradients
/// between saturated colors vivid instead of passing through muddy grey.
public struct OKLab: Hashable, Sendable {
    public var l: Float
    public var a: Float
    public var b: Float

    public init(l: Float, a: Float, b: Float) {
        self.l = l
        self.a = a
        self.b = b
    }

    public init(_ color: RGB) {
        let r = OKLab.toLinear(color.r)
        let g = OKLab.toLinear(color.g)
        let bl = OKLab.toLinear(color.b)
        let lms0 = cbrtf(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let lms1 = cbrtf(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let lms2 = cbrtf(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        l = 0.2104542553 * lms0 + 0.7936177850 * lms1 - 0.0040720468 * lms2
        a = 1.9779984951 * lms0 - 2.4285922050 * lms1 + 0.4505937099 * lms2
        b = 0.0259040371 * lms0 + 0.7827717662 * lms1 - 0.8086757660 * lms2
    }

    public var rgb: RGB {
        let l0 = l + 0.3963377774 * a + 0.2158037573 * b
        let m0 = l - 0.1055613458 * a - 0.0638541728 * b
        let s0 = l - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l0 * l0 * l0
        let m3 = m0 * m0 * m0
        let s3 = s0 * s0 * s0
        let r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let bl = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        return RGB(OKLab.toEncoded(r), OKLab.toEncoded(g), OKLab.toEncoded(bl)).clamped
    }

    public static func mix(_ x: OKLab, _ y: OKLab, _ t: Float) -> OKLab {
        OKLab(l: x.l + (y.l - x.l) * t, a: x.a + (y.a - x.a) * t, b: x.b + (y.b - x.b) * t)
    }

    static func toLinear(_ c: Float) -> Float {
        c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    static func toEncoded(_ c: Float) -> Float {
        let v = max(c, 0)
        return v <= 0.0031308 ? v * 12.92 : 1.055 * powf(v, 1 / 2.4) - 0.055
    }
}
