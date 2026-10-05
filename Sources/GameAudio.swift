import Foundation
import AVFoundation

final class GameAudio {
    enum Effect: String, CaseIterable { case coin, jump, slide, power, crash, shield, start, portal, arrival, relic, warningJump, warningSlide, warningDodge }
    private var enabled = true
    private var music: AVAudioPlayer?
    private var vehicle: AVAudioPlayer?
    private var voices: [Effect: [AVAudioPlayer]] = [:]
    private var lastCoin: TimeInterval = 0
    private var soundscape = "coastline"
    private var musicRequested = false

    init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        if let url = Bundle.main.url(forResource: "coastline", withExtension: "wav") {
            music = try? AVAudioPlayer(contentsOf: url)
            music?.numberOfLoops = -1
            music?.volume = 0.28
            music?.prepareToPlay()
        }
        if let url = Bundle.main.url(forResource: "watercraft", withExtension: "wav") {
            vehicle = try? AVAudioPlayer(contentsOf: url)
            vehicle?.numberOfLoops = -1
            vehicle?.enableRate = true
            vehicle?.volume = 0.15
            vehicle?.prepareToPlay()
        }
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else { continue }
            voices[effect] = (0..<3).compactMap { _ in
                let player = try? AVAudioPlayer(contentsOf: url)
                let warning = effect == .warningJump || effect == .warningSlide || effect == .warningDodge
                player?.volume = warning ? 0.24 : effect == .coin ? 0.22 : 0.35
                player?.prepareToPlay()
                return player
            }
        }
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        if !value { music?.pause(); vehicle?.pause(); voices.values.flatMap { $0 }.forEach { $0.stop() } }
    }
    func setMusicPlaying(_ value: Bool) {
        musicRequested = value
        if value && enabled { music?.play() } else { music?.pause(); vehicle?.pause() }
    }
    /// Swap only at a world boundary; frame updates never restart the soundtrack.
    func setSoundscape(mode: RunMode, world: WorldStage) {
        let name = mode == .odyssey ? "ambient-" + world.rawValue : "coastline"
        guard name != soundscape,
              let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let next = try? AVAudioPlayer(contentsOf: url) else { return }
        music?.stop()
        soundscape = name
        next.numberOfLoops = -1
        next.volume = mode == .odyssey ? 0.23 : 0.28
        next.prepareToPlay()
        music = next
        if musicRequested && enabled { next.play() }
    }
    func setVehicleState(speed: Double, active: Bool, boosting: Bool) {
        guard enabled, active else { vehicle?.pause(); return }
        vehicle?.rate = Float(min(1.7, max(0.7, speed / 24)))
        vehicle?.volume = boosting ? 0.23 : 0.14
        if vehicle?.isPlaying == false { vehicle?.play() }
    }
    func play(_ effect: Effect) {
        guard enabled, let players = voices[effect], !players.isEmpty else { return }
        if effect == .coin {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastCoin > 0.06 else { return }
            lastCoin = now
        }
        let player = players.first(where: { !$0.isPlaying }) ?? players[0]
        player.currentTime = 0
        player.play()
    }
}
