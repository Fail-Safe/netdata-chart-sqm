# shellcheck shell=bash
# no need for shebang - this file is loaded from charts.d.plugin
# SPDX-License-Identifier: GPL-3.0-or-later

# netdata
# real-time performance and health monitoring, done right!
# (C) 2016 Costa Tsaousis <costa@tsaousis.gr>
#

# if this chart is called X.chart.sh, then all functions and global variables
# must start with X_

# _update_every is a special variable - it holds the number of seconds
# between the calls of the _update() function
sqm_update_every=

# global variables to store our collected data
# remember: they need to start with the module name sqm_
sqm_ifr="${sqm_ifc//[!0-9A-Za-z]/_}"

sqm_qdisc_bytes=0
sqm_qdisc_drops=0
sqm_qdisc_backlog=0

declare -a sqm_tns
declare -a sqm_tns_vals_traffic_kb
declare -a sqm_tns_vals_traffic_thres
declare -a sqm_tns_vals_latency_target
declare -a sqm_tns_vals_latency_peak
declare -a sqm_tns_vals_latency_average
declare -a sqm_tns_vals_latency_sparse
declare -a sqm_tns_vals_drops_backlog_backlog
declare -a sqm_tns_vals_drops_backlog_acks
declare -a sqm_tns_vals_drops_backlog_drops
declare -a sqm_tns_vals_drops_backlog_ecn
declare -a sqm_tns_vals_flows_sparse
declare -a sqm_tns_vals_flows_bulk
declare -a sqm_tns_vals_flows_unresponsive

# load external functions
. /usr/share/libubox/jshn.sh

# perform the query of tc to get qdisc output
sqm_query_tc() {
  local jsn
  
  jsn=$(tc -s -j qdisc show dev $sqm_ifc) || return 1
  
  # strip leading & trailing []
  jsn="${jsn#[}" ; jsn="${jsn%]}"

  echo "$jsn"
}

sqm_set_overall() {
  # Overall
  json_get_vars bytes drops backlog

  sqm_qdisc_bytes=$bytes
  sqm_qdisc_drops=$drops
  sqm_qdisc_backlog=$backlog
}

sqm_set_tins() {
  local tin i

  # empty all the arrays
  sqm_tns_vals_traffic_kb=()
  sqm_tns_vals_traffic_thres=()
  sqm_tns_vals_latency_target=()
  sqm_tns_vals_latency_peak=()
  sqm_tns_vals_latency_average=()
  sqm_tns_vals_latency_sparse=()
  sqm_tns_vals_drops_backlog_backlog=()
  sqm_tns_vals_drops_backlog_acks=()
  sqm_tns_vals_drops_backlog_drops=()
  sqm_tns_vals_drops_backlog_ecn=()
  sqm_tns_vals_flows_sparse=()
  sqm_tns_vals_flows_bulk=()
  sqm_tns_vals_flows_unresponsive=()

  # Options
  json_select options
  json_get_vars bandwidth diffserv
  json_select ".."

  # Tins
  # Flows & delays indicate the state as of the last packet that flowed through, so they appear to get stuck.
  # Discard the results from a stuck tin.
  json_get_keys tins tins
  json_select tins
  i=0
  for tin in $tins; do
    json_select "$tin"
    tn="${sqm_tns[i]}"

    json_get_vars threshold_rate sent_bytes sent_packets backlog_bytes target_us peak_delay_us avg_delay_us base_delay_us drops ecn_mark ack_drops sparse_flows bulk_flows unresponsive_flows

    eval osp="\$osp${sqm_ifr}t${i}"
    if  [ "$osp" ] && [ "$osp" -eq "$sent_packets" ] ; then
      peak_delay_us=0; avg_delay_us=0; base_delay_us=0
      sparse_flows=0; bulk_flows=0; unresponsive_flows=0
    else
      eval "osp${sqm_ifr}t${i}=$sent_packets"
    fi

    sqm_tns_vals_traffic_kb[i]=$sent_bytes
    sqm_tns_vals_traffic_thres[i]=$threshold_rate
    sqm_tns_vals_latency_target[i]=$target_us
    sqm_tns_vals_latency_peak[i]=$peak_delay_us
    sqm_tns_vals_latency_average[i]=$avg_delay_us
    sqm_tns_vals_latency_sparse[i]=$base_delay_us
    sqm_tns_vals_drops_backlog_backlog[i]=$backlog_bytes
    sqm_tns_vals_drops_backlog_acks[i]=$ack_drops
    sqm_tns_vals_drops_backlog_drops[i]=$drops
    sqm_tns_vals_drops_backlog_ecn[i]=$ecn_mark
    sqm_tns_vals_flows_sparse[i]=$sparse_flows
    sqm_tns_vals_flows_bulk[i]=$bulk_flows
    sqm_tns_vals_flows_unresponsive[i]=$unresponsive_flows

    json_select ..
    i=$((i+1))
  done
  json_select ..
}

sqm_create_overall() {
  cat << EOF
CHART "SQM.${sqm_ifc}_overview" 'overview' "SQM qdisc $sqm_ifc Overview" '' Qdisc '' line $((sqm_priority)) $sqm_update_every
DIMENSION 'Kb/s' '' incremental 1 1024
DIMENSION 'Backlog/B' '' incremental 1 1024
DIMENSION 'Drops/s' '' absolute 1 1
EOF
}

sqm_create_tins() {
  local tin i j

  # Options
  json_select options
  json_get_vars bandwidth diffserv
  json_select ".."

  case "$diffserv" in
      diffserv3)
        sqm_tns=("BK" "BE" "VI")
        ;;
      diffserv4)
        sqm_tns=("BK" "BE" "VI" "VO")
        ;;
      *)
        sqm_tns=("T0" "T1" "T2" "T3" "T4" "T5" "T6" "T7")
        ;;
  esac

  # Tins
  # Flows & delays indicate the state as of the last packet that flowed through, so they appear to get stuck.
  # Discard the results from a stuck tin.
  json_get_keys tins tins
  json_select tins
  i=0
  j=0
  for tin in $tins; do
      json_select "$tin"
      tn="${sqm_tns[i]}"
      
      cat << EOF
CHART "SQM.${tn}_traffic" '' "CAKE $sqm_ifc $tn Traffic" 'Kb/s' $tn 'traffic' line $((sqm_priority + 1 + j)) $sqm_update_every
DIMENSION 'Kb/s' '' incremental 1 1024
DIMENSION 'Thres' '' absolute 1 1024
CHART "SQM.${tn}_latency" '' "CAKE $sqm_ifc $tn Latency" 'ms' $tn 'latency' line $((sqm_priority + 2 + j)) $sqm_update_every
DIMENSION 'Target' '' absolute 1 1000
DIMENSION 'Peak' '' absolute 1 1000
DIMENSION 'Avg' '' absolute 1 1000
DIMENSION 'Sparse' '' absolute 1 1000
CHART "SQM.${tn}_drops" '' "CAKE $sqm_ifc $tn Drops/s" 'Drops/s' $tn 'drops' line $((sqm_priority + 3 + j)) $sqm_update_every
DIMENSION 'Ack' '' incremental 1 1
DIMENSION 'Drops' '' incremental 1 1
DIMENSION 'Ecn' '' incremental 1 1
CHART "SQM.${tn}_backlog" '' "CAKE $sqm_ifc $tn Backlog" 'Bytes' $tn 'backlog' line $((sqm_priority + 4 + j)) $sqm_update_every
DIMENSION 'Backlog' '' absolute 1 1024
CHART "SQM.${tn}_flows" '' "CAKE $sqm_ifc $tn Flow Counts" 'Flows' $tn 'flows' line $((sqm_priority + 5 + j)) $sqm_update_every
DIMENSION 'Sparse' '' absolute 1 1
DIMENSION 'Bulk' '' absolute 1 1
DIMENSION 'Unresponsive' '' absolute 1 1
EOF
      i=$((i+1))
      j=$((j+5))
      json_select ..
  done
  json_select ..
}

sqm_get() {
  # do all the work to collect / calculate the values
  # for each dimension
  #
  # Remember:
  # 1. KEEP IT SIMPLE AND SHORT
  # 2. AVOID FORKS (avoid piping commands)
  # 3. AVOID CALLING TOO MANY EXTERNAL PROGRAMS
  # 4. USE LOCAL VARIABLES (global variables may overlap with other modules)

  local jsn

  jsn=$(sqm_query_tc) || return 1

  json_load "${jsn}"
  json_get_var qdisc kind

  case "$qdisc" in
      cake)
        sqm_set_overall
        sqm_set_tins
        ;;
      mq)
        sqm_set_overall
        ;;

      *) echo "Unknown qdisc type '$qdisc' on interface '$sqm_ifc'" 1>&2
        return 1
        ;;
  esac

  json_cleanup

  # this should return:
  #  - 0 to send the data to netdata
  #  - 1 to report a failure to collect the data
  return 0
}

# _check is called once, to find out if this chart should be enabled or not
sqm_check() {
  # this should return:
  #  - 0 to enable the chart
  #  - 1 to disable the chart

  # check that we can collect data
  require_cmd tc || return 1
  sqm_query_tc &>/dev/null || return 1

  return 0
}

# _create is called once, to create the charts
sqm_create() {
  local jsn

  jsn=$(sqm_query_tc) || return 1

  json_load "${jsn}"
  json_get_var qdisc kind

  case "$qdisc" in
      cake)
        sqm_create_overall
        sqm_create_tins
        ;;
      mq)
        sqm_create_overall
        ;;

      *) echo "Unknown qdisc type '$qdisc' on interface '$sqm_ifc'" 1>&2
      return 1
      ;;
  esac

  json_cleanup

  return 0
}

# _update is called continuously, to collect the values
sqm_update() {
  # the first argument to this function is the microseconds since last update
  # pass this parameter to the BEGIN statement (see bellow).

  sqm_get || return 1

  # write the result of the work.
  cat << VALUESOF
BEGIN "SQM.${sqm_ifc}_overview" $1
SET 'Kb/s' = $sqm_qdisc_bytes
SET 'Backlog/B' = $sqm_qdisc_drops
SET 'Drops/s' = $sqm_qdisc_backlog
END
VALUESOF

  i=0
  for tn in "${sqm_tns[@]}"; do
    cat << VALUESOF
BEGIN "SQM.${tn}_traffic" $1
SET 'Kb/s' = ${sqm_tns_vals_traffic_kb[i]}
SET 'Thres' = ${sqm_tns_vals_traffic_thres[i]}
END
BEGIN "SQM.${tn}_latency" $1
SET 'Target' = ${sqm_tns_vals_latency_target[i]}
SET 'Peak' = ${sqm_tns_vals_latency_peak[i]}
SET 'Avg' = ${sqm_tns_vals_latency_average[i]}
SET 'Sparse' = ${sqm_tns_vals_latency_sparse[i]}
END
BEGIN "SQM.${tn}_drops" $1
SET 'Ack' = ${sqm_tns_vals_drops_backlog_acks[i]}
SET 'Drops' = ${sqm_tns_vals_drops_backlog_drops[i]}
SET 'Ecn' = ${sqm_tns_vals_drops_backlog_ecn[i]}
END
BEGIN "SQM.${tn}_backlog" $1
SET 'Backlog' = ${sqm_tns_vals_drops_backlog_backlog[i]}
END
BEGIN "SQM.${tn}_flows" $1
SET 'Sparse' = ${sqm_tns_vals_flows_sparse[i]}
SET 'Bulk' = ${sqm_tns_vals_flows_bulk[i]}
SET 'Unresponsive' = ${sqm_tns_vals_flows_unresponsive[i]}
END
VALUESOF
    i=$((i+1))
  done

  return 0
}
