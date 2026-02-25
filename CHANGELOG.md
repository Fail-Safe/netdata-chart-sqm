# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added

- New `sqm_cake_mq_mode="overlay"` mode for `cake_mq`, keeping a single chart set per interface while exposing per-queue dimensions on each chart.

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
