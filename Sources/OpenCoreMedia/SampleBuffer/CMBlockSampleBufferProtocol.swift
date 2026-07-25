public protocol CMBlockSampleBufferProtocol:
    AnyObject,
    CMAttachmentStorageBearerProtocol,
    CMPlatformConcurrencyContract
{
    var isValid: Bool { get }
    var dataReadiness: CMSampleBufferDataReadiness { get }
    var sampleAttachments: CMSampleAttachmentsArray { get }

    func sampleCount() throws(CMSampleBufferError) -> Int
    func formatDescription()
        throws(CMSampleBufferError) -> any CMFormatDescription
    func timingInfo(
        at index: Int
    ) throws(CMSampleBufferError) -> CMSampleTimingInfo
    func sampleSize(at index: Int) throws(CMSampleBufferError) -> Int?
    func dataBuffer() throws(CMSampleBufferError) -> CMBlockBuffer
    func sampleData(
        at index: Int
    ) throws(CMSampleBufferError) -> CMBlockBuffer.Slice
    func sampleAttachments(
        createIfNecessary: Bool
    ) -> CMSampleAttachmentsArray?
    func setDataReadiness(
        _ readiness: CMSampleBufferDataReadiness
    ) throws(CMSampleBufferError)
    func makeDataReady() async throws(CMSampleBufferError)
    func invalidate() throws(CMSampleBufferError)
}
