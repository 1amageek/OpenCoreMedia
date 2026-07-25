/// Converts a platform-owned attachment value at an explicit package boundary.
///
/// OpenCoreMedia never retains `PlatformValue`. An adapter must return an owned
/// portable value before the platform object may be released.
public protocol CMAttachmentPlatformAdapter {
    associatedtype PlatformValue

    func portableValue(
        from value: borrowing PlatformValue
    ) throws -> CMAttachmentValue

    func platformValue(
        from value: CMAttachmentValue
    ) throws -> PlatformValue
}
