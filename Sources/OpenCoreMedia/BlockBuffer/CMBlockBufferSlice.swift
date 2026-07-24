extension CMBlockBuffer {
    public struct Slice: CMBlockBufferProtocol {
        public let owner: CMBlockBuffer
        public let startIndex: Int
        public let endIndex: Int

        init(owner: CMBlockBuffer, bounds: Range<Int>) {
            self.owner = owner
            startIndex = bounds.lowerBound
            endIndex = bounds.upperBound
        }
    }
}
