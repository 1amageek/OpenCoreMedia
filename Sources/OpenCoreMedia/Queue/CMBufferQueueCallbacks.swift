public struct CMBufferQueueCallbacks<Element: Sendable>: Sendable {
    public let duration: @Sendable (borrowing Element) -> CMTime
    public let decodeTimeStamp:
        (@Sendable (borrowing Element) -> CMTime)?
    public let presentationTimeStamp:
        (@Sendable (borrowing Element) -> CMTime)?
    public let isDataReady:
        (@Sendable (borrowing Element) -> Bool)?
    public let compare:
        (@Sendable (borrowing Element, borrowing Element) -> Bool)?
    public let size:
        (@Sendable (borrowing Element) -> Int)?

    public init(
        duration: @escaping @Sendable (borrowing Element) -> CMTime,
        decodeTimeStamp:
            (@Sendable (borrowing Element) -> CMTime)? = nil,
        presentationTimeStamp:
            (@Sendable (borrowing Element) -> CMTime)? = nil,
        isDataReady:
            (@Sendable (borrowing Element) -> Bool)? = nil,
        compare:
            (
                @Sendable (
                    borrowing Element,
                    borrowing Element
                ) -> Bool
            )? = nil,
        size: (@Sendable (borrowing Element) -> Int)? = nil
    ) {
        self.duration = duration
        self.decodeTimeStamp = decodeTimeStamp
        self.presentationTimeStamp = presentationTimeStamp
        self.isDataReady = isDataReady
        self.compare = compare
        self.size = size
    }
}
