# netdata-chart-sqm

## Description

Netdata chart for displaying SQM statistics.

## Acknowledgements

Adapted for Netdata based on the existing [sqm_collectd](https://github.com/openwrt/packages/blob/master/utils/collectd/files/exec-scripts/sqm_collectd.sh) script. (Credit: [ldir-EDB0](https://github.com/ldir-EDB0))

## Requirements

OpenWrt Packages:

```lang-sh
bash
coreutils-timeout
netdata
```

## Installation

Choose either the Local or Remote method below based on whether your OpenWrt device has `git` and `git-http` installed. These can be installed on OpenWrt via `opkg update; opkg install git git-http` if desired. Otherwise, use the Remote method to clone the project down on another host and push the project to your OpenWrt device.

### OpenWrt Local (with `git` + `git-http` on OpenWrt device)

```lang-sh
# git clone https://github.com/Fail-Safe/netdata-chart-sqm.git
# cd netdata-chart-sqm
# sh ./install.sh
```

### OpenWrt Remote

Clone project and `scp` it to the remote OpenWrt device:

```lang-sh
# git clone https://github.com/Fail-Safe/netdata-chart-sqm.git
# scp -r "$(pwd)/netdata-chart-sqm" root@<OpenWrt device IP here>:~
```

Log into the remote OpenWrt device and execute:

```lang-sh
# cd netdata-chart-sqm
# sh ./install.sh
```

### Validate and Test

After completing the above steps (whether local or remote), reload your Netdata web interface and confirm if "SQM" appears in the list of charts.

## Settings

Common settings are to be modified in: `/etc/netdata/charts.d/sqm.conf`

### Values

- `sqm_ifc` - Modify to match the WAN interface where your SQM configuration is applied. [default: eth0]
- `sqm_priority` - Modify to change where the SQM chart appears in Netdata's web interface. [default: 90000]

## Screenshots

### Example: diffserv4

![SQM_netdata2](https://user-images.githubusercontent.com/10307870/85966239-a6ac9e00-b9ae-11ea-8674-1b28b53f775c.png)
![SQM_netdata3](https://user-images.githubusercontent.com/10307870/85966238-a6ac9e00-b9ae-11ea-8899-ea0fcb7dc511.png)

### Example: diffserv3

![SQM_netdata5](https://user-images.githubusercontent.com/10307870/85966232-a44a4400-b9ae-11ea-912f-8596112524dd.png)

### Example: diffserv8

![SQM_netdata4](https://user-images.githubusercontent.com/10307870/85966234-a57b7100-b9ae-11ea-9a09-eb0506102236.png)

## References

- https://github.com/openwrt/packages/blob/master/utils/collectd/patches/910-add-cake-qdisc-types.patch
- https://github.com/openwrt/luci/blob/master/applications/luci-app-statistics/htdocs/luci-static/resources/statistics/rrdtool/definitions/sqm.js
- https://github.com/openwrt/luci/blob/master/applications/luci-app-statistics/htdocs/luci-static/resources/statistics/rrdtool/definitions/sqmcake.js