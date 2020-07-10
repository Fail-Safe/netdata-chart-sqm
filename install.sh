#!/bin/ash

if [ ! -f "/usr/sbin/netdata" ] || [ ! -d "/etc/netdata/charts.d" ] || [ ! -d "/usr/lib/netdata/charts.d" ]; then
  echo "Netdata is not found. Please run 'opkg update; opkg install netdata' first."
  return 1
fi

if [ ! -f "/bin/bash" ]; then
  echo "Bash is not found. Please run 'opkg update; opkg install bash' first."
  return 1
fi

if [ ! -f "/usr/bin/curl" ]; then
  echo "Curl is not found. Please run 'opkg update; opkg install curl' first."
  return 1
fi

if [ ! -f "/usr/bin/timeout" ]; then
  echo "Coreutils-timeout is not found. Please run 'opkg update; opkg install coreutils-timeout' first."
  return 1
fi

if [ ! -f "/etc/netdata/charts.d.conf" ]; then
  cp /usr/lib/netdata/conf.d/charts.d.conf /etc/netdata/charts.d.conf
fi

cp ./sqm-chart/sqm.conf /etc/netdata/charts.d/
cp ./sqm-chart/sqm.chart.sh /usr/lib/netdata/charts.d/

if ! grep -q "sqm=yes" "/etc/netdata/charts.d.conf"; then
  echo "sqm=yes" >> /etc/netdata/charts.d.conf;
fi

sed -i 's/charts.d\ =\ no/charts.d\ =\ yes/g' /etc/netdata/netdata.conf

/etc/init.d/netdata restart

echo "Finished SQM chart install. Reload your Netdata web interface to see SQM charts."
