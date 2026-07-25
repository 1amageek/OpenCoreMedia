public struct CMSampleAttachmentsArray:
    RandomAccessCollection,
    CMPlatformConcurrencyContract
{
    public typealias Index = Int
    public typealias Element = CMSampleAttachmentDictionary

    private let storages: [CMSampleAttachmentDictionaryStorage]

    init(storages: [CMSampleAttachmentDictionaryStorage]) {
        self.storages = storages
    }

    public var startIndex: Int {
        storages.startIndex
    }

    public var endIndex: Int {
        storages.endIndex
    }

    public func index(after index: Int) -> Int {
        storages.index(after: index)
    }

    public func index(before index: Int) -> Int {
        storages.index(before: index)
    }

    public subscript(index: Int) -> CMSampleAttachmentDictionary {
        CMSampleAttachmentDictionary(storage: storages[index])
    }

    public func attachment(
        at index: Int
    ) throws(CMSampleBufferError) -> CMSampleAttachmentDictionary {
        guard storages.indices.contains(index) else {
            throw .sampleIndexOutOfBounds(
                index: index,
                count: storages.count
            )
        }
        return CMSampleAttachmentDictionary(storage: storages[index])
    }
}
