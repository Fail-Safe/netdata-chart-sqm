# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

## [v2.0.0] - 2026-02-26

### Added

- New `sqm_cake_mq_mode="overlay"` mode for `cake_mq`, keeping a single chart set per interface while exposing per-queue dimensions on each chart.
- Optional Go collector backend (`sqm_collector="go"`) with configurable binary path (`sqm_go_collector_bin`).
- Automated tests for installer behavior and collector output, plus Go unit tests.
- GitHub Actions workflow for tests, multi-arch collector builds, and tag-based release asset publishing.

### Changed

- `sqm.chart.sh` now delegates chart create/update generation directly to `sqm-go-collector` when Go mode is enabled, avoiding shell-side JSON parsing overhead.
- `install.sh` now supports both `opkg` and `apk`, with optional collector download from release URLs.
- README expanded with v2.0 settings documentation, benchmark data, and mode guidance.

## [v1.1.0] - 2026-02-24

### Added

- Support for `cake_mq` root qdiscs with multiple child `cake` queues.
- New configuration option `sqm_cake_mq_mode` in `sqm.conf`:
    - `cake_mq` (default): aggregate all child `cake` queues into one chart set per interface.
    - `queue`: create one chart set per child `cake` queue.

### Changed

- `tc` root discovery now uses explicit root queries and array parsing for child queue discovery.

### Fixed

- Corrected overview mapping so `backlog` and `drops` dimensions report the right values.
- Fixed `cake_mq` child-queue parent matching to correctly handle handles like `8096:` with parents `8096:1..n`.
