import Foundation

/// A minimal reader for AppleDouble "._name" sidecar files: just enough to tell whether a sidecar
/// holds something a person would miss.
///
/// On exFAT, FAT32 and network drives, macOS keeps a file's Finder tags, comments, colour label
/// and resource fork in its "._" sidecar. Deleting such a sidecar silently loses that metadata,
/// so Reclaim only treats a sidecar as junk when it carries nothing beyond disposable system
/// bookkeeping (download quarantine, provenance, last-used date).
///
/// Layout (big-endian): magic 0x00051607, version, 16-byte filler, entry count, then 12-byte
/// entries (id, offset, length). Entry 2 is the resource fork; entry 9 is the 32-byte FinderInfo,
/// optionally followed by an "ATTR" block listing extended attributes by name.
public enum AppleDouble {
    public struct Contents: Equatable, Sendable {
        public var resourceForkLength = 0
        public var finderInfo: [UInt8] = []
        public var attributeNames: [String] = []

        /// True when deleting the sidecar would lose something a person set or would miss.
        public var holdsUserMetadata: Bool {
            if resourceForkLength > 0 { return true }
            if AppleDouble.finderInfoIsMeaningful(finderInfo) { return true }
            // Unknown attributes count as meaningful: when unsure, keep the file.
            return attributeNames.contains { !AppleDouble.disposableAttributes.contains($0) }
        }
    }

    static let magic: UInt32 = 0x0005_1607
    static let resourceForkID: UInt32 = 2
    static let finderInfoID: UInt32 = 9
    static let attributesMagic: UInt32 = 0x4154_5452 // "ATTR"

    /// System bookkeeping that is safe to lose.
    public static let disposableAttributes: Set<String> = [
        "com.apple.quarantine",
        "com.apple.provenance",
        "com.apple.lastuseddate#PS",
        "com.apple.macl",
        "com.apple.metadata:kMDItemWhereFroms",
        "com.apple.metadata:kMDItemDownloadedDate",
        "com.apple.TextEncoding",
    ]

    /// Parses the sidecar at `path`, or returns nil if it isn't an AppleDouble file.
    public static func read(_ path: String, limit: Int = 256 * 1024) -> Contents? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit) else { return nil }
        return parse([UInt8](data))
    }

    public static func parse(_ bytes: [UInt8]) -> Contents? {
        guard u32(bytes, 0) == magic, let count = u16(bytes, 24) else { return nil }
        var contents = Contents()
        for index in 0..<Int(count) {
            let base = 26 + index * 12
            guard let id = u32(bytes, base), let offset = u32(bytes, base + 4), let length = u32(bytes, base + 8) else { break }
            switch id {
            case resourceForkID:
                contents.resourceForkLength = resourceDataLength(bytes, forkAt: Int(offset), forkLength: Int(length))
            case finderInfoID:
                let start = Int(offset)
                contents.finderInfo = Array(bytes[min(start, bytes.count)..<min(start + 32, bytes.count)])
                if length > 32 { contents.attributeNames = attributeNames(bytes, attributesAt: start + 34) }
            default:
                continue
            }
        }
        return contents
    }

    /// Bytes of actual resource data in a resource fork. macOS writes an *empty* 286-byte fork
    /// (256-byte header + 30-byte map, no data) into every sidecar it creates, so the entry's
    /// length alone says nothing; the fork header's data-length field does.
    static func resourceDataLength(_ bytes: [UInt8], forkAt offset: Int, forkLength: Int) -> Int {
        guard forkLength > 0 else { return 0 }
        guard let dataLength = u32(bytes, offset + 8) else {
            // Header beyond what was read: only a fork larger than the empty one can hold data.
            return forkLength > 286 ? forkLength : 0
        }
        return Int(dataLength)
    }

    /// FinderInfo matters if it sets a colour label or a classic type/creator code.
    static func finderInfoIsMeaningful(_ info: [UInt8]) -> Bool {
        guard info.count >= 10 else { return false }
        let typeAndCreator = info[0..<8]
        let flags = UInt16(info[8]) << 8 | UInt16(info[9])
        let colourLabel = (flags >> 1) & 0x7
        return typeAndCreator.contains { $0 != 0 } || colourLabel != 0
    }

    /// Reads the attribute names from an "ATTR" block (36-byte header, then 4-byte-aligned entries
    /// of offset, length, flags, name length and a NUL-terminated name).
    static func attributeNames(_ bytes: [UInt8], attributesAt start: Int) -> [String] {
        guard u32(bytes, start) == attributesMagic, let count = u16(bytes, start + 34) else { return [] }
        var names: [String] = []
        var cursor = start + 36
        for _ in 0..<Int(count) {
            guard cursor + 11 <= bytes.count else { break }
            let nameLength = Int(bytes[cursor + 10])
            let nameStart = cursor + 11
            guard nameLength > 0, nameStart + nameLength <= bytes.count else { break }
            let nameBytes = bytes[nameStart..<(nameStart + nameLength)].prefix { $0 != 0 }
            names.append(String(decoding: nameBytes, as: UTF8.self))
            cursor = (nameStart + nameLength + 3) & ~3
        }
        return names
    }

    static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return bytes[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
}
