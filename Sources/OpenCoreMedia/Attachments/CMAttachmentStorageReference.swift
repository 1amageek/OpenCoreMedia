import Synchronization

final class CMAttachmentStorageReference:
    CMAttachmentStorage,
    Sendable
{
    private let values: CMStateLock<[String: CMAttachment]>

    init() {
        values = CMStateLock([:])
    }

    func attachment(for key: String) -> CMAttachment? {
        values.withLock { values in
            values[key]
        }
    }

    func attachments(
        for mode: CMAttachmentMode
    ) -> [String: CMAttachmentValue] {
        let snapshot = values.withLock { values in
            values
        }
        return Self.values(in: snapshot, matching: mode)
    }

    func setAttachment(
        _ attachment: CMAttachment,
        for key: String
    ) {
        values.withLock { values in
            values[key] = attachment
        }
    }

    func setAttachments(
        _ attachments: [String: CMAttachmentValue],
        mode: CMAttachmentMode
    ) {
        values.withLock { values in
            Self.set(attachments, mode: mode, in: &values)
        }
    }

    func removeAttachment(for key: String) {
        _ = values.withLock { values in
            values.removeValue(forKey: key)
        }
    }

    func removeAllAttachments() {
        values.withLock { values in
            values.removeAll(keepingCapacity: true)
        }
    }

    private static func values(
        in attachments: [String: CMAttachment],
        matching mode: CMAttachmentMode
    ) -> [String: CMAttachmentValue] {
        var matching: [String: CMAttachmentValue] = [:]
        matching.reserveCapacity(attachments.count)
        for (key, attachment) in attachments
        where attachment.mode == mode {
            matching[key] = attachment.value
        }
        return matching
    }

    private static func set(
        _ attachments: [String: CMAttachmentValue],
        mode: CMAttachmentMode,
        in values: inout [String: CMAttachment]
    ) {
        for (key, value) in attachments {
            values[key] = CMAttachment(value: value, mode: mode)
        }
    }
}
