#if !hasFeature(Embedded)
import Synchronization
#endif

final class CMAttachmentStorageReference: CMAttachmentStorage {
#if hasFeature(Embedded)
    private var embeddedValues: [String: CMAttachment]
#else
    private let values: Mutex<[String: CMAttachment]>
#endif

    init() {
#if hasFeature(Embedded)
        embeddedValues = [:]
#else
        values = Mutex([:])
#endif
    }

    func attachment(for key: String) -> CMAttachment? {
#if hasFeature(Embedded)
        embeddedValues[key]
#else
        values.withLock { values in
            values[key]
        }
#endif
    }

    func attachments(
        for mode: CMAttachmentMode
    ) -> [String: CMAttachmentValue] {
#if hasFeature(Embedded)
        Self.values(in: embeddedValues, matching: mode)
#else
        values.withLock { values in
            Self.values(in: values, matching: mode)
        }
#endif
    }

    func setAttachment(
        _ attachment: CMAttachment,
        for key: String
    ) {
#if hasFeature(Embedded)
        embeddedValues[key] = attachment
#else
        values.withLock { values in
            values[key] = attachment
        }
#endif
    }

    func setAttachments(
        _ attachments: [String: CMAttachmentValue],
        mode: CMAttachmentMode
    ) {
#if hasFeature(Embedded)
        Self.set(attachments, mode: mode, in: &embeddedValues)
#else
        values.withLock { values in
            Self.set(attachments, mode: mode, in: &values)
        }
#endif
    }

    func removeAttachment(for key: String) {
#if hasFeature(Embedded)
        embeddedValues.removeValue(forKey: key)
#else
        _ = values.withLock { values in
            values.removeValue(forKey: key)
        }
#endif
    }

    func removeAllAttachments() {
#if hasFeature(Embedded)
        embeddedValues.removeAll(keepingCapacity: true)
#else
        values.withLock { values in
            values.removeAll(keepingCapacity: true)
        }
#endif
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
