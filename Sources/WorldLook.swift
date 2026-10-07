import SceneKit

/// Everything that sets a world's mood. Geometry-dependent shadow extents stay in `configureWorld`.
struct WorldLook {
    var sunColor: String, sunIntensity: Double
    /// Degrees. Azimuth 0 = light arriving from straight ahead (-Z), 90 = from the right (+X).
    var sunAzimuth: Double, sunElevation: Double
    var ambientColor: String, ambientIntensity: Double
    var environmentIntensity: Double
    var fogColor: String, fogStart: Double, fogEnd: Double, fogExponent: Double
    var exposure: Double, contrast: Double, saturation: Double
    /// White balance in SceneKit's normalised units: temperature > 0 warms (0.3 is subtle, 1 strong); tint > 0 is magenta, < 0 green.
    var temperature: Double, tint: Double
    /// Back light from behind-right that outlines the runner and props. Orbit's is the strongest.
    var rimColor: String, rimIntensity: Double
    var bloomIntensity: Double, bloomThreshold: Double
    var vignette: Double, grain: Double
}

extension WorldStage {
    var look: WorldLook {
        switch self {
        case .harbor:
            return WorldLook(sunColor: "FFC392", sunIntensity: 1500, sunAzimuth: -81, sunElevation: 35,
                             ambientColor: "8199C9", ambientIntensity: 75, environmentIntensity: 0.65,
                             fogColor: "354B66", fogStart: 75, fogEnd: 215, fogExponent: 1.8,
                             exposure: -0.35, contrast: 0.08, saturation: 1.06, temperature: 0.25, tint: 0.05,
                             rimColor: "72B8F8", rimIntensity: 310, bloomIntensity: 0.32, bloomThreshold: 1.05, vignette: 0.4, grain: 0.06)
        case .orbit:
            return WorldLook(sunColor: "E8F1FF", sunIntensity: 1700, sunAzimuth: -60, sunElevation: 30,
                             ambientColor: "4B6DA8", ambientIntensity: 60, environmentIntensity: 0.75,
                             fogColor: "081329", fogStart: 180, fogEnd: 370, fogExponent: 2.0,
                             exposure: 1.3, contrast: 0.0, saturation: 1.05, temperature: -0.35, tint: 0.0,
                             rimColor: "A9D4FF", rimIntensity: 1100, bloomIntensity: 0.45, bloomThreshold: 0.95, vignette: 0.35, grain: 0.05)
        case .mars:
            return WorldLook(sunColor: "FFD3A2", sunIntensity: 1650, sunAzimuth: 40, sunElevation: 28,
                             ambientColor: "B2664A", ambientIntensity: 110, environmentIntensity: 0.9,
                             fogColor: "B4704E", fogStart: 55, fogEnd: 230, fogExponent: 1.4,
                             exposure: -0.2, contrast: 0.10, saturation: 1.02, temperature: 0.45, tint: 0.08,
                             rimColor: "FFB27A", rimIntensity: 360, bloomIntensity: 0.3, bloomThreshold: 1.05, vignette: 0.45, grain: 0.08)
        case .verdant:
            return WorldLook(sunColor: "BFFFEA", sunIntensity: 1300, sunAzimuth: -30, sunElevation: 40,
                             ambientColor: "2E9C8C", ambientIntensity: 120, environmentIntensity: 0.95,
                             fogColor: "123E3A", fogStart: 60, fogEnd: 240, fogExponent: 1.5,
                             exposure: -0.15, contrast: 0.12, saturation: 1.12, temperature: -0.15, tint: -0.2,
                             rimColor: "7DFFD8", rimIntensity: 380, bloomIntensity: 0.55, bloomThreshold: 0.9, vignette: 0.5, grain: 0.06)
        case .cryo:
            return WorldLook(sunColor: "E6F1FF", sunIntensity: 1850, sunAzimuth: -45, sunElevation: 22,
                             ambientColor: "7FA8D8", ambientIntensity: 130, environmentIntensity: 1.0,
                             fogColor: "6F93BC", fogStart: 70, fogEnd: 260, fogExponent: 1.6,
                             exposure: -0.55, contrast: 0.06, saturation: 0.95, temperature: -0.5, tint: -0.03,
                             rimColor: "BFE3FF", rimIntensity: 420, bloomIntensity: 0.4, bloomThreshold: 1.0, vignette: 0.35, grain: 0.05)
        case .forge:
            return WorldLook(sunColor: "FFA675", sunIntensity: 1250, sunAzimuth: 20, sunElevation: 30,
                             ambientColor: "A0402A", ambientIntensity: 110, environmentIntensity: 0.85,
                             fogColor: "4A1A1A", fogStart: 70, fogEnd: 240, fogExponent: 1.6,
                             exposure: -0.2, contrast: 0.18, saturation: 1.08, temperature: 0.55, tint: 0.1,
                             rimColor: "FF8A4A", rimIntensity: 450, bloomIntensity: 0.6, bloomThreshold: 0.9, vignette: 0.55, grain: 0.08)
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
        worldRim?.color = color(look.rimColor)
        worldRim?.intensity = CGFloat(look.rimIntensity)
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
        // No grading LUT: SceneKit samples it by linear colour with no half-texel offset, which floors the darks.
        lens.colorGrading.contents = nil
    }
}
