public protocol CMSampleBuffer:
    AnyObject,
    CMAttachmentBearerProtocol,
    CMPlatformConcurrencyContract
{
    associatedtype ImageBuffer: CVPixelBuffer
    associatedtype VideoFormat: CMVideoFormatDescription
    associatedtype TimingCopy: CMSampleBuffer

    var isValid: Bool { get }
    var dataReadiness: CMSampleBufferDataReadiness { get }
    var sampleAttachments: CMSampleAttachmentsArray { get }

    func sampleCount() throws(CMSampleBufferError) -> Int
    func formatDescription()
        throws(CMSampleBufferError) -> VideoFormat
    func timingInfo(
        at index: Int
    ) throws(CMSampleBufferError) -> CMSampleTimingInfo
    func imageBuffer()
        throws(CMSampleBufferError) -> ImageBuffer
    func copy(
        withTiming timing: [CMSampleTimingInfo]
    ) throws(CMSampleBufferError) -> TimingCopy
    func sampleAttachments(
        createIfNecessary: Bool
    ) -> CMSampleAttachmentsArray?
    func setDataReadiness(
        _ readiness: CMSampleBufferDataReadiness
    ) throws(CMSampleBufferError)
    func invalidate() throws(CMSampleBufferError)
}
