extension CMBlockBuffer {
    public typealias Error = CMBlockBufferError

    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let assureMemoryNow = Flags(rawValue: 1 << 0)
        public static let alwaysCopyData = Flags(rawValue: 1 << 1)
        public static let dontOptimizeDepth = Flags(rawValue: 1 << 2)
        public static let permitEmptyReference = Flags(rawValue: 1 << 3)
    }
}
