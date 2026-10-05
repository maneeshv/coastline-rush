import Foundation

/// Profile and active run share a single save value so a rescue purchase, board use,
/// or final banking operation cannot be restored without its corresponding run.
struct ControllerSave: Codable {
    var version = 1
    var profile: PlayerProfile
    var session: RunSession?

    private enum CodingKeys: String, CodingKey { case version, profile, session }

    init(profile: PlayerProfile, session: RunSession?) {
        self.profile = profile
        self.session = session
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        profile = try values.decode(PlayerProfile.self, forKey: .profile)
        // A damaged or no-longer-readable transient race must never erase the
        // authoritative wallet, unlocks, and records saved beside it.
        session = try? values.decodeIfPresent(RunSession.self, forKey: .session)
    }
}

struct RunSession: Codable {
    var run: RunnerSimulation
    var hasRevived: Bool
    var spentRunKeys: Int
    var isDailyRun: Bool
    var dailyRunDate: String
    var ghostRecorder: GhostRecorder? = nil
    var ghostCourse: GhostCourseKey? = nil

    init(run: RunnerSimulation, hasRevived: Bool, spentRunKeys: Int, isDailyRun: Bool,
         dailyRunDate: String, ghostRecorder: GhostRecorder? = nil, ghostCourse: GhostCourseKey? = nil) {
        self.run = run; self.hasRevived = hasRevived; self.spentRunKeys = spentRunKeys
        self.isDailyRun = isDailyRun; self.dailyRunDate = dailyRunDate
        self.ghostRecorder = ghostRecorder; self.ghostCourse = ghostCourse
    }

    private enum CodingKeys: String, CodingKey {
        case run, hasRevived, spentRunKeys, isDailyRun, dailyRunDate, ghostRecorder, ghostCourse
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        run = try values.decode(RunnerSimulation.self, forKey: .run)
        hasRevived = try values.decodeIfPresent(Bool.self, forKey: .hasRevived) ?? false
        spentRunKeys = try values.decodeIfPresent(Int.self, forKey: .spentRunKeys) ?? 0
        isDailyRun = try values.decodeIfPresent(Bool.self, forKey: .isDailyRun) ?? false
        dailyRunDate = try values.decodeIfPresent(String.self, forKey: .dailyRunDate) ?? ""
        // Optional replay corruption must not discard the actual playable run.
        let course = try? values.decodeIfPresent(GhostCourseKey.self, forKey: .ghostCourse)
        if let course, course.isValid, course.mode == run.mode, course.expert == run.expert,
           course.seed == run.runSeed, course.startWorld == run.startWorldIndex {
            ghostCourse = course
            ghostRecorder = try? values.decodeIfPresent(GhostRecorder.self, forKey: .ghostRecorder)
        }
    }
}

enum RunCheckpointStore {
    private static let saveKey = "coastlineRush.controller.v1"

    static func load(defaults: UserDefaults = .standard) -> ControllerSave? {
        guard let data = defaults.data(forKey: saveKey),
              let save = try? JSONDecoder().decode(ControllerSave.self, from: data),
              save.version == 1 else { return nil }
        return save
    }

    @discardableResult
    static func save(_ record: ControllerSave, defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else { return false }
        defaults.set(data, forKey: saveKey)
        return true
    }
}
