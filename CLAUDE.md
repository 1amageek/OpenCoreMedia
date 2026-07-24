# OpenCoreMedia implementation rules

Read `DESIGN.md` completely before changing this package.

- Preserve the Core Media responsibility: rational time, format descriptions,
  byte blocks, timed sample buffers, readiness, attachments, clocks, and queues.
- OpenCoreMedia may depend on OpenCoreVideo. OpenCoreVideo must never depend on
  OpenCoreMedia.
- Do not add capture sessions, capture-device discovery, camera controls, codecs,
  inference, or Manas dependencies.
- Keep shared targets free of Foundation, Objective-C, Dispatch, JavaScriptKit,
  Darwin, Glibc, camera SDKs, and GPU SDKs.
- Sample payload ownership is zero-copy by default. A `CMSampleBuffer` retains a
  payload lease; borrowed access cannot outlive that lease.
- Readiness and invalidation are explicit state transitions. Never turn failed or
  unavailable data into an empty successful sample.
- Do not add an Apple-named declaration until its signature has been checked with
  `remark` and its behavior has a conformance test plan.
- Tests use Swift Testing. Run focused `xcodebuild test` commands with a timeout,
  plus WASM and Embedded builds for shared-source changes.
