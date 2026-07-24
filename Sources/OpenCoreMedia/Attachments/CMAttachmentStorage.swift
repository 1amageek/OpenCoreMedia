protocol CMAttachmentStorage:
    CMPlatformConcurrencyContract
{
    func attachment(
        for key: String
    ) -> CMAttachment?
    func attachments(
        for mode: CMAttachmentMode
    ) -> [String: CMAttachmentValue]
    func setAttachment(
        _ attachment: CMAttachment,
        for key: String
    )
    func setAttachments(
        _ attachments: [String: CMAttachmentValue],
        mode: CMAttachmentMode
    )
    func removeAttachment(for key: String)
    func removeAllAttachments()
}
