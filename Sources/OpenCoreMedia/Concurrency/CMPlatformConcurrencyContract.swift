#if hasFeature(Embedded)
public protocol CMPlatformConcurrencyContract {}
#else
public protocol CMPlatformConcurrencyContract: Sendable {}
#endif
