import Foundation
import Observation

/// Per-category Proof of Work preferences. Mirrors the Android `PowPreferences` keys
/// so the conceptual settings line up across platforms. Storage is global (not keyed
/// by pubkey) — same as `AppSettings`.
@Observable
@MainActor
final class PowPreferences {
    static let shared = PowPreferences()

    nonisolated static let minDifficulty = 8
    nonisolated static let maxDifficulty = 32

    private struct Keys {
        static let noteEnabled = "pow_note_enabled"
        static let noteDifficulty = "pow_note_difficulty"
        static let reactionEnabled = "pow_reaction_enabled"
        static let reactionDifficulty = "pow_reaction_difficulty"
        static let dmEnabled = "pow_dm_enabled"
        static let dmDifficulty = "pow_dm_difficulty"
    }

    var notePowEnabled: Bool {
        didSet { UserDefaults.standard.set(notePowEnabled, forKey: Keys.noteEnabled) }
    }
    var noteDifficulty: Int {
        didSet {
            let clamped = Self.clamp(noteDifficulty)
            if clamped != noteDifficulty {
                noteDifficulty = clamped
                return
            }
            UserDefaults.standard.set(noteDifficulty, forKey: Keys.noteDifficulty)
        }
    }
    var reactionPowEnabled: Bool {
        didSet { UserDefaults.standard.set(reactionPowEnabled, forKey: Keys.reactionEnabled) }
    }
    var reactionDifficulty: Int {
        didSet {
            let clamped = Self.clamp(reactionDifficulty)
            if clamped != reactionDifficulty {
                reactionDifficulty = clamped
                return
            }
            UserDefaults.standard.set(reactionDifficulty, forKey: Keys.reactionDifficulty)
        }
    }
    var dmPowEnabled: Bool {
        didSet { UserDefaults.standard.set(dmPowEnabled, forKey: Keys.dmEnabled) }
    }
    var dmDifficulty: Int {
        didSet {
            let clamped = Self.clamp(dmDifficulty)
            if clamped != dmDifficulty {
                dmDifficulty = clamped
                return
            }
            UserDefaults.standard.set(dmDifficulty, forKey: Keys.dmDifficulty)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.notePowEnabled = defaults.object(forKey: Keys.noteEnabled) as? Bool ?? true
        self.noteDifficulty = Self.clamp(defaults.object(forKey: Keys.noteDifficulty) as? Int ?? 16)
        self.reactionPowEnabled = defaults.object(forKey: Keys.reactionEnabled) as? Bool ?? true
        self.reactionDifficulty = Self.clamp(defaults.object(forKey: Keys.reactionDifficulty) as? Int ?? 12)
        self.dmPowEnabled = defaults.object(forKey: Keys.dmEnabled) as? Bool ?? true
        self.dmDifficulty = Self.clamp(defaults.object(forKey: Keys.dmDifficulty) as? Int ?? 12)
    }

    nonisolated private static func clamp(_ n: Int) -> Int {
        max(minDifficulty, min(maxDifficulty, n))
    }

    /// Lockless read for off-main publish paths (reactions, DM gift wraps). Reads
    /// UserDefaults directly with the same defaults as `init`, so a background actor
    /// does not need to hop to the MainActor just to consult the user's settings.
    nonisolated static func snapshot() -> Snapshot {
        let d = UserDefaults.standard
        return Snapshot(
            noteEnabled: d.object(forKey: Keys.noteEnabled) as? Bool ?? true,
            noteDifficulty: clamp(d.object(forKey: Keys.noteDifficulty) as? Int ?? 16),
            reactionEnabled: d.object(forKey: Keys.reactionEnabled) as? Bool ?? true,
            reactionDifficulty: clamp(d.object(forKey: Keys.reactionDifficulty) as? Int ?? 12),
            dmEnabled: d.object(forKey: Keys.dmEnabled) as? Bool ?? true,
            dmDifficulty: clamp(d.object(forKey: Keys.dmDifficulty) as? Int ?? 12)
        )
    }

    struct Snapshot: Sendable {
        let noteEnabled: Bool
        let noteDifficulty: Int
        let reactionEnabled: Bool
        let reactionDifficulty: Int
        let dmEnabled: Bool
        let dmDifficulty: Int
    }
}
