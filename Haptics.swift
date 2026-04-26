import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreHaptics)
import CoreHaptics
#endif

@MainActor
final class Haptics {
    static let shared = Haptics()

    #if canImport(CoreHaptics) && !os(tvOS)
    private let supportsCoreHaptics: Bool
    private var engine: CHHapticEngine?
    #endif

    #if canImport(UIKit) && !os(tvOS)
    private let lightGen = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let successGen = UINotificationFeedbackGenerator()
    #endif

    private init() {
        #if canImport(CoreHaptics) && !os(tvOS)
        supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        #endif
    }

    func blip() {
        #if canImport(UIKit) && !os(tvOS)
        lightGen.prepare()
        lightGen.impactOccurred(intensity: 0.3)
        #endif
    }

    func pulse() {
        #if canImport(UIKit) && !os(tvOS)
        mediumGen.prepare()
        mediumGen.impactOccurred(intensity: 0.6)
        #endif
    }

    func zapBuzz() {
        #if canImport(CoreHaptics) && canImport(UIKit) && !os(tvOS)
        guard supportsCoreHaptics else {
            successGen.prepare()
            successGen.notificationOccurred(.success)
            return
        }
        do {
            try ensureEngineRunning()
            let e1 = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.78),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: 0,
                duration: 0.060
            )
            let e2 = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                ],
                relativeTime: 0.100,
                duration: 0.100
            )
            let pattern = try CHHapticPattern(events: [e1, e2], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            NSLog("[Haptics] zapBuzz failed: %@", String(describing: error))
            successGen.notificationOccurred(.success)
        }
        #endif
    }

    #if canImport(CoreHaptics) && !os(tvOS)
    private func ensureEngineRunning() throws {
        if engine == nil {
            let e = try CHHapticEngine()
            e.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            try e.start()
            engine = e
        } else {
            try engine?.start()
        }
    }
    #endif
}
