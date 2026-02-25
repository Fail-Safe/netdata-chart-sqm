#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_contains() {
	local text="$1"
	local needle="$2"
	[[ "$text" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

mkdir -p "$TMP/bin"

cat > "$TMP/bin/tc" <<'EOF'
#!/bin/sh
if [ "$1" = "-s" ] && [ "$2" = "-j" ] && [ "$3" = "qdisc" ] && [ "$4" = "show" ] && [ "$5" = "dev" ] && [ "$6" = "eth0" ]; then
	if [ "${7:-}" = "root" ]; then
		cat <<'JSON'
[{"kind":"cake_mq","handle":"1:","root":true,"bytes":1000,"drops":1,"backlog":0}]
JSON
	else
		cat <<'JSON'
[
  {"kind":"cake_mq","handle":"1:","root":true,"bytes":1000,"drops":1,"backlog":0},
  {"kind":"cake","handle":"10:","parent":"1:1","bytes":600,"drops":0,"backlog":0,"options":{"diffserv":"diffserv4"},"tins":[
    {"threshold_rate":1000,"sent_bytes":100,"backlog_bytes":1,"target_us":5000,"peak_delay_us":10,"avg_delay_us":5,"base_delay_us":1,"sent_packets":10,"drops":0,"ecn_mark":0,"ack_drops":0,"sparse_flows":1,"bulk_flows":1,"unresponsive_flows":0},
    {"threshold_rate":2000,"sent_bytes":200,"backlog_bytes":2,"target_us":5000,"peak_delay_us":10,"avg_delay_us":5,"base_delay_us":1,"sent_packets":20,"drops":0,"ecn_mark":0,"ack_drops":0,"sparse_flows":1,"bulk_flows":1,"unresponsive_flows":0},
    {"threshold_rate":3000,"sent_bytes":300,"backlog_bytes":3,"target_us":5000,"peak_delay_us":10,"avg_delay_us":5,"base_delay_us":1,"sent_packets":30,"drops":0,"ecn_mark":0,"ack_drops":0,"sparse_flows":1,"bulk_flows":1,"unresponsive_flows":0},
    {"threshold_rate":4000,"sent_bytes":400,"backlog_bytes":4,"target_us":5000,"peak_delay_us":10,"avg_delay_us":5,"base_delay_us":1,"sent_packets":40,"drops":0,"ecn_mark":0,"ack_drops":0,"sparse_flows":1,"bulk_flows":1,"unresponsive_flows":0}
  ]},
  {"kind":"cake","handle":"20:","parent":"1:2","bytes":400,"drops":0,"backlog":0,"options":{"diffserv":"diffserv4"},"tins":[
    {"threshold_rate":1100,"sent_bytes":110,"backlog_bytes":1,"target_us":5000,"peak_delay_us":10,"avg_delay_us":5,"base_delay_us":1,"sent_packets":11,"drops":0,"ecn_mark":0,"ack_drops":0,"sparse_flows":1,"bulk_flows":1,"unresponsive_flows":0},
    {"threshold_rate":2100,"sent_bytes":210,"backlog_bytes":2,"target_us":5000,"peak_delay_us":10,"avg_delay_us":5,"base_delay_us":1,"sent_packets":21,"drops":0,"ecn_mark":0,"ack_drops":0,"sparse_flows":1,"bulk_flows":1,"unresponsive_flows":0},
    {"threshold_rate":3100,"sent_bytes":310,"backlog_bytes":3,"target_us":5000,"peak_delay_us":10,"avg_delay_us":5,"base_delay_us":1,"sent_packets":31,"drops":0,"ecn_mark":0,"ack_drops":0,"sparse_flows":1,"bulk_flows":1,"unresponsive_flows":0},
    {"threshold_rate":4100,"sent_bytes":410,"backlog_bytes":4,"target_us":5000,"peak_delay_us":10,"avg_delay_us":5,"base_delay_us":1,"sent_packets":41,"drops":0,"ecn_mark":0,"ack_drops":0,"sparse_flows":1,"bulk_flows":1,"unresponsive_flows":0}
  ]}
]
JSON
	fi
	exit 0
fi
echo "unexpected tc args: $*" >&2
exit 1
EOF
chmod +x "$TMP/bin/tc"

BIN="$TMP/sqm-go-collector"
(
	cd "$REPO_ROOT/sqm-go-collector"
	go build -o "$BIN" ./cmd/sqm-go-collector
)

CREATE_OUT="$(PATH="$TMP/bin:/usr/bin:/bin" "$BIN" -ifc eth0 -mode overlay -format netdata-create -priority 90000 -update-every 1)"
UPDATE_OUT="$(PATH="$TMP/bin:/usr/bin:/bin" "$BIN" -ifc eth0 -mode overlay -format netdata-update -microseconds 1000000)"

assert_contains "$CREATE_OUT" "CHART \"SQM.eth0_BE_traffic\""
assert_contains "$CREATE_OUT" "DIMENSION 'q1_bytes' 'Q1_Bytes' incremental 1 125"
assert_contains "$UPDATE_OUT" "BEGIN \"SQM.eth0_BE_traffic\" 1000000"
assert_contains "$UPDATE_OUT" "SET 'q1_bytes' = 200"

echo "sqm-go-collector-bin-test.sh: PASS"
