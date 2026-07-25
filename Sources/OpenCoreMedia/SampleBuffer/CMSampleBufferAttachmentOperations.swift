public func CMSampleBufferGetSampleAttachmentsArray<
    Buffer: CMSampleBuffer
>(
    _ sampleBuffer: borrowing Buffer,
    createIfNecessary: Bool
) -> CMSampleAttachmentsArray? {
    sampleBuffer.sampleAttachments(
        createIfNecessary: createIfNecessary
    )
}
