# Apple Core Media API Trace

## Baseline

- Review dates: 2026-07-24 and 2026-07-25
- SDK: macOS 27.0 from the active Xcode beta
- Documentation: Apple Developer Documentation read with `remark`
- Local evidence: `CoreMedia.framework/Headers`, the SDK symbol graph, package
  source, and behavior tests

## Responsibility trace

| Apple family | Header evidence | Open implementation | Status | Required evidence |
|---|---|---|---|---|
| `CMTime` | `CMTime.h` | Rational values, flags, arithmetic, rounding, epochs | Partial | Broader overflow and epoch differential matrix |
| `CMTimeRange` and `CMTimeMapping` | `CMTimeRange.h` | Ranges, mapping, clamp, fold, affine conversion | Implemented | Apple differential fixtures |
| `CMBlockBuffer` | `CMBlockBuffer.h` | Segmented external leases, append, buffer/slice references, range-aware contiguity, cross-segment byte operations, explicit materialization | Partial | Deferred allocation, allocator-backed construction/append, raw-buffer slice overloads |
| `CMFormatDescription` | `CMFormatDescription.h` | Immutable video description | Partial | Audio, metadata, codec extensions |
| `CMSampleBuffer` | `CMSampleBuffer.h` | One-image sample, timing, readiness, invalidation, timing-only copy | Partial | Multi-sample, block payload, size arrays, callbacks |
| Buffer-level attachments | `CMAttachment.h`, `CMSampleBuffer.h` | Swift bearer overlay, recursively typed portable values, modes, C-derived operations, and timing-copy propagation | Partial | Byte values, platform-object adapters, and `CMBlockBuffer` bearer conformance |
| Per-sample attachments | `CMSampleBuffer.h`, SDK Swift overlay | Lazy fixed-length array, mutable dictionary views, standard keys, typed Boolean access, and independent timing-copy metadata | Partial | Multi-sample payload carrier and broader codec-specific values |
| Clocks and timebases | `CMSync.h`, `CMAudioClock.h`, `CMAudioDeviceClock.h` | No declaration | Planned | Injected source, rate, anchor, and ordering tests |
| Timed and simple queues | `CMBufferQueue.h`, `CMSimpleQueue.h` | No declaration | Planned | Ordering, trigger, capacity, and shutdown tests |
| Memory pools | `CMMemoryPool.h` | No declaration | Planned | Allocation and lifecycle tests |
| Metadata and tags | `CMMetadata.h`, `CMTag*.h`, `CMTaggedBufferGroup.h` | No declaration | Planned | Typed tag and provenance behavior |
| Text markup | `CMTextMarkup.h` | No declaration | Planned | Scope decision before implementation |

## Current compatibility boundary

Core Media is the timing and sample layer between Core Video ownership and the
capture graph. The current image path is real but deliberately narrow. It must
not be described as full `CMSampleBuffer` or `CMBlockBuffer` compatibility until
the partial rows above have production behavior and differential tests.
