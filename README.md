# netdata-chart-sqm

## Description

Netdata chart for displaying SQM statistics.

## Acknowledgements

Adapted for Netdata based on the existing [sqm_collectd](https://github.com/openwrt/packages/blob/master/utils/collectd/files/exec-scripts/sqm_collectd.sh) script. (Credit: [ldir-EDB0](https://github.com/ldir-EDB0))

## Requirements

OpenWrt Packages:

```shell
bash
coreutils-timeout
curl
netdata
```

## Installation

Choose either the Local or Remote method below based on whether your OpenWrt device has `git` and `git-http` installed. These can be installed on OpenWrt via `apk update; apk add git git-http` if desired. Otherwise, use the Remote method to clone the project down on another host and push the project to your OpenWrt device.

### OpenWrt Local (with `git` + `git-http` on OpenWrt device)

```shell
# git clone https://github.com/Fail-Safe/netdata-chart-sqm.git
# cd netdata-chart-sqm
# sh ./install.sh
```

### OpenWrt Remote

Clone project and `scp` it to the remote OpenWrt device:

```shell
# git clone https://github.com/Fail-Safe/netdata-chart-sqm.git
# scp -r "$(pwd)/netdata-chart-sqm" root@<OpenWrt device IP here>:~
```

Log into the remote OpenWrt device and execute:

```shell
# cd netdata-chart-sqm
# sh ./install.sh
```

### Validate and Test

After completing the above steps (whether local or remote), reload your Netdata web interface and confirm if "SQM" appears in the list of charts.

### Development tests

Run project tests locally:

```lang-sh
bash tests/run-tests.sh
```

## Settings

Common settings are to be modified in: `/etc/netdata/charts.d/sqm.conf`

### Values

- `sqm_ifc` - Modify to match the interface(s) where your SQM configuration is applied. Each interface names should be placed in quotes and separated by a space. e.g. for eth0 and eth1: `declare -a sqm_ifc=("eth0" "eth1")` [default: "eth0"]
- `sqm_cake_mq_mode` - Choose charting behavior for interfaces using `cake_mq`: `cake_mq` (aggregate child `cake` queues into one chart set), `queue` (one chart set per child queue), or `overlay` (one chart set with one dimension per child queue). [default: `cake_mq`]
- `sqm_collector` - Choose collector backend: `shell` (legacy charts.d parsing path) or `go` (delegates chart create/update output to the Go collector binary). See performance benchmark below for details. [default: `shell`, recommended: `go`]
- `sqm_go_collector_bin` - Absolute path to the Go collector binary used when `sqm_collector="go"`. [default: `/usr/lib/netdata/charts.d/sqm-go-collector`]
- `sqm_priority` - Modify to change where the SQM chart appears in Netdata's web interface. [default: 90000]

#### `sqm_cake_mq_mode` details

This setting only changes how `cake_mq` child queues are presented in charts; metric collection remains the same.

| Value     | What you get                                                                  | Expectations                                                              | Pros                                                       | Cons                                               |
| --------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------- | ---------------------------------------------------------- | -------------------------------------------------- |
| `cake_mq` | One aggregated chart set per interface (all child queues combined)            | Best when you care about overall link behavior, not per-queue differences | Lowest chart count, easiest to read, least dashboard noise | Hides queue-level imbalance/hotspots               |
| `queue`   | One full chart set per child queue                                            | Best for deep troubleshooting per hardware queue                          | Most detailed per-queue visibility                         | Highest chart count, noisier dashboard             |
| `overlay` | One chart set per tin with per-queue dimensions (e.g. `q1_bytes`, `q2_bytes`) | Best balance for day-to-day monitoring with queue comparison              | Good visibility with fewer charts than `queue`             | More complex dimensions and legends than `cake_mq` |

## Optional Go backend collector

The shell collector (`sqm-chart/sqm.chart.sh`) remains the primary integration path for legacy usage.
This repository also includes `sqm-go-collector`, a lightweight Go binary that can be used as an optional backend for `tc` data collection workflows.

If you choose the Go collector during `install.sh`, you can download a binary from GitHub Releases (or any compatible base URL) by setting:

- `SQM_GO_COLLECTOR_BASE_URL` (example: `https://github.com/<owner>/<repo>/releases/download`)
- `SQM_GO_COLLECTOR_VERSION` (example: `v1.2.3`)

### Performance benchmark (shell vs go backend)

Latest benchmark on an OpenWrt x86_64 based host (2026-02-25), using Netdata chart `netdata.plugin_chartsd_sqm` (plugin run time):

| Collector |   n | Avg (ms) | Median (ms) | p95 (ms) | Min (ms) | Max (ms) |
| --------- | --: | -------: | ----------: | -------: | -------: | -------: |
| Shell     |  48 |   348.88 |         340 |      370 |      330 |      370 |
| Go        |  48 |     9.38 |          10 |       10 |        0 |       10 |

Method summary: for each mode, restart netdata, warm up for 30s, then collect 8 short windows from `/api/v1/data?chart=netdata.plugin_chartsd_sqm&after=-12&points=12&format=csv` and aggregate numeric samples.

These values indicate most overhead in shell mode comes from shell/jshn processing in charts.d, while the delegated Go update path stays near timer-resolution floor on this device.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history and notable changes.

## Screenshots

### Example: diffserv4

![SQM_netdata2](https://user-images.githubusercontent.com/10307870/85966239-a6ac9e00-b9ae-11ea-8674-1b28b53f775c.png)
![SQM_netdata3](https://user-images.githubusercontent.com/10307870/85966238-a6ac9e00-b9ae-11ea-8899-ea0fcb7dc511.png)

### Example: diffserv3

![SQM_netdata5](https://user-images.githubusercontent.com/10307870/85966232-a44a4400-b9ae-11ea-912f-8596112524dd.png)

### Example: diffserv8

![SQM_netdata4](https://user-images.githubusercontent.com/10307870/85966234-a57b7100-b9ae-11ea-9a09-eb0506102236.png)

## References

### Cake / Cake MQ

- [Cake MQ](https://github.com/openwrt/openwrt/commit/dd79febbbe94d6b870848ef43573eef02cb0331c)
- [Cake-mq - backport of multi-core capable CAKE implementation to 25.12 branch](https://forum.openwrt.org/t/cake-mq-backport-of-multi-core-capable-cake-implementation-to-25-12-branch/246349)

### Collectd Inspiration

- https://github.com/openwrt/packages/blob/master/utils/collectd/patches/910-add-cake-qdisc-types.patch
- https://github.com/openwrt/luci/blob/master/applications/luci-app-statistics/htdocs/luci-static/resources/statistics/rrdtool/definitions/sqm.js
- https://github.com/openwrt/luci/blob/master/applications/luci-app-statistics/htdocs/luci-static/resources/statistics/rrdtool/definitions/sqmcake.js
