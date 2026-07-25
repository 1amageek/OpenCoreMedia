import Synchronization

final class CMSampleAttachmentDictionaryStorage:
    CMPlatformConcurrencyContract,
    Sendable
{
    private let values: Mutex<[String: CMAttachmentValue]>

    init(_ values: [String: CMAttachmentValue] = [:]) {
        self.values = Mutex(values)
    }

    func value(for key: String) -> CMAttachmentValue? {
        values.withLock { values in
            values[key]
        }
    }

    func setValue(
        _ value: CMAttachmentValue?,
        for key: String
    ) {
        values.withLock { values in
            values[key] = value
        }
    }

    func snapshot() -> [String: CMAttachmentValue] {
        values.withLock { values in
            values
        }
    }

    var count: Int {
        values.withLock { values in
            values.count
        }
    }

    var isEmpty: Bool {
        values.withLock { values in
            values.isEmpty
        }
    }

    func copy() -> CMSampleAttachmentDictionaryStorage {
        CMSampleAttachmentDictionaryStorage(snapshot())
    }

    func removeAll() {
        values.withLock { values in
            values.removeAll(keepingCapacity: true)
        }
    }
}
