public struct CMSampleAttachmentKey:
    RawRepresentable,
    Sendable,
    Hashable
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let notSync = Self(rawValue: "NotSync")
    public static let partialSync = Self(rawValue: "PartialSync")
    public static let hasRedundantCoding =
        Self(rawValue: "HasRedundantCoding")
    public static let isDependedOnByOthers =
        Self(rawValue: "IsDependedOnByOthers")
    public static let dependsOnOthers =
        Self(rawValue: "DependsOnOthers")
    public static let earlierDisplayTimesAllowed =
        Self(rawValue: "EarlierDisplayTimesAllowed")
    public static let displayImmediately =
        Self(rawValue: "DisplayImmediately")
    public static let doNotDisplay =
        Self(rawValue: "DoNotDisplay")
    public static let hevcTemporalLevelInfo =
        Self(rawValue: "HEVCTemporalLevelInfo")
    public static let hevcTemporalSubLayerAccess =
        Self(rawValue: "HEVCTemporalSubLayerAccess")
    public static let hevcStepwiseTemporalSubLayerAccess =
        Self(rawValue: "HEVCStepwiseTemporalSubLayerAccess")
    public static let hevcSyncSampleNALUnitType =
        Self(rawValue: "HEVCSyncSampleNALUnitType")
    public static let audioIndependentSampleDecoderRefreshCount =
        Self(rawValue: "AudioIndependentSampleDecoderRefreshCount")
}
