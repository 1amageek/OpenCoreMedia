# OpenCoreMedia

OpenCoreMedia is a pure-Swift implementation target for the Swift-visible Core
Media API on platforms where Apple's Core Media framework is unavailable.

The implemented behavior Smokes cover rational `CMTime`, `CMTimeRange`,
`CMTimeMapping`, range mapping and folding, `CMSampleTimingInfo`, immutable video
format descriptions, zero-copy image sample buffers backed by OpenCoreVideo,
and a contiguous zero-copy `CMBlockBuffer` owner/view path. External byte
storage is borrowed through scoped raw-buffer closures and released exactly
once after its last buffer or slice owner is destroyed.

This is not complete Core Media API compatibility. Segmented block buffers,
attachments, asynchronous readiness, clocks, timebases, and queues remain
explicitly unimplemented. See
[IMPLEMENTATION_PROGRESS.md](IMPLEMENTATION_PROGRESS.md) for current evidence.

## Supported production targets

- WebAssembly
- Embedded Swift

Apple-platform builds are used for compatibility and conformance testing. Apps on
Apple platforms should import Apple's `CoreMedia` framework.

## Design

Read [DESIGN.md](DESIGN.md) before adding public API or buffer implementations.
Use [APPLE_API_TRACE.md](APPLE_API_TRACE.md) to distinguish implemented,
partial, and planned Apple Core Media families.

## Build

```bash
swift build
swiftly run swift build --swift-sdk swift-6.3.1-RELEASE_wasm
swiftly run swift build --swift-sdk swift-6.3.1-RELEASE_wasm-embedded
```
