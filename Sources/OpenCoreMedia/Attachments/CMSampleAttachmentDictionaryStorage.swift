#if !hasFeature(Embedded)
import Synchronization
#endif

final class CMSampleAttachmentDictionaryStorage:
    CMPlatformConcurrencyContract
{
#if hasFeature(Embedded)
    private var embeddedValues: [String: CMAttachmentValue]
#else
    private let values: Mutex<[String: CMAttachmentValue]>
#endif

    init(_ values: [String: CMAttachmentValue] = [:]) {
#if hasFeature(Embedded)
        embeddedValues = values
#else
        self.values = Mutex(values)
#endif
    }

    func value(for key: String) -> CMAttachmentValue? {
#if hasFeature(Embedded)
        embeddedValues[key]
#else
        values.withLock { values in
            values[key]
        }
#endif
    }

    func setValue(
        _ value: CMAttachmentValue?,
        for key: String
    ) {
#if hasFeature(Embedded)
        embeddedValues[key] = value
#else
        values.withLock { values in
            values[key] = value
        }
#endif
    }

    func snapshot() -> [String: CMAttachmentValue] {
#if hasFeature(Embedded)
        embeddedValues
#else
        values.withLock { values in
            values
        }
#endif
    }

    var count: Int {
#if hasFeature(Embedded)
        embeddedValues.count
#else
        values.withLock { values in
            values.count
        }
#endif
    }

    var isEmpty: Bool {
#if hasFeature(Embedded)
        embeddedValues.isEmpty
#else
        values.withLock { values in
            values.isEmpty
        }
#endif
    }

    func copy() -> CMSampleAttachmentDictionaryStorage {
        CMSampleAttachmentDictionaryStorage(snapshot())
    }

    func removeAll() {
#if hasFeature(Embedded)
        embeddedValues.removeAll(keepingCapacity: true)
#else
        values.withLock { values in
            values.removeAll(keepingCapacity: true)
        }
#endif
    }
}
