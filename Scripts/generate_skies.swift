// Generates the off-world panoramas used as background and lighting environment.
// swiftc -O Scripts/generate_skies.swift -o work/skies && work/skies Resources
// Equirectangular 2048x1024; u = 0.75 faces the camera's forward (-Z), v = 0.5 is the horizon.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import simd

typealias V3 = SIMD3<Double>

func hex(_ s: String) -> V3 {
    let v = UInt64(s, radix: 16) ?? 0
    return V3(Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255)) / 255
}
func mix(_ a: V3, _ b: V3, _ t: Double) -> V3 { a + (b - a) * t }
func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t)
}
func luminance(_ c: V3) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

func hash(_ x: Int, _ y: Int, _ z: Int, _ seed: Int) -> Double {
    var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ z &* 1_274_126_177 &+ seed &* 144_665))
    h = (h ^ (h >> 13)) &* 0x5851_F42D_4C95_7F2D
    h ^= h >> 29
    return Double(h & 0xFF_FFFF) / Double(0xFF_FFFF)
}

/// Trilinear value noise. Sampling on a cylinder (cos lon, sin lon, lat) keeps u = 0/1 seamless.
func noise(_ p: V3, _ seed: Int) -> Double {
    let i = p.rounded(.down), f = p - i
    let u = f * f * (3 - 2 * f)
    let x = Int(i.x), y = Int(i.y), z = Int(i.z)
    func h(_ dx: Int, _ dy: Int, _ dz: Int) -> Double { hash(x + dx, y + dy, z + dz, seed) }
    let x00 = h(0, 0, 0) + (h(1, 0, 0) - h(0, 0, 0)) * u.x
    let x10 = h(0, 1, 0) + (h(1, 1, 0) - h(0, 1, 0)) * u.x
    let x01 = h(0, 0, 1) + (h(1, 0, 1) - h(0, 0, 1)) * u.x
    let x11 = h(0, 1, 1) + (h(1, 1, 1) - h(0, 1, 1)) * u.x
    let y0 = x00 + (x10 - x00) * u.y, y1 = x01 + (x11 - x01) * u.y
    return y0 + (y1 - y0) * u.z
}

func fbm(_ p: V3, octaves: Int, seed: Int) -> Double {
    var sum = 0.0, amp = 0.5, q = p, norm = 0.0
    for o in 0..<octaves { sum += noise(q, seed + o * 31) * amp; norm += amp; q *= 2.03; amp *= 0.5 }
    return sum / norm
}

struct Sky {
    let name: String
    let zenith: String, horizon: String, ground: String
    let cloudLit: String, cloudShadow: String
    let coverage: Double, cloudLow: Double, cloudHigh: Double, cloudScale: Double
    let nebulaA: String, nebulaB: String, nebula: Double
    let aurora: [String]
    let stars: Double
    let sunU: Double, sunV: Double, sunColor: String, sunSize: Double, glow: Double
    let seed: Int
}

let skies = [
    // Dust haze, low pale sun behind the existing sun sphere.
    Sky(name: "MarsSky", zenith: "2B1424", horizon: "D08A5C", ground: "4A2418", cloudLit: "F2B48A", cloudShadow: "7A3A30",
        coverage: 0.55, cloudLow: 0.0, cloudHigh: 0.45, cloudScale: 3.0, nebulaA: "000000", nebulaB: "000000", nebula: 0,
        aurora: [], stars: 0.0015, sunU: 0.79, sunV: 0.457, sunColor: "FFE2C2", sunSize: 0.02, glow: 0.55, seed: 11),
    // Bioluminescent night: teal/violet nebula and aurora above the temple.
    Sky(name: "VerdantSky", zenith: "020B12", horizon: "1C5A52", ground: "06201E", cloudLit: "4FAE9A", cloudShadow: "0B2A2C",
        coverage: 0.62, cloudLow: 0.02, cloudHigh: 0.35, cloudScale: 2.5, nebulaA: "2FB79A", nebulaB: "5A3FC0", nebula: 0.55,
        aurora: ["46F0C0", "7B62FF"], stars: 0.004, sunU: 0.68, sunV: 0.36, sunColor: "BFFFF0", sunSize: 0.035, glow: 0.35, seed: 23),
    // Cold high-key horizon; halo behind the existing ice planet.
    Sky(name: "CryoSky", zenith: "060E2A", horizon: "7FA6CF", ground: "1A2C48", cloudLit: "D7E8FF", cloudShadow: "4A6286",
        coverage: 0.6, cloudLow: 0.0, cloudHigh: 0.28, cloudScale: 3.2, nebulaA: "6C8CFF", nebulaB: "3FD8C0", nebula: 0.15,
        aurora: ["57E6B8", "8A7BFF"], stars: 0.005, sunU: 0.713, sunV: 0.433, sunColor: "E6F1FF", sunSize: 0.0, glow: 0.4, seed: 37),
    // Smoke-filled furnace sky with a giant red star above the reactor.
    Sky(name: "ForgeSky", zenith: "0C0308", horizon: "C2462A", ground: "2A0A08", cloudLit: "FF8A4A", cloudShadow: "2A0E12",
        coverage: 0.45, cloudLow: 0.0, cloudHigh: 0.6, cloudScale: 2.2, nebulaA: "FF5A2A", nebulaB: "7A1E3A", nebula: 0.25,
        aurora: [], stars: 0.0008, sunU: 0.75, sunV: 0.42, sunColor: "7A1C0C", sunSize: 0.05, glow: 0.8, seed: 41),
]

func direction(u: Double, v: Double) -> V3 {
    let lon = u * 2 * .pi, lat = (0.5 - v) * .pi
    return V3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
}

func render(_ sky: Sky, width w: Int, height h: Int) -> [UInt8] {
    let zenith = hex(sky.zenith), horizon = hex(sky.horizon), ground = hex(sky.ground)
    let cloudLit = hex(sky.cloudLit), cloudShadow = hex(sky.cloudShadow), sunColor = hex(sky.sunColor)
    let nebulaA = hex(sky.nebulaA), nebulaB = hex(sky.nebulaB), auroras = sky.aurora.map(hex)
    let sunDir = direction(u: sky.sunU, v: sky.sunV)
    // Rows are independent; each thread writes only its own row of one shared buffer.
    let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: w * h * 4)
    buffer.initialize(repeating: 255)
    defer { buffer.deallocate() }
    DispatchQueue.concurrentPerform(iterations: h) { row in
        for col in 0..<w {
            let u = (Double(col) + 0.5) / Double(w), v = (Double(row) + 0.5) / Double(h)
            let lon = u * 2 * .pi, lat = (0.5 - v) * .pi
            let dir = direction(u: u, v: v)
            let e = sin(lat)
            var c = e >= 0 ? mix(horizon, zenith, pow(e, 0.42)) : mix(horizon, ground, min(1, -e * 5))
            c = mix(c, horizon * 1.15, exp(-abs(e) * 18) * 0.5)
            let cyl = V3(cos(lon), sin(lon), lat)
            let sunDot = min(1, max(-1, simd_dot(dir, sunDir)))
            let sunAngle = acos(sunDot)
            if sky.nebula > 0 {
                let n = fbm(cyl * 2.2 + 5, octaves: 5, seed: sky.seed)
                let ridge = 1 - abs(2 * n - 1)
                let weight = pow(ridge, 3) * sky.nebula * smoothstep(0.05, 0.5, e)
                c += mix(nebulaA, nebulaB, fbm(cyl * 1.3 + 9, octaves: 3, seed: sky.seed + 7)) * weight
            }
            if sky.stars > 0 && e > -0.02 {
                let r = hash(col, row, 7, sky.seed)
                if r > 1 - sky.stars {
                    let b = pow((r - (1 - sky.stars)) / sky.stars, 3) * 0.9 + 0.1
                    c += V3(repeating: b * max(0, 1 - luminance(c) * 3))
                }
            }
            for (i, tint) in auroras.enumerated() {
                let center = 0.25 + Double(i) * 0.12
                let wobble = sin(lon * 3 + Double(i) * 1.7) * 0.05 + (fbm(cyl * 1.5 + Double(i), octaves: 3, seed: sky.seed + 50 + i) - 0.5) * 0.1
                let d = e - (center + wobble)
                let band = exp(-max(0, d) * 14 - max(0, -d) * 60)
                let rays = 0.4 + 0.6 * pow(noise(V3(cos(lon) * 40, sin(lon) * 40, Double(i) * 3), sky.seed + 90), 2)
                c += tint * band * rays * 0.55
            }
            if e > sky.cloudLow - 0.02 && e < sky.cloudHigh {
                let w = smoothstep(sky.cloudLow, sky.cloudLow + 0.05, e) * (1 - smoothstep(sky.cloudHigh - 0.1, sky.cloudHigh, e))
                let s = sky.cloudScale
                let p = V3(cos(lon) * s, sin(lon) * s, lat * s * 3.5)
                let n = fbm(p, octaves: 6, seed: sky.seed + 200)
                let density = smoothstep(sky.coverage, sky.coverage + 0.22, n) * w
                if density > 0 {
                    let detail = fbm(p * 2.1 + 3, octaves: 4, seed: sky.seed + 300)
                    let light = (0.35 + 0.65 * pow((sunDot + 1) / 2, 2)) * (0.5 + 0.5 * detail)
                    let lit = mix(cloudShadow, cloudLit, light) + sunColor * exp(-sunAngle * 4) * 0.6
                    c = mix(c, lit, density * 0.92)
                }
            }
            let core = sky.sunSize > 0 ? smoothstep(sky.sunSize, sky.sunSize * 0.8, sunAngle) : 0
            let tight: Double = exp(-sunAngle * 7) * sky.glow
            let wide: Double = exp(-sunAngle * 1.6) * sky.glow * 0.35
            c += sunColor * (core * 3 + tight + wide)
            let dither = (hash(col, row, 3, 1) - 0.5) / 255
            for k in 0..<3 { buffer[(row * w + col) * 4 + k] = UInt8(max(0, min(255, (c[k] + dither) * 255))) }
        }
    }
    return Array(buffer)
}

func write(_ pixels: [UInt8], width w: Int, height h: Int, to url: URL) {
    let data = CFDataCreate(nil, pixels, pixels.count)!
    let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                        provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Could not write \(url.path)")
}

/// Self-check: size, a seamless wrap, and a visible (non-black) horizon.
func check(_ pixels: [UInt8], width w: Int, height h: Int, name: String) {
    precondition(pixels.count == w * h * 4, "\(name): wrong size")
    var seam = 0.0
    for row in 0..<h { for k in 0..<3 {
        seam += abs(Double(pixels[row * w * 4 + k]) - Double(pixels[(row * w + w - 1) * 4 + k])) / 255
    } }
    seam /= Double(h * 3)
    let horizonRow = h / 2 - 4
    var horizon = 0.0
    for col in 0..<w { horizon += Double(pixels[(horizonRow * w + col) * 4 + 1]) / 255 }
    horizon /= Double(w)
    precondition(seam < 0.03, "\(name): seam \(seam) too visible")
    precondition(horizon > 0.08, "\(name): horizon too dark (\(horizon))")
    print(name, String(format: "seam=%.4f horizon=%.3f", seam, horizon))
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources")
for sky in skies {
    let pixels = render(sky, width: 2048, height: 1024)
    check(pixels, width: 2048, height: 1024, name: sky.name)
    write(pixels, width: 2048, height: 1024, to: output.appendingPathComponent(sky.name + ".png"))
}
