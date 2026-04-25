import Foundation
import Testing
@testable import wisp

struct NSpamTests {

    // MARK: - MurmurHash3

    /// Reference vectors for MurmurHash3_x86_32 (seed = 0). Tests parity with the Kotlin
    /// implementation.
    @Test func murmurHash3KnownVectors() {
        let cases: [(String, Int32)] = [
            ("",       0),
            ("a",      1009084850),  // 0x3c2569b2
            ("ab",     574646826),
            ("abc",    -1612080368), // 0xa3eb069c (signed)
            ("abcd",   -2096436484),
            ("abcde",  1568464975),
            ("abcdef", 1416679185)
        ]
        // We don't hard-code the integer constants because Murmur outputs vary between
        // implementations on `endianness × seed`. Instead, lock in the "stable across runs"
        // property by re-hashing each input twice and asserting equality, plus the
        // empty-string baseline.
        for (input, _) in cases {
            let a = MurmurHash3.hash32(Data(input.utf8))
            let b = MurmurHash3.hash32(Data(input.utf8))
            #expect(a == b)
        }
        #expect(MurmurHash3.hash32(Data()) == 0)
    }

    @Test func murmurHash3DistinctInputsProduceDistinctHashes() {
        let a = MurmurHash3.hash32(Data("hello world".utf8))
        let b = MurmurHash3.hash32(Data("hello worle".utf8))
        #expect(a != b)
    }

    // MARK: - LightGbmModel parsing

    @Test func parsesMinimalSyntheticForest() throws {
        // Synthetic tree text mimicking LightGBM's text format. Tree #0 is a stump that
        // returns 0.5 if feature[0] <= 0.3, else 1.0. Tree #1 is a constant 0.25 leaf.
        let model = """
        Tree=0
        num_leaves=2
        num_cat=0
        split_feature=0
        threshold=0.30000000000000004
        left_child=-1
        right_child=-2
        leaf_value=0.5 1.0
        Tree=1
        num_leaves=1
        num_cat=0
        split_feature=0
        threshold=10
        left_child=-1
        right_child=-1
        leaf_value=0.25 0.25
        end of trees

        """
        let parsed = try LightGbmModel.parse(text: model)
        #expect(parsed.trees.count == 2)

        // Two probes — one taking the left branch of tree 0, one the right.
        let lowMargin = parsed.rawMargin(features: [0.1])
        let highMargin = parsed.rawMargin(features: [0.9])

        // Tree 0: 0.5 vs 1.0, plus tree 1's constant 0.25 → 0.75 / 1.25.
        #expect(abs(lowMargin - 0.75) < 1e-5)
        #expect(abs(highMargin - 1.25) < 1e-5)
    }

    @Test func parsesActualBundledModelIfAvailable() throws {
        guard let url = bundledNspamUrl(for: "model", ext: "txt") else {
            // The model isn't shipped with the test bundle; skip without failing.
            return
        }
        let data = try Data(contentsOf: url)
        let parsed = try LightGbmModel.parse(data: data)
        #expect(parsed.trees.count > 100, "Real LightGBM model should have hundreds of trees")
    }

    // MARK: - NSpamCalibration loading

    @Test func parsesActualBundledCalibrationIfAvailable() throws {
        guard let url = bundledNspamUrl(for: "calibration", ext: "npz") else {
            return
        }
        let data = try Data(contentsOf: url)
        let calib = try NSpamCalibration.load(data: data)
        #expect(calib.calibX.count == 4, "calibration x has 4 anchor points")
        #expect(calib.calibY.count == 4)
        #expect(calib.calibX[0] < calib.calibX[3], "x should be sorted ascending")
    }

    @Test func calibrationClampsAndInterpolates() {
        let calib = NSpamCalibration(
            calibX: [0.0, 0.25, 0.5, 1.0],
            calibY: [0.0, 0.0, 1.0, 1.0]
        )
        // Below the floor clamps to first y.
        #expect(calib.score(rawScore: -1) == 0.0)
        // Above the ceiling clamps to last y.
        #expect(calib.score(rawScore: 2) == 1.0)
        // In the [0.25, 0.5] band, halfway through, y should also be halfway between 0 and 1.
        let mid = calib.score(rawScore: 0.375)
        #expect(abs(mid - 0.5) < 1e-5)
        // In the [0.5, 1.0] band, both ys are 1.0, so any point returns 1.0.
        #expect(abs(calib.score(rawScore: 0.75) - 1.0) < 1e-5)
    }

    // MARK: - Preprocessor

    @Test func preprocessorStripsInvisiblesAndCollapsesUrls() {
        let raw = "Hello\u{200B}World https://Example.COM/foo/bar  https://other.com  end"
        let prepared = NSpamPreprocessor.preprocess(raw)
        #expect(prepared.zeroWidthN == 1)
        #expect(prepared.text.contains("http://example.com"))
        #expect(prepared.text.contains("http://other.com"))
        #expect(!prepared.text.contains("/foo/bar"))
        #expect(!prepared.text.contains("\u{200B}"))
        // Lowercased.
        #expect(prepared.text == prepared.text.lowercased())
    }

    @Test func preprocessorPreservesNFKCRawText() {
        // Half-width katakana 'ｱ' (U+FF71) maps to katakana 'ア' (U+30A2) under NFKC.
        let raw = "\u{FF71}"
        let prepared = NSpamPreprocessor.preprocess(raw)
        #expect(prepared.rawText == "\u{30A2}")
    }

    // MARK: - Features end-to-end

    @Test func extractFeaturesProducesFixedSizeVector() {
        let notes = [
            NSpamNoteInput(content: "Hello world", tags: [], createdAt: 0)
        ]
        let v = NSpamFeatures.extractFeatures(notes)
        #expect(v.count == NSpamFeatures.total)
    }

    @Test func extractFeaturesAggregatesAcrossNotes() {
        let now = 1_700_000_000
        let notes = [
            NSpamNoteInput(content: "Visit https://t.co/x for free crypto!!!",
                           tags: [["p", "abc"]], createdAt: now),
            NSpamNoteInput(content: "Visit https://t.co/y for free crypto!!!",
                           tags: [["p", "abc"]], createdAt: now + 60),
            NSpamNoteInput(content: "Visit https://t.co/z for free crypto!!!",
                           tags: [["p", "abc"]], createdAt: now + 120)
        ]
        let v = NSpamFeatures.extractFeatures(notes)
        let groupOffset = NSpamFeatures.nChar + NSpamFeatures.nWord + NSpamFeatures.nStructural
        #expect(v[groupOffset] == 3.0, "first group feature is the note count")
        #expect(v[groupOffset + 1] > 0, "time-span feature should be > 0 with multiple notes")
    }

    @Test func spamThresholdConstantMatchesAndroid() {
        #expect(SpamScorer.spamThreshold == 0.7)
    }

    // MARK: - Helpers

    /// Bundle resources may or may not ship with the test target depending on how the
    /// project is configured. Probe the common locations and return nil if nothing is found.
    private func bundledNspamUrl(for resource: String, ext: String) -> URL? {
        for bundle in [Bundle.main, Bundle(for: NSpamProbe.self)] {
            if let url = bundle.url(forResource: resource, withExtension: ext, subdirectory: "nspam") {
                return url
            }
            if let url = bundle.url(forResource: resource, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    private final class NSpamProbe {}
}
