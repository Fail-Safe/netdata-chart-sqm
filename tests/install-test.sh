#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_file() {
	[ -f "$1" ] || fail "expected file not found: $1"
}

assert_contains() {
	local file="$1"
	local needle="$2"
	grep -Fq "$needle" "$file" || fail "expected '$needle' in $file"
}

make_fake_root() {
	local root="$1"
	mkdir -p "$root"/{bin,etc/netdata/charts.d,etc/init.d,usr/bin,usr/lib/netdata/{charts.d,conf.d},usr/sbin}
	touch "$root/usr/sbin/netdata" "$root/bin/bash" "$root/usr/bin/curl" "$root/usr/bin/timeout"
	cat > "$root/usr/lib/netdata/conf.d/charts.d.conf" <<'EOF'
# test charts config
EOF
	cat > "$root/etc/netdata/netdata.conf" <<'EOF'
[plugins]
    charts.d = no
EOF
	cat > "$root/etc/init.d/netdata" <<'EOF'
#!/bin/sh
echo "$@" >>"$(dirname "$0")/netdata.restart.log"
EOF
	chmod +x "$root/etc/init.d/netdata"
}

run_install() {
	local root="$1"
	local bindir="$2"
	(
		cd "$REPO_ROOT"
		PATH="$bindir:/usr/bin:/bin" SQM_ROOT_PREFIX="$root" sh ./install.sh </dev/null
	)
}

test_basic_install() {
	local tmp root bindir
	tmp="$(mktemp -d)"
	root="$tmp/root"
	bindir="$tmp/bin"
	mkdir -p "$bindir"
	make_fake_root "$root"

	cat > "$bindir/opkg" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$bindir/opkg"

	run_install "$root" "$bindir" >/dev/null

	assert_file "$root/etc/netdata/charts.d/sqm.conf"
	assert_file "$root/usr/lib/netdata/charts.d/sqm.chart.sh"
	assert_contains "$root/etc/netdata/charts.d.conf" "sqm=yes"
	assert_contains "$root/etc/netdata/netdata.conf" "charts.d = yes"
	assert_contains "$root/etc/init.d/netdata.restart.log" "restart"

	rm -rf "$tmp"
}

test_existing_sqm_conf_merge() {
	local tmp root bindir conf
	tmp="$(mktemp -d)"
	root="$tmp/root"
	bindir="$tmp/bin"
	conf="$root/etc/netdata/charts.d/sqm.conf"
	mkdir -p "$bindir"
	make_fake_root "$root"

	cat > "$bindir/opkg" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$bindir/opkg"

	cat > "$conf" <<'EOF'
declare -a sqm_ifc=("wan")
sqm_cake_mq_mode="queue"
sqm_priority=12345
EOF

	run_install "$root" "$bindir" >/dev/null

	assert_contains "$conf" 'declare -a sqm_ifc=("wan")'
	assert_contains "$conf" 'sqm_cake_mq_mode="queue"'
	assert_contains "$conf" 'sqm_priority=12345'
	assert_contains "$conf" 'sqm_collector="shell"'
	assert_contains "$conf" 'sqm_go_collector_bin="/usr/lib/netdata/charts.d/sqm-go-collector"'

	[ "$(grep -c '^sqm_priority=' "$conf")" -eq 1 ] || fail "sqm_priority duplicated after merge"
	[ "$(grep -c '^sqm_cake_mq_mode=' "$conf")" -eq 1 ] || fail "sqm_cake_mq_mode duplicated after merge"

	rm -rf "$tmp"
}

test_go_collector_download() {
	local tmp root bindir
	tmp="$(mktemp -d)"
	root="$tmp/root"
	bindir="$tmp/bin"
	mkdir -p "$bindir"
	make_fake_root "$root"

	cat > "$bindir/opkg" <<'EOF'
#!/bin/sh
exit 0
EOF
	cat > "$bindir/uname" <<'EOF'
#!/bin/sh
echo x86_64
EOF
	cat > "$bindir/curl" <<'EOF'
#!/bin/sh
out=""
url=""
while [ $# -gt 0 ]; do
	if [ "$1" = "-o" ]; then
		out="$2"
		shift 2
		continue
	fi
	case "$1" in
	http://* | https://*)
		url="$1"
		;;
	esac
	shift
done
[ -n "$out" ] || exit 1
[ -n "${CURL_URL_FILE:-}" ] && echo "$url" >"$CURL_URL_FILE"
cat > "$out" <<'BIN'
#!/bin/sh
echo fake
BIN
chmod 0755 "$out"
exit 0
EOF
	chmod +x "$bindir/opkg" "$bindir/uname" "$bindir/curl"

	(
		cd "$REPO_ROOT"
		PATH="$bindir:/usr/bin:/bin" \
			SQM_ROOT_PREFIX="$root" \
			SQM_INSTALL_GO_COLLECTOR=1 \
			SQM_GO_COLLECTOR_BASE_URL="https://example.invalid/pkg" \
			SQM_GO_COLLECTOR_VERSION="test" \
			CURL_URL_FILE="$tmp/curl-url.txt" \
			sh ./install.sh >/dev/null </dev/null
	)

	assert_file "$root/usr/lib/netdata/charts.d/sqm-go-collector"
	[ -x "$root/usr/lib/netdata/charts.d/sqm-go-collector" ] || fail "sqm-go-collector is not executable"
	assert_contains "$tmp/curl-url.txt" "https://example.invalid/pkg/test/sqm-go-collector-linux-amd64"

	rm -rf "$tmp"
}

test_go_collector_default_latest_release() {
	local tmp root bindir
	tmp="$(mktemp -d)"
	root="$tmp/root"
	bindir="$tmp/bin"
	mkdir -p "$bindir"
	make_fake_root "$root"

	cat > "$bindir/opkg" <<'EOF'
#!/bin/sh
exit 0
EOF
	cat > "$bindir/uname" <<'EOF'
#!/bin/sh
echo x86_64
EOF
	cat > "$bindir/curl" <<'EOF'
#!/bin/sh
out=""
url=""
while [ $# -gt 0 ]; do
	if [ "$1" = "-o" ]; then
		out="$2"
		shift 2
		continue
	fi
	case "$1" in
	http://* | https://*)
		url="$1"
		;;
	esac
	shift
done
[ -n "$out" ] || exit 1
[ -n "${CURL_URL_FILE:-}" ] && echo "$url" >"$CURL_URL_FILE"
cat > "$out" <<'BIN'
#!/bin/sh
echo fake
BIN
chmod 0755 "$out"
exit 0
EOF
	chmod +x "$bindir/opkg" "$bindir/uname" "$bindir/curl"

	(
		cd "$REPO_ROOT"
		PATH="$bindir:/usr/bin:/bin" \
			SQM_ROOT_PREFIX="$root" \
			SQM_INSTALL_GO_COLLECTOR=1 \
			CURL_URL_FILE="$tmp/curl-url.txt" \
			sh ./install.sh >/dev/null </dev/null
	)

	assert_file "$root/usr/lib/netdata/charts.d/sqm-go-collector"
	assert_contains "$tmp/curl-url.txt" "https://github.com/Fail-Safe/netdata-chart-sqm/releases/latest/download/sqm-go-collector-linux-amd64"

	rm -rf "$tmp"
}

test_no_package_manager() {
	local tmp root bindir
	tmp="$(mktemp -d)"
	root="$tmp/root"
	bindir="$tmp/bin"
	mkdir -p "$bindir"
	make_fake_root "$root"

	set +e
	out="$(
		cd "$REPO_ROOT" && \
			PATH="$bindir" SQM_ROOT_PREFIX="$root" /bin/sh ./install.sh 2>&1
	)"
	rc=$?
	set -e

	[ "$rc" -ne 0 ] || fail "expected non-zero exit without opkg/apk"
	echo "$out" | grep -Fq "No supported package manager found" || fail "missing no package manager error"

	rm -rf "$tmp"
}

test_basic_install
test_existing_sqm_conf_merge
test_go_collector_download
test_go_collector_default_latest_release
test_no_package_manager
echo "install-test.sh: PASS"
