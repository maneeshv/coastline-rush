import SceneKit
import CoreGraphics

/// Everything that sets a world's mood. Geometry-dependent shadow extents stay in `configureWorld`.
struct WorldLook {
    var sunColor: String, sunIntensity: Double
    /// Degrees. Azimuth 0 = light arriving from straight ahead (-Z), 90 = from the right (+X).
    var sunAzimuth: Double, sunElevation: Double
    var ambientColor: String, ambientIntensity: Double
    var environmentIntensity: Double
    var fogColor: String, fogStart: Double, fogEnd: Double, fogExponent: Double
    var exposure: Double, contrast: Double, saturation: Double
    var temperature: Double, tint: Double
    var bloomIntensity: Double, bloomThreshold: Double
    var vignette: Double, grain: Double
    /// Split toning: hue pushed into shadows and highlights, plus a gentle S-curve.
    var shadowTint: String, highlightTint: String, splitStrength: Double, curve: Double
}

extension WorldStage {
    var look: WorldLook {
        switch self {
        case .harbor:
            return WorldLook(sunColor: "FFC392", sunIntensity: 1500, sunAzimuth: -81, sunElevation: 35,
                             ambientColor: "8199C9", ambientIntensity: 75, environmentIntensity: 0.65,
                             fogColor: "354B66", fogStart: 75, fogEnd: 215, fogExponent: 1.8,
                             exposure: -0.35, contrast: 0.08, saturation: 1.06, temperature: 0, tint: 0,
                             bloomIntensity: 0.32, bloomThreshold: 1.05, vignette: 0.4, grain: 0.06,
                             shadowTint: "2B4A7A", highlightTint: "FFB070", splitStrength: 0.10, curve: 0.25)
        case .orbit:
            return WorldLook(sunColor: "E8F1FF", sunIntensity: 1700, sunAzimuth: -60, sunElevation: 30,
                             ambientColor: "4B6DA8", ambientIntensity: 60, environmentIntensity: 0.75,
                             fogColor: "081329", fogStart: 180, fogEnd: 370, fogExponent: 2.0,
                             exposure: 0.35, contrast: 0.14, saturation: 1.05, temperature: 0, tint: 0,
                             bloomIntensity: 0.45, bloomThreshold: 0.95, vignette: 0.5, grain: 0.05,
                             shadowTint: "10204A", highlightTint: "BFE6FF", splitStrength: 0.12, curve: 0.35)
        case .mars:
            return WorldLook(sunColor: "FFD3A2", sunIntensity: 1650, sunAzimuth: 40, sunElevation: 28,
                             ambientColor: "B2664A", ambientIntensity: 110, environmentIntensity: 0.9,
                             fogColor: "B4704E", fogStart: 55, fogEnd: 230, fogExponent: 1.4,
                             exposure: -0.2, contrast: 0.10, saturation: 1.02, temperature: 0, tint: 0,
                             bloomIntensity: 0.3, bloomThreshold: 1.05, vignette: 0.45, grain: 0.08,
                             shadowTint: "5A2A3A", highlightTint: "FFC890", splitStrength: 0.12, curve: 0.3)
        case .verdant:
            return WorldLook(sunColor: "BFFFEA", sunIntensity: 1300, sunAzimuth: -30, sunElevation: 40,
                             ambientColor: "2E9C8C", ambientIntensity: 120, environmentIntensity: 0.95,
                             fogColor: "123E3A", fogStart: 60, fogEnd: 240, fogExponent: 1.5,
                             exposure: -0.15, contrast: 0.12, saturation: 1.12, temperature: 0, tint: 0,
                             bloomIntensity: 0.55, bloomThreshold: 0.9, vignette: 0.5, grain: 0.06,
                             shadowTint: "1A1450", highlightTint: "7CFFD8", splitStrength: 0.14, curve: 0.3)
        case .cryo:
            return WorldLook(sunColor: "E6F1FF", sunIntensity: 1850, sunAzimuth: -45, sunElevation: 22,
                             ambientColor: "7FA8D8", ambientIntensity: 130, environmentIntensity: 1.0,
                             fogColor: "6F93BC", fogStart: 70, fogEnd: 260, fogExponent: 1.6,
                             exposure: -0.55, contrast: 0.06, saturation: 0.95, temperature: 0, tint: 0,
                             bloomIntensity: 0.4, bloomThreshold: 1.0, vignette: 0.35, grain: 0.05,
                             shadowTint: "203A80", highlightTint: "E8F6FF", splitStrength: 0.10, curve: 0.2)
        case .forge:
            return WorldLook(sunColor: "FFA675", sunIntensity: 1250, sunAzimuth: 20, sunElevation: 30,
                             ambientColor: "A0402A", ambientIntensity: 110, environmentIntensity: 0.85,
                             fogColor: "4A1A1A", fogStart: 70, fogEnd: 240, fogExponent: 1.6,
                             exposure: -0.2, contrast: 0.18, saturation: 1.08, temperature: 0, tint: 0,
                             bloomIntensity: 0.6, bloomThreshold: 0.9, vignette: 0.55, grain: 0.08,
                             shadowTint: "2A0A20", highlightTint: "FFB060", splitStrength: 0.14, curve: 0.4)
        }
    }
}

extension CoastalWorld {
    /// Single entry point for a world's lighting and post-processing; quality only scales it.
    func applyLook(_ stage: WorldStage) {
        let look = stage.look
        worldSun?.color = color(look.sunColor)
        worldSun?.intensity = CGFloat(look.sunIntensity)
        if let sun = worldSunNode {
            let az = look.sunAzimuth * .pi / 180, el = look.sunElevation * .pi / 180
            let target = SCNVector3(0, 0, -8)
            let distance = 32.0
            sun.position = SCNVector3(CoastScalar(sin(az) * cos(el) * distance),
                                      CoastScalar(sin(el) * distance),
                                      CoastScalar(-8 - cos(az) * cos(el) * distance))
            sun.look(at: target)
        }
        worldAmbient?.color = color(look.ambientColor)
        worldAmbient?.intensity = CGFloat(look.ambientIntensity)
        scene.lightingEnvironment.intensity = CGFloat(look.environmentIntensity)
        scene.fogColor = color(look.fogColor)
        scene.fogStartDistance = CGFloat(look.fogStart)
        scene.fogEndDistance = CGFloat(look.fogEnd)
        scene.fogDensityExponent = CGFloat(look.fogExponent)
        guard let lens = camera.camera else { return }
        let fullPost = qualityLevel > 0
        lens.exposureOffset = CGFloat(look.exposure)
        lens.contrast = CGFloat(look.contrast)
        lens.saturation = CGFloat(look.saturation)
        lens.whiteBalanceTemperature = CGFloat(look.temperature)
        lens.whiteBalanceTint = CGFloat(look.tint)
        lens.bloomIntensity = CGFloat(look.bloomIntensity * (fullPost ? 1 : 0.45))
        lens.bloomThreshold = CGFloat(look.bloomThreshold)
        lens.bloomBlurRadius = fullPost ? 8 : 3
        lens.vignettingIntensity = CGFloat(look.vignette)
        lens.vignettingPower = 0.8
        lens.grainIntensity = fullPost ? CGFloat(look.grain) : 0
        lens.grainScale = 1.2
        let shadow = Self.rgb(color(look.shadowTint)), highlight = Self.rgb(color(look.highlightTint))
        lens.colorGrading.contents = Self.gradingLUT { c in
            let l = simd_dot(c, SIMD3(0.2126, 0.7152, 0.0722))
            // Hue-only offsets so the tints never brighten or darken the frame.
            let shadowShift = shadow - simd_dot(shadow, SIMD3(0.2126, 0.7152, 0.0722))
            let highlightShift = highlight - simd_dot(highlight, SIMD3(0.2126, 0.7152, 0.0722))
            var out = c + shadowShift * pow(1 - l, 2) * look.splitStrength + highlightShift * pow(l, 2) * look.splitStrength
            out = simd_clamp(out, SIMD3(repeating: 0), SIMD3(repeating: 1))
            let s = out * out * (3 - 2 * out)
            return out + (s - out) * look.curve
        }
    }

    static func rgb(_ value: CoastColor) -> SIMD3<Double> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        value.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3(Double(r), Double(g), Double(b))
    }

    /// SceneKit applies the grading cube to linear scene color: it samples straight at the color's normalized
    /// coordinate, with no half-texel correction, and reads the stored values back as linear. So texel k holds
    /// the grade of color (k + 0.5) / size; `grade` itself works on sRGB-encoded colors so its tuning stays perceptual.
    /// `size` slices of a size³ cube in one horizontal row. Within a slice: x = red, row = green; slice index = blue.
    static func gradingLUT(size: Int = 32, grade: (SIMD3<Double>) -> SIMD3<Double>) -> CGImage? {
        let width = size * size, height = size
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        func encode(_ l: Double) -> Double { l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055 }
        func decode(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, decode(max(0, min(1, v))) * 255 + 0.5))) }
        let cell = { (k: Int) in encode((Double(k) + 0.5) / Double(size)) }
        for g in 0..<size { for b in 0..<size { for r in 0..<size {
            let out = grade(SIMD3(cell(r), cell(g), cell(b)))
            let i = (g * width + b * size + r) * 4
            pixels[i] = byte(out.x); pixels[i + 1] = byte(out.y); pixels[i + 2] = byte(out.z)
        } } }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
