import Foundation

/// Replays can only race the identical generator, difficulty and starting world.
struct GhostCourseKey: Codable, Equatable, Hashable {
    /// Course generator revision for ghost recordings. It is bumped whenever generation changes,
    /// so old ghosts retire. It is independent of PortalJourney.currentRevision, which also archives world records.
    /// 8: G1 coin lines. 9: G2 hazards and the G3 shuffle bag, fork and finale order.
    static let currentRevision = 9
    /// Endless and Sprint ghosts: 5 for G1 coins and pickups, 6 for G3 escalation and forgiveness.
    static let legacyModeRevision = 6
    /// Jet Ski generation has not changed since revision 4, so its ghosts stay valid.
    static func revision(for mode: RunMode) -> Int {
        mode == .odyssey ? currentRevision : mode == .jetSki ? 4 : legacyModeRevision
    }
    var mode: RunMode
    var expert: Bool
    var seed: UInt64
    var startWorld: Int
    var revision: Int
    var expeditionStyle: ExpeditionStyle
    var decisionPlan: [ExpeditionDecision]
    var artifact: ArtifactAbility?

    init(mode: RunMode, expert: Bool, seed: UInt64, startWorld: Int,
         expeditionStyle: ExpeditionStyle = .campaign, decisionPlan: [ExpeditionDecision] = [], artifact: ArtifactAbility? = nil) {
        self.mode = mode; self.expert = expert; self.seed = seed; self.startWorld = startWorld
        self.expeditionStyle = mode == .odyssey ? expeditionStyle : .campaign
        self.decisionPlan = mode == .odyssey ? decisionPlan : []
        self.artifact = mode == .odyssey ? artifact : nil
        revision = Self.revision(for: mode)
    }

    var isValid: Bool {
        guard revision == Self.revision(for: mode),
              (0..<WorldStage.allCases.count).contains(startWorld), expeditionStyle == .campaign else { return false }
        guard mode == .odyssey else { return startWorld == 0 && decisionPlan.isEmpty && artifact == nil }
        guard decisionPlan.count <= WorldStage.allCases.count else { return false }
        var priorWorld = startWorld - 1
        var perks = Set<ExpeditionPerk>()
        for decision in decisionPlan {
            guard (startWorld..<WorldStage.allCases.count).contains(decision.world), decision.world > priorWorld else { return false }
            if let perk = decision.perk {
                guard decision.world != startWorld && perks.insert(perk).inserted else { return false }
            }
            priorWorld = decision.world
        }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case mode, expert, seed, startWorld, revision, expeditionStyle, decisionPlan, artifact
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decode(RunMode.self, forKey: .mode)
        expert = try values.decode(Bool.self, forKey: .expert)
        seed = try values.decode(UInt64.self, forKey: .seed)
        startWorld = try values.decode(Int.self, forKey: .startWorld)
        revision = try values.decode(Int.self, forKey: .revision)
        expeditionStyle = try values.decodeIfPresent(ExpeditionStyle.self, forKey: .expeditionStyle) ?? .campaign
        decisionPlan = try values.decodeIfPresent([ExpeditionDecision].self, forKey: .decisionPlan) ?? []
        artifact = try values.decodeIfPresent(ArtifactAbility.self, forKey: .artifact)
    }
}

struct GhostSample: Codable, Equatable {
    var time: Double
    var distance: Double
    var stageIndex: Int
    var stageDistance: Double
    var x: Double
    var y: Double
    var roll: Bool

    var isValid: Bool {
        time.isFinite && (0...86_400).contains(time)
            && distance.isFinite && (0...10_000_000).contains(distance)
            && (0..<WorldStage.allCases.count).contains(stageIndex)
            && stageDistance.isFinite && (0...10_000_000).contains(stageDistance)
            && x.isFinite && (-5...5).contains(x) && y.isFinite && (-1...30).contains(y)
    }
}

struct GhostReplay: Codable, Identifiable, Equatable {
    static let maximumSamples = 3_600
    var course: GhostCourseKey
    var score: Int
    var completed: Bool
    var recordedAt: Date
    var samples: [GhostSample]
    var id: String {
        let choices = course.decisionPlan.map { "\($0.world).\($0.route.rawValue).\($0.perk?.rawValue ?? "none")" }.joined(separator: "-")
        return "\(course.mode.rawValue)-\(course.seed)-\(course.expert)-\(course.startWorld)-\(course.revision)-\(course.expeditionStyle.rawValue)-\(course.artifact?.rawValue ?? "none")-\(choices)"
    }
    var duration: Double { samples.last?.time ?? 0 }

    /// Invalid geometry and non-monotonic timestamps are rejected before rendering.
    func sanitized() -> GhostReplay? {
        guard course.isValid, recordedAt.timeIntervalSince1970.isFinite else { return nil }
        var safe: [GhostSample] = []
        for sample in samples.prefix(Self.maximumSamples) where sample.isValid {
            if let previous = safe.last {
                guard sample.time > previous.time, sample.distance >= previous.distance,
                      sample.stageIndex >= previous.stageIndex else { continue }
            }
            safe.append(sample)
        }
        guard safe.count >= 2, (safe.last?.time ?? 0) > (safe.first?.time ?? 0) else { return nil }
        return GhostReplay(course: course, score: min(1_000_000_000, max(0, score)), completed: completed,
                           recordedAt: recordedAt, samples: safe)
    }

    /// A binary search keeps playback cost independent of run length. Never blend
    /// across a portal: that would draw the ghost between unrelated worlds.
    func sample(at time: Double) -> GhostSample? {
        guard time.isFinite, let first = samples.first, let last = samples.last,
              time >= first.time, time <= last.time else { return nil }
        var lower = 0
        var upper = samples.count - 1
        while upper - lower > 1 {
            let mid = (lower + upper) / 2
            if samples[mid].time <= time { lower = mid } else { upper = mid }
        }
        let a = samples[lower], b = samples[upper]
        guard a.stageIndex == b.stageIndex, b.time > a.time else { return time >= b.time ? b : a }
        let t = min(1, max(0, (time - a.time) / (b.time - a.time)))
        func mix(_ start: Double, _ end: Double) -> Double { start + (end - start) * t }
        return GhostSample(time: time, distance: mix(a.distance, b.distance), stageIndex: a.stageIndex,
                           stageDistance: mix(a.stageDistance, b.stageDistance), x: mix(a.x, b.x),
                           y: mix(a.y, b.y), roll: t < 0.5 ? a.roll : b.roll)
    }

    func beats(_ other: GhostReplay) -> Bool {
        if completed != other.completed { return completed }
        if score != other.score { return score > other.score }
        if completed { return duration < other.duration }
        return (samples.last?.distance ?? 0) > (other.samples.last?.distance ?? 0)
    }
}

/// At most ten samples a second. Very long runs reduce sample density rather
/// than growing the save or abruptly truncating the opponent midway through.
struct GhostRecorder: Codable {
    private(set) var samples: [GhostSample] = []
    private(set) var sampleInterval: Double = 0.1

    mutating func append(_ sample: GhostSample, force: Bool = false) {
        guard sample.isValid else { return }
        if let last = samples.last {
            guard sample.time > last.time, sample.distance >= last.distance,
                  sample.stageIndex >= last.stageIndex else { return }
            guard force || sample.stageIndex != last.stageIndex || sample.time - last.time >= sampleInterval - 0.000_001 else { return }
        }
        if samples.count >= GhostReplay.maximumSamples {
            samples = samples.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
            sampleInterval *= 2
        }
        samples.append(sample)
    }

    func replay(course: GhostCourseKey, score: Int, completed: Bool, now: Date = Date()) -> GhostReplay? {
        GhostReplay(course: course, score: score, completed: completed, recordedAt: now, samples: samples).sanitized()
    }

    /// Checkpoint decoding is bounded too; old or malformed recording data must
    /// never affect the actual run's restore path.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let restored = (try? container.decode([GhostSample].self, forKey: .samples)) ?? []
        sampleInterval = max(0.1, min(60, (try? container.decode(Double.self, forKey: .sampleInterval)) ?? 0.1))
        if !sampleInterval.isFinite { sampleInterval = 0.1 }
        for sample in restored.prefix(GhostReplay.maximumSamples) { append(sample, force: true) }
    }
    init() {}
    private enum CodingKeys: String, CodingKey { case samples, sampleInterval }
}
