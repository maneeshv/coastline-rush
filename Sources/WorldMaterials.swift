import SceneKit

/// Model-space surface detail shared by every lit, non-emissive material. Model space keeps the
/// pattern fixed to scrolling sections and pooled props, so it never swims as the world moves.
extension CoastalWorld {
    static let surfaceDetailModifier = """
    #pragma arguments
    texture2d<float> detailMap;
    float detailScale;
    float detailStrength;
    #pragma body
    constexpr sampler detailSampler(filter::linear, mip_filter::linear, address::repeat);
    float3 local = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
    float3 w = abs(normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz));
    w = pow(w, float3(4.0)); w /= max(0.0001, w.x + w.y + w.z);
    float3 p = local * detailScale;
    float4 broad = detailMap.sample(detailSampler, p.yz) * w.x + detailMap.sample(detailSampler, p.xz) * w.y + detailMap.sample(detailSampler, p.xy) * w.z;
    float3 q = p * 4.7 + 0.31;
    float4 fine = detailMap.sample(detailSampler, q.yz) * w.x + detailMap.sample(detailSampler, q.xz) * w.y + detailMap.sample(detailSampler, q.xy) * w.z;
    float breakup = (broad.r - 0.5) * 2.0;
    float grain = (fine.g - 0.5) * 2.0;
    _surface.diffuse.rgb *= 1.0 + detailStrength * (0.22 * breakup + 0.10 * grain - 0.35 * broad.b);
    _surface.roughness = clamp(_surface.roughness + detailStrength * (0.18 * breakup + 0.12 * fine.g - 0.06), 0.04, 1.0);
    """

    /// 512² tileable data texture (linear, not color): R broad fbm, G fine fbm, B cavities and specks.
    func detailTexture() -> CGImage? {
        if let cached = textureCache["surface-detail"] { return cached }
        let size = 512
        func lattice(_ x: Int, _ y: Int, _ period: Int, _ seed: UInt64) -> Double {
            // Split into steps: one long mixed &*/^ expression times out the type checker.
            var h = UInt64(x % period) &* 0x9E37_79B9_7F4A_7C15
            h ^= UInt64(y % period) &* 0xC2B2_AE3D_27D4_EB4F
            h ^= seed
            h ^= h >> 31; h = h &* 0x94D0_49BB_1331_11EB; h ^= h >> 29
            return Double(h & 0xFFFF) / 65535
        }
        func noise(_ u: Double, _ v: Double, period: Int, seed: UInt64) -> Double {
            let x = u * Double(period), y = v * Double(period)
            let xi = Int(x), yi = Int(y), fx = x - Double(xi), fy = y - Double(yi)
            let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
            let a = lattice(xi, yi, period, seed), b = lattice(xi + 1, yi, period, seed)
            let c = lattice(xi, yi + 1, period, seed), d = lattice(xi + 1, yi + 1, period, seed)
            let top = a + (b - a) * sx, bottom = c + (d - c) * sx
            return top + (bottom - top) * sy
        }
        func fbm(_ u: Double, _ v: Double, base: Int, seed: UInt64) -> Double {
            var sum = 0.0, amplitude = 0.5, norm = 0.0, period = base
            for octave in 0..<4 { sum += noise(u, v, period: period, seed: seed &+ UInt64(octave)) * amplitude; norm += amplitude; amplitude *= 0.5; period *= 2 }
            return sum / norm
        }
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size { for x in 0..<size {
            let u = Double(x) / Double(size), v = Double(y) / Double(size)
            let broad = fbm(u, v, base: 4, seed: 11), fine = fbm(u, v, base: 32, seed: 23)
            let speck = noise(u, v, period: 128, seed: 37)
            let cavity = min(1, max(0, (speck - 0.78) / 0.22) * 0.8 + max(0, (0.30 - broad) / 0.30) * 0.4)
            let i = (y * size + x) * 4
            pixels[i] = UInt8(broad * 255); pixels[i + 1] = UInt8(fine * 255); pixels[i + 2] = UInt8(cavity * 255)
        } }
        let result = Self.rgbaImage(pixels, width: size, height: size)
        textureCache["surface-detail"] = result
        return result
    }

    func applySurfaceDetail(to material: SCNMaterial, scale: Double = 0.45, strength: Double = 1.8) {
        material.shaderModifiers = [.surface: Self.surfaceDetailModifier]
        let map = SCNMaterialProperty(contents: detailTexture() as Any)
        map.wrapS = .repeat; map.wrapT = .repeat
        map.minificationFilter = .linear; map.magnificationFilter = .linear; map.mipFilter = .linear
        material.setValue(map, forKey: "detailMap")
        material.setValue(NSNumber(value: scale), forKey: "detailScale")
        material.setValue(NSNumber(value: strength), forKey: "detailStrength")
    }

    /// Linear-space RGBA so data textures are not gamma-decoded when sampled.
    static func rgbaImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
