# SQM Go Collector

This folder contains a standalone lightweight Go collector that can be used as an optional backend for the shell-based SQM chart workflow.

## Build

```sh
go build -trimpath -ldflags="-s -w" -o bin/sqm-go-collector ./cmd/sqm-go-collector
```

Size workflow (stripped multi-arch artifacts):

```sh
make size
```

Optional UPX comparison (if `upx` is installed):

```sh
make size-upx
```

Release artifacts (normal + optional `.upx` + `SHA256SUMS`):

```sh
make release
```

`make release` also generates `release/RELEASE_NOTES.txt` with runtime guidance for standard vs `.upx` binaries.

`make release` also attempts an automatic startup benchmark when a release binary is runnable on the current host, and appends results to `RELEASE_NOTES.txt`.

You can control it with environment variables:

- `AUTO_BENCH=0` disable auto benchmark
- `BENCH_RUNS` (default `20`)
- `BENCH_INNER` (default `50`)
- `BENCH_IFC` (default `eth0,ifb4eth0`)
- `BENCH_MODE` (default `overlay`)
- `BENCH_FORMAT` (default `metrics`)

Verify release checksums:

```sh
make verify-release
```

Compare startup/runtime timing of standard vs UPX binaries:

```sh
./scripts/compare-startup.sh \
	--std release/sqm-go-collector-linux-amd64 \
	--upx release/sqm-go-collector-linux-amd64.upx \
	--runs 20 -- -ifc eth0,ifb4eth0 -mode overlay -format metrics
```

## Run

```sh
./bin/sqm-go-collector -ifc eth0,ifb4eth0 -mode cake_mq -pretty
```

Metrics-style output (flattened keys for go.d-style mapping):

```sh
./bin/sqm-go-collector -ifc eth0,ifb4eth0 -mode overlay -format metrics -pretty
```

Plan output (chart definitions + updates):

```sh
./bin/sqm-go-collector -ifc eth0,ifb4eth0 -mode overlay -format plan -pretty
```

Modes:

- `cake_mq` - aggregate child cake queues under each `cake_mq`
- `queue` - emit per-queue output
- `overlay` - emit per-queue output intended for shared charts with per-queue dimensions

Formats:

- `json` - structured report output (default)
- `metrics` - flattened numeric key/value output
- `plan` - chart scaffold output containing chart definitions and chart updates
- `netdata-create` - emits Netdata `CHART`/`DIMENSION` definitions
- `netdata-update` - emits Netdata `BEGIN`/`SET`/`END` update frames
