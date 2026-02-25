#!/usr/bin/env bash
set -euo pipefail

# Compare startup/runtime cost of standard vs UPX-packed binaries.
#
# Usage:
#   ./scripts/compare-startup.sh \
#     --std release/sqm-go-collector-linux-amd64 \
#     --upx release/sqm-go-collector-linux-amd64.upx \
#     --runs 20 -- -ifc eth0,ifb4eth0 -mode overlay -format metrics
#
# Notes:
# - Everything after "--" is passed to both binaries unchanged.
# - By default, output is discarded to focus on timing.
# - Set KEEP_OUTPUT=1 to keep command output.

STD_BIN=""
UPX_BIN=""
RUNS=15
INNER_RUNS=25
DEBUG_TIMER="${DEBUG_TIMER:-0}"
TIMER_BACKEND="unknown"

detect_timer_backend() {
	if [[ -r /proc/uptime ]]; then
		TIMER_BACKEND="proc_uptime"
		return
	fi
	if command -v perl >/dev/null 2>&1; then
		TIMER_BACKEND="perl_time_hires"
		return
	fi
	local sec nsec
	sec=$(date +%s 2>/dev/null || true)
	nsec=$(date +%N 2>/dev/null || true)
	if [[ "$sec" =~ ^[0-9]+$ && "$nsec" =~ ^[0-9]+$ ]]; then
		TIMER_BACKEND="date_sec_nsec"
		return
	fi
	if [[ "$sec" =~ ^[0-9]+$ ]]; then
		TIMER_BACKEND="date_sec"
	else
		TIMER_BACKEND="fallback_zero"
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--std)
		STD_BIN="$2"
		shift 2
		;;
	--upx)
		UPX_BIN="$2"
		shift 2
		;;
	--runs)
		RUNS="$2"
		shift 2
		;;
	--inner)
		INNER_RUNS="$2"
		shift 2
		;;
	--)
		shift
		break
		;;
	*)
		echo "Unknown option: $1" >&2
		exit 1
		;;
	esac
done

CMD_ARGS=("$@")

if [[ -z "$STD_BIN" || -z "$UPX_BIN" ]]; then
	echo "--std and --upx are required" >&2
	exit 1
fi

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || [[ "$RUNS" -lt 1 ]]; then
	echo "--runs must be a positive integer" >&2
	exit 1
fi
if ! [[ "$INNER_RUNS" =~ ^[0-9]+$ ]] || [[ "$INNER_RUNS" -lt 1 ]]; then
	echo "--inner must be a positive integer" >&2
	exit 1
fi

if [[ ! -x "$STD_BIN" ]]; then
	echo "STD binary not found/executable: $STD_BIN" >&2
	exit 1
fi
if [[ ! -x "$UPX_BIN" ]]; then
	echo "UPX binary not found/executable: $UPX_BIN" >&2
	exit 1
fi

now_us() {
	# Linux/OpenWrt first choice: /proc/uptime is monotonic-ish and widely available.
	# Return seconds (float-like string), not scaled integers, to avoid overflow/precision
	# issues on smaller awk implementations.
	if [[ "$TIMER_BACKEND" == "proc_uptime" ]]; then
		awk '{print $1}' /proc/uptime
		return 0
	fi

	# High resolution via perl if available.
	if [[ "$TIMER_BACKEND" == "perl_time_hires" ]]; then
		perl -MTime::HiRes=time -e 'printf "%.6f\n", time()'
		return 0
	fi

	# date fallback: only use %N if it is actually numeric on this platform.
	local sec nsec
	sec=$(date +%s 2>/dev/null || true)
	nsec=$(date +%N 2>/dev/null || true)
	if [[ "$TIMER_BACKEND" == "date_sec_nsec" ]] && [[ "$sec" =~ ^[0-9]+$ && "$nsec" =~ ^[0-9]+$ ]]; then
		awk -v s="$sec" -v n="$nsec" 'BEGIN { printf "%.6f\n", s + (n/1000000000) }'
		return 0
	fi

	# Last fallback: second resolution.
	if [[ "$sec" =~ ^[0-9]+$ ]]; then
		echo "$sec"
	else
		echo "0"
	fi
}

measure_us() {
	local bin="$1"
	shift
	local start_s end_s total_us i
	local loops="$INNER_RUNS"
	local attempt

	# Coarse timers on some OpenWrt targets can produce 0 for fast runs.
	# Adapt by increasing inner loops until elapsed time is measurable.
	for attempt in 1 2 3 4; do
		start_s=$(now_us)
		for ((i = 1; i <= loops; i++)); do
			if [[ "${KEEP_OUTPUT:-0}" == "1" && "$i" -eq "$loops" ]]; then
				"$bin" "$@"
			else
				"$bin" "$@" >/dev/null 2>&1
			fi
		done
		end_s=$(now_us)

		total_us=$(awk -v s="$start_s" -v e="$end_s" 'BEGIN { d=e-s; if (d<0) d=0; printf "%.0f\n", d*1000000 }')
		if [[ "$total_us" -gt 0 ]]; then
			break
		fi

		loops=$((loops * 10))
	done

	# Return average microseconds per invocation across measured loops.
	# If elapsed was measurable but truncation would produce 0, clamp to 1us.
	awk -v t="$total_us" -v l="$loops" 'BEGIN { if (l<1) l=1; a=t/l; if (t>0 && a<1) a=1; printf "%.0f\n", a }'
}

run_series() {
	local label="$1"
	local bin="$2"
	shift 2

	local min_us=-1
	local max_us=0
	local sum_us=0
	local i us

	for ((i = 1; i <= RUNS; i++)); do
		us=$(measure_us "$bin" "$@")
		sum_us=$((sum_us + us))
		if [[ "$min_us" -lt 0 || "$us" -lt "$min_us" ]]; then
			min_us=$us
		fi
		if [[ "$us" -gt "$max_us" ]]; then
			max_us=$us
		fi
	done

	local avg_us avg_ms min_ms max_ms
	avg_us=$(awk -v s="$sum_us" -v r="$RUNS" 'BEGIN { printf "%.2f", s/r }')
	avg_ms=$(awk -v u="$avg_us" 'BEGIN { printf "%.3f", u/1000 }')
	min_ms=$(awk -v u="$min_us" 'BEGIN { printf "%.3f", u/1000 }')
	max_ms=$(awk -v u="$max_us" 'BEGIN { printf "%.3f", u/1000 }')

	printf "%s\t%s\t%s\t%s\n" "$label" "$avg_ms" "$min_ms" "$max_ms"
}

echo "Comparing binaries with args: ${CMD_ARGS[*]:-(none)}"
echo "Outer runs: $RUNS, inner runs per sample: $INNER_RUNS"
detect_timer_backend
_probe_now=$(now_us)
if [[ "$DEBUG_TIMER" == "1" ]]; then
	echo "Timer backend: $TIMER_BACKEND"
	echo "Timer probe value: $_probe_now"
fi
printf "%-8s\t%-10s\t%-8s\t%-8s\n" "Binary" "Avg(ms)" "Min(ms)" "Max(ms)"

std_line=$(run_series "std" "$STD_BIN" "${CMD_ARGS[@]}")
upx_line=$(run_series "upx" "$UPX_BIN" "${CMD_ARGS[@]}")

printf "%s\n" "$std_line"
printf "%s\n" "$upx_line"

std_avg=$(awk -F'\t' '{print $2}' <<<"$std_line")
upx_avg=$(awk -F'\t' '{print $2}' <<<"$upx_line")

delta_ms=$(awk -v a="$upx_avg" -v b="$std_avg" 'BEGIN { printf "%.2f", a-b }')
delta_pct=$(awk -v a="$upx_avg" -v b="$std_avg" 'BEGIN { if (b == 0) { print "0.00" } else { printf "%.2f", ((a-b)/b)*100 } }')

echo "---"
echo "Delta (upx - std): ${delta_ms} ms (${delta_pct}%)"
