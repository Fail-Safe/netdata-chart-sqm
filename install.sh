#!/bin/sh

die() {
	echo "$1"
	exit 1
}

sqmpath() {
	printf '%s%s' "${SQM_ROOT_PREFIX:-}" "$1"
}

sed_inplace() {
	sed -i "$1" "$2" 2>/dev/null || sed -i '' "$1" "$2"
}

merge_sqm_conf() {
	src="$1"
	dst="$2"

	if [ ! -f "$dst" ]; then
		cp "$src" "$dst"
		return 0
	fi

	tmp="$(mktemp 2>/dev/null || echo "/tmp/sqm.conf.merge.$$")"
	cp "$dst" "$tmp" || return 1

	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		[A-Za-z_][A-Za-z0-9_]*=*)
			key="${line%%=*}"
			if ! grep -q "^[[:space:]]*$key=" "$tmp"; then
				printf '\n%s\n' "$line" >>"$tmp"
			fi
			;;
		esac
	done <"$src"

	cp "$tmp" "$dst"
	rm -f "$tmp"
}

if command -v opkg >/dev/null 2>&1; then
	pkg_install_cmd="opkg update; opkg install"
elif command -v apk >/dev/null 2>&1; then
	pkg_install_cmd="apk update; apk add"
else
	die "No supported package manager found (opkg/apk). Install dependencies manually."
fi

if [ ! -f "$(sqmpath /usr/sbin/netdata)" ] || [ ! -d "$(sqmpath /etc/netdata/charts.d)" ] || [ ! -d "$(sqmpath /usr/lib/netdata/charts.d)" ]; then
	die "Netdata is not found. Please run '$pkg_install_cmd netdata' first."
fi

if [ ! -f "$(sqmpath /bin/bash)" ]; then
	die "Bash is not found. Please run '$pkg_install_cmd bash' first."
fi

if [ ! -f "$(sqmpath /usr/bin/curl)" ]; then
	die "Curl is not found. Please run '$pkg_install_cmd curl' first."
fi

if [ ! -f "$(sqmpath /usr/bin/timeout)" ]; then
	die "Coreutils-timeout is not found. Please run '$pkg_install_cmd coreutils-timeout' first."
fi

if [ ! -f "$(sqmpath /etc/netdata/charts.d.conf)" ]; then
	cp "$(sqmpath /usr/lib/netdata/conf.d/charts.d.conf)" "$(sqmpath /etc/netdata/charts.d.conf)"
fi

merge_sqm_conf ./sqm-chart/sqm.conf "$(sqmpath /etc/netdata/charts.d/sqm.conf)" || die "Failed to merge sqm.conf"
cp ./sqm-chart/sqm.chart.sh "$(sqmpath /usr/lib/netdata/charts.d/)"

install_go_collector="no"
if [ -t 0 ]; then
	printf "Install optional Go SQM collector binary? [y/N]: "
	read -r go_answer
	case "$go_answer" in
	y | Y | yes | YES)
		install_go_collector="yes"
		;;
	esac
elif [ "${SQM_INSTALL_GO_COLLECTOR}" = "1" ] || [ "${SQM_INSTALL_GO_COLLECTOR}" = "yes" ] || [ "${SQM_INSTALL_GO_COLLECTOR}" = "true" ]; then
	install_go_collector="yes"
fi

if [ "$install_go_collector" = "yes" ]; then
	go_arch=""
	case "$(uname -m 2>/dev/null)" in
	x86_64 | amd64)
		go_arch="amd64"
		;;
	aarch64 | arm64)
		go_arch="arm64"
		;;
	mipsel | mipsle)
		go_arch="mipsle-softfloat"
		;;
	*)
		echo "Go SQM collector: unsupported architecture '$(uname -m 2>/dev/null)'; skipping."
		;;
	esac

	if [ -n "$go_arch" ]; then
		go_filename="sqm-go-collector-linux-$go_arch"
		go_target="$(sqmpath /usr/lib/netdata/charts.d/sqm-go-collector)"
		go_base_url="${SQM_GO_COLLECTOR_BASE_URL:-}"
		go_version="${SQM_GO_COLLECTOR_VERSION:-latest}"

		if [ -n "$go_base_url" ]; then
			if [ "$go_version" = "latest" ]; then
				go_url="${go_base_url%/}/${go_filename}"
			else
				go_url="${go_base_url%/}/${go_version}/${go_filename}"
			fi
		elif [ "$go_version" = "latest" ]; then
			go_url="https://github.com/Fail-Safe/netdata-chart-sqm/releases/latest/download/${go_filename}"
		else
			go_url="https://github.com/Fail-Safe/netdata-chart-sqm/releases/download/${go_version}/${go_filename}"
		fi

		echo "Downloading $go_url"
		if curl -fsSL "$go_url" -o "$go_target"; then
			chmod 0755 "$go_target"
			echo "Installed Go SQM collector binary at $go_target"
		else
			echo "Download failed for $go_url."
			echo "Go SQM collector not installed."
		fi
	fi
fi

if ! grep -q "sqm=yes" "$(sqmpath /etc/netdata/charts.d.conf)"; then
	echo "sqm=yes" >>"$(sqmpath /etc/netdata/charts.d.conf)"
fi

sed_inplace 's/charts.d\ =\ no/charts.d\ =\ yes/g' "$(sqmpath /etc/netdata/netdata.conf)"

"$(sqmpath /etc/init.d/netdata)" restart

echo "Finished SQM chart install. Reload your Netdata web interface to see SQM charts."
