# OpenCoreMedia Implementation Progress

## Apple API trace

- [x] Framework header-family inventory recorded in `APPLE_API_TRACE.md`
- [x] Implemented, partial, and planned responsibilities are distinguished
- [x] Callable partial `CMBlockBuffer` behavior has a source marker
- [x] Callable partial attachment-value behavior has a source marker
- [x] Missing `CMBlockBuffer` attachment-bearer path has a source marker

## Smoke definition

The first smoke milestone is complete only when behavior tests demonstrate:

- valid, invalid, indefinite, and infinite `CMTime` values;
- checked `CMTime` arithmetic, scale conversion, and comparison;
- `CMSampleTimingInfo` value semantics;
- an immutable video format description;
- a ready `CMSampleBuffer` retaining an OpenCoreVideo image buffer without
  copying its storage;
- typed failures for inconsistent timing, format, and sample counts;
- typed failures for unready and invalidated payload access;
- successful native tests and sequential WASM and Embedded WASM builds.

The second Smoke additionally requires:

- Apple-compatible `CMTimeRange` construction, predicates, half-open
  containment, intersection, and union;
- a `CMBlockBuffer` retaining externally supplied storage without copying;
- `init(referencing:)` and `CMBlockBuffer.Slice` sharing that same memory lease;
- scoped immutable and mutable byte borrows preserving the source address;
- typed range and storage-policy failures;
- explicit copy naming and bounds for copy and replace operations;
- exactly-once external release after the final buffer or slice owner dies.

The segmented block-buffer slice additionally requires:

- empty construction with a validated, bounded-reservation capacity hint;
- external segment append without copying payload bytes;
- buffer and slice references sharing the original leases;
- range-specific contiguity across segment boundaries;
- copy, replace, and fill operations spanning segments without an intermediate
  payload;
- explicit contiguous materialization with allocator and deallocator
  contracts;
- no allocator call when an already-contiguous range can share its lease;
- exactly-once release for every appended and materialized lease;
- Apple differential behavior and documented portable copy boundaries.

The buffer-level attachment slice additionally requires:

- Apple-shaped Swift overlay and get, copy, set, remove, and propagate
  operations;
- a mode stored with every value and replacement across modes;
- propagation of only `.shouldPropagate` values;
- independent attachment storage in a timing-only copy;
- unchanged zero-copy image payload ownership;
- differential behavior against Apple Core Media.

The per-sample attachment slice additionally requires:

- no attachment dictionary allocation before first requested access;
- one fixed dictionary view per declared sample;
- direct mutation through Apple-shaped array and key subscripts;
- all 13 standard sample key raw values from the reviewed SDK overlay;
- direct dictionary iteration through `Sequence`;
- typed failure for incompatible standard-key value access;
- recursive array and string-keyed dictionary values;
- independent metadata after a timing-only copy;
- unchanged zero-copy image payload ownership;
- differential behavior against Apple Core Media.

## Required implementation

### Time

- [x] `CMTimeValue`, `CMTimeScale`, and `CMTimeEpoch`
- [x] `CMTimeFlags`
- [x] `CMTimeRoundingMethod`
- [x] `CMTime` special values and predicates
- [x] Checked arithmetic and scale conversion
- [x] Exact comparison without floating-point conversion
- [x] `CMTimeRange` start/duration and start/end construction
- [x] `CMTimeRange` validity, empty, indefinite, and end predicates
- [x] Half-open time and range containment
- [x] Intersection and union
- [x] `CMTimeMapping` value and factory semantics
- [x] Linear time and duration mapping
- [x] Range clamping
- [x] Exact positive and negative range folding
- [x] Apple differential mapping and folding fixtures
- [x] Apple differential fixtures for broader overflow and epoch combinations

### Timing and formats

- [x] `CMSampleTimingInfo`
- [x] Media type and subtype identifiers
- [x] Immutable video format description
- [x] Format-to-image-buffer compatibility validation

### Sample buffers

- [x] Typed sample-buffer errors
- [x] Ready image sample construction
- [x] Zero-copy image-buffer retention
- [x] Readiness and invalidation state transitions
- [x] Timing, format, and count validation
- [x] Scalar timing storage for the single-image sample path
- [x] `CMAttachmentBearerProtocol` and `CMAttachmentBearerAttachments`
- [x] Keyed Swift-overlay access, merge, remove-all, and propagation
- [x] Attachment modes and scalar portable values
- [x] Recursive attachment array and dictionary values
- [x] Get, copy, set, batch set, remove, and remove-all operations
- [x] Propagatable-only attachment transfer
- [x] Timing-copy attachment propagation into independent storage
- [x] Lazy fixed-length per-sample attachment array
- [x] Mutable, iterable per-sample dictionary views and all standard keys
- [x] Typed Boolean access and incompatible-value failure
- [x] Timing-copy preservation and independent per-sample metadata
- [x] Owned attachment byte values and explicit platform-value adapters
- [x] Multi-sample block payload carrier and zero-copy sample slices
- [x] Revision-safe asynchronous data readiness handlers shared by timing copies
- [x] Sendable sample, block-buffer, and zero-copy slice contracts on every target

### Block buffers

- [x] `CMBlockBufferProtocol` owner and index contract
- [x] Synchronized `Sendable` owner and zero-copy slice views
- [x] External contiguous buffer construction
- [x] Zero-copy `init(referencing:)`
- [x] `CMBlockBuffer.Slice` retaining owner plus range
- [x] Range, closed-range, partial-range, and unbounded subscripts
- [x] Typed `slice(_:)` validation
- [x] Scoped immutable and mutable borrows
- [x] Explicit `copyDataBytes`, `replaceDataBytes`, and `fillDataBytes`
- [x] Exactly-once external deallocation
- [x] Empty construction and bounded segment-capacity hint
- [x] Multiple external memory segments and append
- [x] Zero-copy buffer and slice reference append
- [x] Range-specific contiguity
- [x] Cross-segment copy, replace, and fill
- [x] Explicit contiguous materialization
- [x] Deferred allocation
- [x] Allocator-backed append and construction overloads
- [x] Raw-memory offset and data-length construction/append
- [x] Foundation `dataBytes()` in a separate explicit-copy product

### Clocks and queues

- [x] Injected `CMClockSource` and typed clock invalidation
- [x] Clock- and timebase-sourced `CMTimebase`
- [x] Anchored time, rate changes, and effective-rate traversal
- [x] Bounded timed queue with FIFO/ordered insertion
- [x] Readiness-aware dequeue and end-of-data/reset
- [x] Checked aggregate duration and size
- [x] Callbacks outside locks with revision-safe retry
- [x] O(1) dequeue metadata and post-unlock release
- [x] Bounded lazy two-stack portable simple queue

## Copy boundary

`CMImageSampleBuffer` retains the supplied Sendable `CVPixelBuffer` reference.
It does not read, copy, convert, or materialize payload bytes. A timing-only
copy retains that same image-buffer reference and allocates only timing metadata
and independent attachment storage while sharing the readiness tracker. Only
`.shouldPropagate` metadata is inserted into the copy. The native Smoke verifies
object identity and shared mutation through borrowed pixel-buffer byte access:
writes through the source, original sample, and timing-only copy are observed
from the same media storage, while later attachment mutations remain isolated.

Per-sample attachment storage starts unmaterialized. First requested access
creates a fixed array with one dictionary owner per sample. A timing copy
preserves the unmaterialized state when the source has no per-sample metadata.
When materialized, it copies each dictionary directly into one destination
owner array. Recursive array and dictionary values use copy-on-write backing;
no image bytes are read or copied. The optional owner array lives in the
sample's existing state, so unused per-sample attachments do not require a
separate coordinator allocation.

The public initializer retains its one-element timing-array input for API
compatibility. After validating that input, the single-sample implementation
stores one `CMSampleTimingInfo` value rather than retaining an `Array` inside
every sample object. This removes persistent array storage from the high-rate
sample path, but does not claim that construction is allocation-free because
the caller still creates the boundary array.

The image sample buffer is non-generic and stores Sendable pixel-buffer and
video-format existentials. The block sample buffer is also non-generic and
stores an `any CMFormatDescription`, matching Core Media's heterogeneous sample
carrier.
Native, regular WASI, and Embedded use the same `Synchronization.Mutex`-backed
`CMStateLock`. Lock ownership is separated: sample state protects validity and
the optional per-sample storage array; the shared readiness tracker protects
terminal state and revision; `CMAttachmentStorageReference` protects
buffer-level attachments; and each `CMSampleAttachmentDictionaryStorage`
protects one per-sample dictionary. No locks are nested, and no `await`,
allocator callback, borrow callback, or media-byte work occurs while a lock is
held.

`CMBlockBuffer` stores segment metadata over external-memory leases rather than
payload bytes. Buffer/slice reference append snapshots segment views;
`init(referencing:)` shares the synchronized storage and attachments; slices
retain an owner plus range. Borrow closures receive an original lease pointer
adjusted only by their
range offset. Mutable offset access borrows only the tail of the containing
segment. `copyDataBytes` and `replaceDataBytes` preflight physical overlap, then
iterate twice over the retained segment table without a temporary view array and
copy directly between disjoint caller memory and each overlapping segment;
`fillDataBytes` mutates each segment in place. `makeContiguous` shares a
one-segment lease unless `.alwaysCopyData` is requested, and otherwise performs
one allocator-visible payload copy. Raw pointers returned to borrow closures
must not be stored or returned.

## Apple API review evidence

Reviewed with `remark` on 2026-07-24:

- `CMTime`
- `CMTimeFlags`
- `CMTimeRoundingMethod`
- `CMTime.+`
- `CMTime.-`
- `CMTime.convertScale`
- `CMTimeCompare`
- `CMSampleTimingInfo`
- `CMFormatDescription`
- `CMVideoFormatDescription`
- `CMSampleBuffer`
- `CMSampleBuffer.imageBuffer`
- `CMSampleBuffer.formatDescription`
- `CMSampleBuffer.numSamples`
- `CMSampleBuffer.invalidate`
- `CMTimeRange`
- `CMTimeRange.init(start:duration:)`
- `CMTimeRange.init(start:end:)`
- `CMTimeRange.containsTime`
- `CMTimeRange.containsTimeRange`
- `CMTimeRange.intersection`
- `CMTimeRange.union`
- `CMTimeMapping`
- `CMTimeMapping.init(source:target:)`
- `CMTimeMapping.invalid`
- `CMTimeMappingMake`
- `CMTimeMappingMakeEmpty`
- `CMTimeMapTimeFromRangeToRange`
- `CMTimeMapDurationFromRangeToRange`
- `CMTimeClampToRange`
- `CMTimeFoldIntoRange`
- `CMBlockBuffer`
- `CMBlockBuffer.init(buffer:deallocator:flags:)`
- `CMBlockBuffer.init(referencing:)`
- `CMBlockBufferProtocol`
- `CMBlockBuffer.Slice`
- `CMBlockBuffer.withUnsafeMutableBytes`
- `CMBlockBufferProtocol.withContiguousStorage`
- `CMBlockBufferProtocol.copyDataBytes`
- `CMBlockBufferProtocol.replaceDataBytes`
- `CMBlockBufferProtocol.fillDataBytes`
- `CMBlockBuffer.init(capacity:flags:)`
- `CMBlockBuffer.init(bufferReference:flags:)`
- `CMBlockBuffer.append(buffer:deallocator:flags:)`
- `CMBlockBuffer.append(bufferReference:flags:)`
- `CMBlockBuffer.assureBlockMemory()`
- `CMBlockBufferProtocol.isContiguous`
- `CMBlockBufferProtocol.makeContiguous(allocator:deallocator:flags:)`
- `CMAttachment`
- `CMAttachmentBearerProtocol`
- `CMAttachmentBearerAttachments`
- `CMGetAttachment`
- `CMCopyDictionaryOfAttachments`
- `CMSetAttachment`
- `CMSetAttachments`
- `CMRemoveAttachment`
- `CMRemoveAllAttachments`
- `CMPropagateAttachments`
- `CMSampleBufferGetSampleAttachmentsArray`
- `CMSampleBuffer.sampleAttachments`
- `CMSampleBuffer.SampleAttachmentsArray`
- `CMSampleBuffer.PerSampleAttachmentsDictionary`
- `CMSampleBuffer.PerSampleAttachmentsDictionary.Key`
- Sample Attachment Keys
- `CMSampleBufferCreateCopy`
- `CMSampleBufferCreateCopyWithNewTiming`
- `CMSampleBufferCreate`
- `CMSampleBufferCreateWithMakeDataReadyHandler`
- `CMSampleBufferMakeDataReady`
- `CMBlockBufferCreateWithMemoryBlock`
- `CMBlockBufferAppendMemoryBlock`
- `CMBlockBufferProtocol.dataBytes`
- `CMClock`
- `CMTimebase`
- `CMBufferQueue`
- `CMSimpleQueue`

The second Smoke checked the Swift declarations emitted from the local macOS 27
SDK with `swift-symbolgraph-extract` and read `CMTimeRange.h` and
`CMBlockBuffer.h` directly. The per-sample attachment slice refreshed that
symbol graph on 2026-07-25 and read the relevant `CMSampleBuffer.h` declarations.
The reviewed behavior and portable differences are recorded in `DESIGN.md`.
Additional Apple-named APIs must be reviewed and added to this list before
implementation.

## Test evidence

- Native:
  `xcodebuild test -scheme OpenCoreMedia-Package -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 60
  -only-testing:OpenCoreMediaTests
  SWIFT_EXEC=~/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a.xctoolchain/usr/bin/swiftc`
  — passed all 79 behavior tests in 11 suites with the fixed Swift 6.4
  development snapshot compiler on 2026-07-25.
- Time mapping differential:
  `xcodebuild test -scheme OpenCoreMedia-Package -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 60
  -only-testing:OpenCoreMediaTests/CMTimeSmokeTests
  -only-testing:OpenCoreMediaTests/CMTimeRangeSmokeTests
  -only-testing:OpenCoreMediaTests/CMTimeMappingSmokeTests
  -only-testing:OpenCoreMediaTests/CMTimeMappingAppleDifferentialTests`
  — passed 23 tests on 2026-07-25, including special values, checked
  arithmetic, scale conversion, exact comparison, range behavior, raw versus
  validating mapping construction,
  endpoint preservation, nonintegral nanosecond mapping, epoch failures,
  infinite ranges, clamping, and positive/negative folding. Overflow,
  large-timescale conversion, and epoch arithmetic/comparison differential
  fixtures ran against Apple Core Media. Exhaustive generated arithmetic
  differential fuzzing remains outside the completed milestone.
- Scalar timing-storage regression:
  `xcodebuild test -scheme OpenCoreMedia-Package -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 30
  -only-testing:OpenCoreMediaTests/SampleBufferSmokeTests`
  — passed on 2026-07-24, including index `0`, negative, and upper-bound
  timing access plus payload identity and readiness behavior.
- Buffer-level attachments:
  `xcodebuild test -scheme OpenCoreMedia-Package -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 30
  -only-testing:OpenCoreMediaTests/CMAttachmentSmokeTests
  -only-testing:OpenCoreMediaTests/CMAttachmentAppleDifferentialTests
  -only-testing:OpenCoreMediaTests/SampleBufferSmokeTests`
  — passed 11 tests on 2026-07-24, including Apple timing-copy propagation,
  independent metadata storage, and unchanged image-buffer identity.
- Per-sample attachments:
  `xcodebuild test -scheme OpenCoreMedia-Package -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 30
  -only-testing:OpenCoreMediaTests/CMSampleAttachmentSmokeTests
  -only-testing:OpenCoreMediaTests/CMAttachmentAppleDifferentialTests
  SWIFT_EXEC=~/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a.xctoolchain/usr/bin/swiftc`
  — passed on 2026-07-25, including lazy creation, fixed length, direct
  mutation, all standard raw keys, direct iteration, typed mismatch failure,
  recursive values, concurrent mutation/copy, Apple copy behavior, independent
  metadata, and unchanged image-buffer identity.
- WASM:
  `~/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a.xctoolchain/usr/bin/swift build
  --swift-sdks-path ~/Library/org.swift.swiftpm/swift-sdks
  --swift-sdk
  swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a_wasm
  --target OpenCoreMedia`
  — passed after `swift package clean` with the matching Swift 6.4
  development snapshot compiler and SDK on 2026-07-25.
- WASM runtime:
  `./scripts/run-wasm-smoke.sh`
  — built the smoke executable with the regular fixed Swift 6.4 WASM SDK and
  executed it through Node WASI on 2026-07-25. It runs the same segmented
  append, reference, cross-segment mutation/copy, overlap-safe failure,
  materialization, allocation failure, and lease-release contracts as the
  Embedded runtime fixture.
- Embedded WASM:
  `~/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a.xctoolchain/usr/bin/swift build
  --swift-sdks-path ~/Library/org.swift.swiftpm/swift-sdks
  --swift-sdk
  swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a_wasm-embedded
  --target OpenCoreMedia`
  — passed after `swift package clean` with the matching Swift 6.4
  development snapshot compiler and SDK on 2026-07-25. The target triple is
  `wasm32-unknown-wasip1`; the Embedded platform module is
  `embedded/Synchronization.swiftmodule/wasm32-unknown-wasip1.swiftmodule`.
- Embedded runtime:
  `./scripts/run-embedded-smoke.sh`
  — built `OpenCoreMediaEmbeddedSmoke.wasm` with the fixed Swift 6.4
  Embedded SDK and executed it through Node WASI on 2026-07-25. The smoke
  validates `any CMSampleBuffer` construction and payload access,
  Mutex-protected not-ready and typed-failure recovery, buffer-level
  propagation, lazy per-sample creation, recursive mutation, throwing scoped
  borrows, segmented append, noncontiguous typed failure, cross-segment
  fill/copy/replace, zero-copy references, forced-copy materialization,
  allocation failure, per-lease release counts, timing-copy metadata
  independence, and unchanged image-buffer identity. The script records the
  toolchain, Swift SDK, target triple, and Embedded Synchronization module
  identifiers. Node WASI is a single-threaded execution fixture; Native
  concurrent state, buffer-level attachment, and per-sample mutation/copy tests
  provide the current contention test.
- Native Thread Sanitizer:
  `xcodebuild test -scheme OpenCoreMedia-Package
  -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 60
  -enableThreadSanitizer YES
  SWIFT_EXEC=~/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a.xctoolchain/usr/bin/swiftc`
  — passed all 79 tests in 11 suites on 2026-07-25.
- Segmented block buffers:
  `xcodebuild test -quiet -scheme OpenCoreMedia-Package
  -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 60
  -only-testing:OpenCoreMediaTests/CMBlockBufferSmokeTests
  -only-testing:OpenCoreMediaTests/CMBlockBufferAppleDifferentialTests
  SWIFT_EXEC=~/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a.xctoolchain/usr/bin/swiftc`
  — passed on 2026-07-25, covering zero-copy append/reference behavior,
  reference flags, range-specific contiguity, segment-tail mutable borrows,
  cross-segment copy/fill/replace, alias rejection, explicit range-limited
  materialization, allocation and length failure, per-lease release, and
  macOS 27 differential behavior including documented zero-length overlay
  differences.
- Native Address Sanitizer:
  `xcodebuild build-for-testing -scheme OpenCoreMedia-Package
  -destination 'platform=macOS,arch=arm64' -enableAddressSanitizer YES
  SWIFT_EXEC=~/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a.xctoolchain/usr/bin/swiftc`,
  followed by `xcodebuild test-without-building` for
  `CMBlockBufferSmokeTests` and `CMBlockBufferAppleDifferentialTests`
  — passed on 2026-07-25. The Xcode beta bundle initially embedded its
  `apple_clang_2100` ASan runtime while the fixed snapshot instrumentation
  requires `__asan_version_mismatch_check_v8`. The successful run replaced the
  disposable test bundle's runtime with the snapshot's matching
  `libclang_rt.asan_osx_dynamic.dylib` and inserted that exact library through
  the generated `.xctestrun` environment before process launch.
- Deferred blocks, multi-sample buffers, readiness, clocks, and queues:
  `xcodebuild test -scheme OpenCoreMedia-Package -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 30
  -only-testing:OpenCoreMediaTests/CMRemainingSurfaceSmokeTests
  SWIFT_EXEC=~/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a.xctoolchain/usr/bin/swiftc`
  — passed 16 focused behavior tests on 2026-07-25. The full
  `OpenCoreMediaTests` target passed 79 tests in 11 suites. The focused runtime
  covers lazy and assured allocation, raw-memory ranges, owned attachment
  bytes and adapters, zero-copy multi-sample slices, revision-safe readiness,
  anchored timebases, bounded queues, and Foundation materialization
  independence.
- Completion-surface Thread Sanitizer:
  the same focused suite passed with `-enableThreadSanitizer YES` on
  2026-07-25, exercising handler coordination plus synchronized clock,
  timebase, attachment, block-buffer, sample-buffer, and queue state.
- Final portability and consumer validation:
  `./scripts/run-wasm-smoke.sh` and `./scripts/run-embedded-smoke.sh`
  both built and executed successfully with the fixed Swift 6.4 SDKs on
  2026-07-25. Their completion fixtures statically require `Sendable` for
  `CMBlockBuffer`, `CMBlockSampleBuffer`, `CMBlockBuffer.Slice`, and the
  Embedded image sample, then exercise sample destruction and zero-copy slice
  access at runtime. A focused Thread Sanitizer run passed 40 block-buffer,
  sample-buffer, and completion-surface tests. Finally,
  `OpenAVFoundationDriverTesting` built for Embedded WASM against this local
  OpenCoreMedia tree and OpenCoreVideo `29b4664`; the temporary local dependency
  override was removed immediately after validation.

## External Embedded integration finding

The original same-module Embedded image fixture passes. A fixture that instead
constructed OpenCoreVideo `e092d7b`'s
`CVPackedPixelBuffer<CVOwnedPixelBufferStorage<CVNoOpPixelBufferAccessCoordinator>, CVBufferAttachments>`
and passed it to `CMImageSampleBuffer` compiled but failed while linking the
Embedded executable:

```text
undefined symbol:
$e13OpenCoreVideo19CVBufferAttachmentsCAA0D17AttachmentStorageAAWP
```

The reproducer was `./scripts/run-embedded-smoke.sh` after replacing the local
`OpenCoreMediaEmbeddedPixelBuffer(dimensions:)` construction with
`CVPackedPixelBuffer(dimensions:pixelFormat:bytesPerPixel:bytesPerRow:)`.
This identified the missing external
`CVBufferAttachments: CVBufferAttachmentStorage` Embedded witness from
OpenCoreVideo, not an OpenCoreMedia source or Sendable failure.

On 2026-07-25, the same reproducer was rerun against the local OpenCoreVideo
change that exports this conformance. That removed the missing symbol and
exposed a Swift 6.4 Embedded compiler crash while specializing the former
generic public `CMImageSampleBuffer` initializer. The initializer now accepts
the type-erased Sendable pixel-buffer and video-format protocols directly.
With both changes present, the real external `CVPackedPixelBuffer` fixture
built, linked, and executed successfully with no additional missing symbol.
The temporary local package dependency and external fixture were restored
after validation.

## Outside the completed milestone

- exhaustive generated `CMTime` arithmetic differential fuzzing
- audio, metadata, and codec-specific format descriptions
- arbitrary platform-object retention inside shared attachment storage
- real-time lockless SPSC queues and trigger callback parity
- clock/timebase timer scheduling and operating-system host clock adapters
- memory pools, metadata/tag groups, and text markup
- platform camera, codec, and file adapters
