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
while [ $# -gt 0 ]; do
	if [ "$1" = "-o" ]; then
		out="$2"
		shift 2
		continue
	fi
	shift
done
[ -n "$out" ] || exit 1
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
			sh ./install.sh >/dev/null </dev/null
	)

	assert_file "$root/usr/lib/netdata/charts.d/sqm-go-collector"
	[ -x "$root/usr/lib/netdata/charts.d/sqm-go-collector" ] || fail "sqm-go-collector is not executable"

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
test_go_collector_download
test_no_package_manager
echo "install-test.sh: PASS"
