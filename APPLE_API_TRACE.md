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
| `CMTime` | `CMTime.h` | Rational values, flags, arithmetic, rounding, epochs | Partial | Exhaustive generated boundary differential fuzzing |
| `CMTimeRange` and `CMTimeMapping` | `CMTimeRange.h` | Ranges, mapping, clamp, fold, affine conversion | Implemented | Apple differential fixtures |
| `CMBlockBuffer` | `CMBlockBuffer.h` | Segmented external/deferred leases, allocator construction/append, raw-memory ranges, references, byte operations, explicit materialization | Implemented portable surface | Broader allocator-timing differential fixtures |
| `CMFormatDescription` | `CMFormatDescription.h` | Immutable video description | Partial | Audio, metadata, codec extensions |
| `CMSampleBuffer` | `CMSampleBuffer.h` | Sendable one-image and multi-sample block carriers, compact timing/size layouts, shared revisioned readiness, invalidation, timing-only copy | Partial | Zero-sample events and broader audio/codec fixtures |
| Buffer-level attachments | `CMAttachment.h`, `CMSampleBuffer.h` | Synchronized storage bearer, recursive values, owned bytes, explicit platform adapters, modes, C-derived operations, and propagation | Partial | Arbitrary Core Foundation object parity is intentionally outside shared storage |
| Per-sample attachments | `CMSampleBuffer.h`, SDK Swift overlay | Lazy fixed-length array for image and multi-sample block carriers, mutable dictionary views, standard keys, and independent copy metadata | Implemented portable surface | Broader codec-specific values |
| Clocks and timebases | `CMSync.h` | Injected clock source, invalidation, clock/timebase source chains, anchor/rate/effective-rate behavior | Partial | Timer scheduling and operating-system host-clock adapters |
| Timed and simple queues | `CMBufferQueue.h`, `CMSimpleQueue.h` | Bounded timed queue ordering/readiness/end-of-data with callbacks outside locks, plus a bounded two-stack portable FIFO | Partial | Triggers and platform real-time lockless SPSC adapter |
| Memory pools | `CMMemoryPool.h` | No declaration | Planned | Allocation and lifecycle tests |
| Metadata and tags | `CMMetadata.h`, `CMTag*.h`, `CMTaggedBufferGroup.h` | No declaration | Planned | Typed tag and provenance behavior |
| Text markup | `CMTextMarkup.h` | No declaration | Planned | Scope decision before implementation |

## Current compatibility boundary

Core Media is the timing and sample layer between Core Video ownership and the
capture graph. The current image path is real but deliberately narrow. It must
not be described as full `CMSampleBuffer` or `CMBlockBuffer` compatibility until
the partial rows above have production behavior and differential tests.
