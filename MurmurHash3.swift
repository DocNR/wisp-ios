import Foundation

/// 32-bit MurmurHash3, byte-for-byte port of Android wisp's `com.wisp.app.ml.MurmurHash3`.
/// Returns a signed `Int32` so callers can replicate Kotlin's
/// `kotlin.math.abs(hash.toLong())` exactly (the .toLong() side-steps Int32.min).
enum MurmurHash3 {
    private static let c1: UInt32 = 0xcc9e2d51
    private static let c2: UInt32 = 0x1b873593
    private static let fmix1: UInt32 = 0x85ebca6b
    private static let fmix2: UInt32 = 0xc2b2ae35

    static func hash32(_ data: Data, seed: UInt32 = 0) -> Int32 {
        var h1 = seed
        let len = data.count
        let nblocks = len / 4

        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let bytes = buf.bindMemory(to: UInt8.self).baseAddress
            guard let bytes else { return }
            for i in 0..<nblocks {
                let off = i * 4
                var k1 = UInt32(bytes[off]) |
                    (UInt32(bytes[off + 1]) << 8) |
                    (UInt32(bytes[off + 2]) << 16) |
                    (UInt32(bytes[off + 3]) << 24)
                k1 = k1 &* c1
                k1 = rotl(k1, 15)
                k1 = k1 &* c2
                h1 ^= k1
                h1 = rotl(h1, 13)
                h1 = (h1 &* 5) &+ 0xe6546b64
            }

            let tail = nblocks * 4
            var k1: UInt32 = 0
            switch len & 3 {
            case 3:
                k1 ^= UInt32(bytes[tail + 2]) << 16
                k1 ^= UInt32(bytes[tail + 1]) << 8
                k1 ^= UInt32(bytes[tail])
                k1 = k1 &* c1; k1 = rotl(k1, 15); k1 = k1 &* c2; h1 ^= k1
            case 2:
                k1 ^= UInt32(bytes[tail + 1]) << 8
                k1 ^= UInt32(bytes[tail])
                k1 = k1 &* c1; k1 = rotl(k1, 15); k1 = k1 &* c2; h1 ^= k1
            case 1:
                k1 ^= UInt32(bytes[tail])
                k1 = k1 &* c1; k1 = rotl(k1, 15); k1 = k1 &* c2; h1 ^= k1
            default: break
            }
        }

        h1 ^= UInt32(truncatingIfNeeded: len)
        h1 ^= h1 >> 16
        h1 = h1 &* fmix1
        h1 ^= h1 >> 13
        h1 = h1 &* fmix2
        h1 ^= h1 >> 16
        return Int32(bitPattern: h1)
    }

    @inline(__always)
    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x &<< n) | (x &>> (32 - n))
    }
}
