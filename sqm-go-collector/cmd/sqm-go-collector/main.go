package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
)

type qdiscOptions struct {
	Diffserv string `json:"diffserv"`
}

type tcTin struct {
	ThresholdRate     uint64 `json:"threshold_rate"`
	SentBytes         uint64 `json:"sent_bytes"`
	BacklogBytes      uint64 `json:"backlog_bytes"`
	TargetUS          uint64 `json:"target_us"`
	PeakDelayUS       uint64 `json:"peak_delay_us"`
	AvgDelayUS        uint64 `json:"avg_delay_us"`
	BaseDelayUS       uint64 `json:"base_delay_us"`
	SentPackets       uint64 `json:"sent_packets"`
	Drops             uint64 `json:"drops"`
	ECNMark           uint64 `json:"ecn_mark"`
	AckDrops          uint64 `json:"ack_drops"`
	SparseFlows       uint64 `json:"sparse_flows"`
	BulkFlows         uint64 `json:"bulk_flows"`
	UnresponsiveFlows uint64 `json:"unresponsive_flows"`
}

type tcQdisc struct {
	Kind    string       `json:"kind"`
	Handle  string       `json:"handle"`
	Parent  string       `json:"parent"`
	Root    bool         `json:"root"`
	Options qdiscOptions `json:"options"`
	Bytes   uint64       `json:"bytes"`
	Drops   uint64       `json:"drops"`
	Backlog uint64       `json:"backlog"`
	Tins    []tcTin      `json:"tins"`
}

type overview struct {
	Bytes   uint64 `json:"bytes"`
	Drops   uint64 `json:"drops"`
	Backlog uint64 `json:"backlog"`
}

type tinMetrics struct {
	Tin               string `json:"tin"`
	ThresholdRate     uint64 `json:"threshold_rate"`
	SentBytes         uint64 `json:"sent_bytes"`
	BacklogBytes      uint64 `json:"backlog_bytes"`
	TargetUS          uint64 `json:"target_us"`
	PeakDelayUS       uint64 `json:"peak_delay_us"`
	AvgDelayUS        uint64 `json:"avg_delay_us"`
	BaseDelayUS       uint64 `json:"base_delay_us"`
	Drops             uint64 `json:"drops"`
	ECNMark           uint64 `json:"ecn_mark"`
	AckDrops          uint64 `json:"ack_drops"`
	SparseFlows       uint64 `json:"sparse_flows"`
	BulkFlows         uint64 `json:"bulk_flows"`
	UnresponsiveFlows uint64 `json:"unresponsive_flows"`
}

type queueReport struct {
	QueueID  string       `json:"queue_id"`
	Parent   string       `json:"parent"`
	Overview overview     `json:"overview"`
	Tins     []tinMetrics `json:"tins"`
}

type ifaceReport struct {
	Interface  string        `json:"interface"`
	Mode       string        `json:"mode"`
	RootKind   string        `json:"root_kind"`
	RootHandle string        `json:"root_handle"`
	Overview   overview      `json:"overview"`
	Queues     []queueReport `json:"queues"`
}

type result struct {
	Reports []ifaceReport `json:"reports"`
}

type dimensionDef struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Algo string `json:"algo"`
	Mul  int    `json:"mul"`
	Div  int    `json:"div"`
}

type chartDef struct {
	ID      string         `json:"id"`
	Title   string         `json:"title"`
	Units   string         `json:"units"`
	Family  string         `json:"family"`
	Context string         `json:"context"`
	Dims    []dimensionDef `json:"dims"`
}

type planOutput struct {
	Charts  []chartDef                   `json:"charts"`
	Updates map[string]map[string]uint64 `json:"updates"`
}

func main() {
	interfacesRaw := flag.String("ifc", "", "Comma-separated interfaces (e.g. eth0,ifb4eth0)")
	mode := flag.String("mode", "cake_mq", "Mode: cake_mq|queue|overlay")
	format := flag.String("format", "json", "Output format: json|metrics|plan|netdata-create|netdata-update")
	pretty := flag.Bool("pretty", false, "Pretty-print JSON")
	priority := flag.Int("priority", 90000, "Chart priority used by -format netdata-create")
	updateEvery := flag.Int("update-every", 1, "Update interval used by -format netdata-create")
	microseconds := flag.Int64("microseconds", 0, "Microseconds since last update used by -format netdata-update")
	flag.Parse()

	if *interfacesRaw == "" {
		fatal(errors.New("-ifc is required"))
	}
	if *mode != "cake_mq" && *mode != "queue" && *mode != "overlay" {
		fatal(fmt.Errorf("invalid -mode %q (expected cake_mq|queue|overlay)", *mode))
	}
	if *format != "json" && *format != "metrics" && *format != "plan" && *format != "netdata-create" && *format != "netdata-update" {
		fatal(fmt.Errorf("invalid -format %q (expected json|metrics|plan|netdata-create|netdata-update)", *format))
	}

	interfaces := splitNonEmpty(*interfacesRaw, ",")
	if len(interfaces) == 0 {
		fatal(errors.New("no interfaces after parsing -ifc"))
	}

	out := result{Reports: make([]ifaceReport, 0, len(interfaces))}
	for _, ifc := range interfaces {
		report, err := collectInterface(ifc, *mode)
		if err != nil {
			fatal(fmt.Errorf("%s: %w", ifc, err))
		}
		out.Reports = append(out.Reports, report)
	}

	if *format == "plan" {
		plan := buildPlan(out)
		var b []byte
		var err error
		if *pretty {
			b, err = json.MarshalIndent(plan, "", "  ")
		} else {
			b, err = json.Marshal(plan)
		}
		if err != nil {
			fatal(err)
		}
		fmt.Println(string(b))
	} else if *format == "netdata-create" {
		plan := buildPlan(out)
		emitNetdataCreate(plan, *priority, *updateEvery)
	} else if *format == "netdata-update" {
		plan := buildPlan(out)
		emitNetdataUpdate(plan, *microseconds)
	} else if *format == "metrics" {
		metrics := flattenMetrics(out)
		var b []byte
		var err error
		if *pretty {
			b, err = json.MarshalIndent(metrics, "", "  ")
		} else {
			b, err = json.Marshal(metrics)
		}
		if err != nil {
			fatal(err)
		}
		fmt.Println(string(b))
	} else {
		var b []byte
		var err error
		if *pretty {
			b, err = json.MarshalIndent(out, "", "  ")
		} else {
			b, err = json.Marshal(out)
		}
		if err != nil {
			fatal(err)
		}
		fmt.Println(string(b))
	}
}

func buildPlan(in result) planOutput {
	charts := make(map[string]*chartDef)
	updates := make(map[string]map[string]uint64)

	addUpdate := func(chartID, dimID string, v uint64) {
		if _, ok := updates[chartID]; !ok {
			updates[chartID] = make(map[string]uint64)
		}
		updates[chartID][dimID] = v
	}

	ensureChart := func(id, title, units, family, context string) *chartDef {
		if c, ok := charts[id]; ok {
			return c
		}
		c := &chartDef{ID: id, Title: title, Units: units, Family: family, Context: context, Dims: []dimensionDef{}}
		charts[id] = c
		return c
	}

	ensureDim := func(c *chartDef, id, name, algo string, mul, div int) {
		for _, d := range c.Dims {
			if d.ID == id {
				return
			}
		}
		c.Dims = append(c.Dims, dimensionDef{ID: id, Name: name, Algo: algo, Mul: mul, Div: div})
	}

	for _, rep := range in.Reports {
		ifc := sanitizeKey(rep.Interface)
		overviewID := fmt.Sprintf("SQM.%s_overview", ifc)
		overview := ensureChart(overviewID, fmt.Sprintf("SQM qdisc %s Overview", rep.Interface), "mixed", fmt.Sprintf("%s Qdisc", rep.Interface), "overview")
		ensureDim(overview, "bytes", "Bytes", "incremental", 1, 1)
		ensureDim(overview, "backlog", "Backlog", "incremental", 1, 1)
		ensureDim(overview, "drops", "Drops", "incremental", 1, 1)
		addUpdate(overviewID, "bytes", rep.Overview.Bytes)
		addUpdate(overviewID, "backlog", rep.Overview.Backlog)
		addUpdate(overviewID, "drops", rep.Overview.Drops)

		for _, q := range rep.Queues {
			qid := sanitizeKey(q.QueueID)
			if qid == "" {
				qid = "0"
			}

			for _, tin := range q.Tins {
				tn := strings.ToUpper(sanitizeKey(tin.Tin))
				if tn == "" {
					tn = "T0"
				}

				var chartPrefix string
				switch rep.Mode {
				case "queue":
					chartPrefix = fmt.Sprintf("SQM.%s_q%s_%s", ifc, qid, tn)
				default:
					chartPrefix = fmt.Sprintf("SQM.%s_%s", ifc, tn)
				}

				trafficID := chartPrefix + "_traffic"
				latencyID := chartPrefix + "_latency"
				dropsID := chartPrefix + "_drops"
				backlogID := chartPrefix + "_backlog"
				flowsID := chartPrefix + "_flows"

				traffic := ensureChart(trafficID, fmt.Sprintf("CAKE %s %s Traffic", rep.Interface, tn), "Kb/s", fmt.Sprintf("%s %s", rep.Interface, tn), "traffic")
				latency := ensureChart(latencyID, fmt.Sprintf("CAKE %s %s Latency", rep.Interface, tn), "ms", fmt.Sprintf("%s %s", rep.Interface, tn), "latency")
				drops := ensureChart(dropsID, fmt.Sprintf("CAKE %s %s Drops", rep.Interface, tn), "drops/s", fmt.Sprintf("%s %s", rep.Interface, tn), "drops")
				backlog := ensureChart(backlogID, fmt.Sprintf("CAKE %s %s Backlog", rep.Interface, tn), "bytes", fmt.Sprintf("%s %s", rep.Interface, tn), "backlog")
				flows := ensureChart(flowsID, fmt.Sprintf("CAKE %s %s Flows", rep.Interface, tn), "flows", fmt.Sprintf("%s %s", rep.Interface, tn), "flows")

				dimPrefix := ""
				if rep.Mode == "overlay" {
					dimPrefix = "q" + qid + "_"
				}

				ensureDim(traffic, dimPrefix+"bytes", strings.ToUpper(dimPrefix)+"Bytes", "incremental", 1, 125)
				ensureDim(traffic, dimPrefix+"thres", strings.ToUpper(dimPrefix)+"Thres", "absolute", 1, 125)
				ensureDim(latency, dimPrefix+"tg", strings.ToUpper(dimPrefix)+"Target", "absolute", 1, 1000)
				ensureDim(latency, dimPrefix+"pk", strings.ToUpper(dimPrefix)+"Peak", "absolute", 1, 1000)
				ensureDim(latency, dimPrefix+"av", strings.ToUpper(dimPrefix)+"Avg", "absolute", 1, 1000)
				ensureDim(latency, dimPrefix+"sp", strings.ToUpper(dimPrefix)+"Sparse", "absolute", 1, 1000)
				ensureDim(drops, dimPrefix+"ack", strings.ToUpper(dimPrefix)+"Ack", "incremental", 1, 1)
				ensureDim(drops, dimPrefix+"drops", strings.ToUpper(dimPrefix)+"Drops", "incremental", 1, 1)
				ensureDim(drops, dimPrefix+"ecn", strings.ToUpper(dimPrefix)+"Ecn", "incremental", 1, 1)
				ensureDim(backlog, dimPrefix+"backlog", strings.ToUpper(dimPrefix)+"Backlog", "absolute", 1, 1)
				ensureDim(flows, dimPrefix+"sp", strings.ToUpper(dimPrefix)+"Sparse", "absolute", 1, 1)
				ensureDim(flows, dimPrefix+"bu", strings.ToUpper(dimPrefix)+"Bulk", "absolute", 1, 1)
				ensureDim(flows, dimPrefix+"un", strings.ToUpper(dimPrefix)+"Unresponsive", "absolute", 1, 1)

				addUpdate(trafficID, dimPrefix+"bytes", tin.SentBytes)
				addUpdate(trafficID, dimPrefix+"thres", tin.ThresholdRate)
				addUpdate(latencyID, dimPrefix+"tg", tin.TargetUS)
				addUpdate(latencyID, dimPrefix+"pk", tin.PeakDelayUS)
				addUpdate(latencyID, dimPrefix+"av", tin.AvgDelayUS)
				addUpdate(latencyID, dimPrefix+"sp", tin.BaseDelayUS)
				addUpdate(dropsID, dimPrefix+"ack", tin.AckDrops)
				addUpdate(dropsID, dimPrefix+"drops", tin.Drops)
				addUpdate(dropsID, dimPrefix+"ecn", tin.ECNMark)
				addUpdate(backlogID, dimPrefix+"backlog", tin.BacklogBytes)
				addUpdate(flowsID, dimPrefix+"sp", tin.SparseFlows)
				addUpdate(flowsID, dimPrefix+"bu", tin.BulkFlows)
				addUpdate(flowsID, dimPrefix+"un", tin.UnresponsiveFlows)
			}
		}
	}

	keys := make([]string, 0, len(charts))
	for k := range charts {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	outCharts := make([]chartDef, 0, len(keys))
	for _, k := range keys {
		c := charts[k]
		sort.Slice(c.Dims, func(i, j int) bool { return c.Dims[i].ID < c.Dims[j].ID })
		outCharts = append(outCharts, *c)
	}

	return planOutput{Charts: outCharts, Updates: updates}
}

func flattenMetrics(in result) map[string]uint64 {
	out := make(map[string]uint64)

	for _, rep := range in.Reports {
		ifc := sanitizeKey(rep.Interface)

		setMetric(out, fmt.Sprintf("%s.overview.bytes", ifc), rep.Overview.Bytes)
		setMetric(out, fmt.Sprintf("%s.overview.drops", ifc), rep.Overview.Drops)
		setMetric(out, fmt.Sprintf("%s.overview.backlog", ifc), rep.Overview.Backlog)

		for _, q := range rep.Queues {
			qid := sanitizeKey(q.QueueID)
			if qid == "" {
				qid = "0"
			}

			for _, tin := range q.Tins {
				tn := strings.ToLower(sanitizeKey(tin.Tin))

				switch rep.Mode {
				case "overlay":
					base := fmt.Sprintf("%s.%s.q%s", ifc, tn, qid)
					setMetric(out, base+".traffic.bytes", tin.SentBytes)
					setMetric(out, base+".traffic.thres", tin.ThresholdRate)
					setMetric(out, base+".latency.target", tin.TargetUS)
					setMetric(out, base+".latency.peak", tin.PeakDelayUS)
					setMetric(out, base+".latency.avg", tin.AvgDelayUS)
					setMetric(out, base+".latency.sparse", tin.BaseDelayUS)
					setMetric(out, base+".drops.ack", tin.AckDrops)
					setMetric(out, base+".drops.drops", tin.Drops)
					setMetric(out, base+".drops.ecn", tin.ECNMark)
					setMetric(out, base+".backlog.bytes", tin.BacklogBytes)
					setMetric(out, base+".flows.sparse", tin.SparseFlows)
					setMetric(out, base+".flows.bulk", tin.BulkFlows)
					setMetric(out, base+".flows.unresponsive", tin.UnresponsiveFlows)
				case "queue":
					base := fmt.Sprintf("%s.q%s.%s", ifc, qid, tn)
					setMetric(out, base+".traffic.bytes", tin.SentBytes)
					setMetric(out, base+".traffic.thres", tin.ThresholdRate)
					setMetric(out, base+".latency.target", tin.TargetUS)
					setMetric(out, base+".latency.peak", tin.PeakDelayUS)
					setMetric(out, base+".latency.avg", tin.AvgDelayUS)
					setMetric(out, base+".latency.sparse", tin.BaseDelayUS)
					setMetric(out, base+".drops.ack", tin.AckDrops)
					setMetric(out, base+".drops.drops", tin.Drops)
					setMetric(out, base+".drops.ecn", tin.ECNMark)
					setMetric(out, base+".backlog.bytes", tin.BacklogBytes)
					setMetric(out, base+".flows.sparse", tin.SparseFlows)
					setMetric(out, base+".flows.bulk", tin.BulkFlows)
					setMetric(out, base+".flows.unresponsive", tin.UnresponsiveFlows)
				default:
					base := fmt.Sprintf("%s.%s", ifc, tn)
					setMetric(out, base+".traffic.bytes", tin.SentBytes)
					setMetric(out, base+".traffic.thres", tin.ThresholdRate)
					setMetric(out, base+".latency.target", tin.TargetUS)
					setMetric(out, base+".latency.peak", tin.PeakDelayUS)
					setMetric(out, base+".latency.avg", tin.AvgDelayUS)
					setMetric(out, base+".latency.sparse", tin.BaseDelayUS)
					setMetric(out, base+".drops.ack", tin.AckDrops)
					setMetric(out, base+".drops.drops", tin.Drops)
					setMetric(out, base+".drops.ecn", tin.ECNMark)
					setMetric(out, base+".backlog.bytes", tin.BacklogBytes)
					setMetric(out, base+".flows.sparse", tin.SparseFlows)
					setMetric(out, base+".flows.bulk", tin.BulkFlows)
					setMetric(out, base+".flows.unresponsive", tin.UnresponsiveFlows)
				}
			}
		}
	}

	return out
}

func emitNetdataCreate(plan planOutput, priority, updateEvery int) {
	if updateEvery <= 0 {
		updateEvery = 1
	}
	order := sortedChartIDs(plan.Updates)
	for i, chartID := range order {
		var chart *chartDef
		for j := range plan.Charts {
			if plan.Charts[j].ID == chartID {
				chart = &plan.Charts[j]
				break
			}
		}
		if chart == nil {
			continue
		}

		fmt.Printf("CHART \"%s\" '' \"%s\" '%s' \"%s\" '%s' line %d %d\n", chart.ID, chart.Title, chart.Units, chart.Family, chart.Context, priority+i, updateEvery)
		for _, d := range chart.Dims {
			mul := d.Mul
			div := d.Div
			if mul == 0 {
				mul = 1
			}
			if div == 0 {
				div = 1
			}
			fmt.Printf("DIMENSION '%s' '%s' %s %d %d\n", d.ID, d.Name, d.Algo, mul, div)
		}
	}
}

func emitNetdataUpdate(plan planOutput, microseconds int64) {
	order := sortedChartIDs(plan.Updates)
	for _, chartID := range order {
		fmt.Printf("BEGIN \"%s\" %d\n", chartID, microseconds)
		dims := plan.Updates[chartID]
		dimIDs := make([]string, 0, len(dims))
		for dimID := range dims {
			dimIDs = append(dimIDs, dimID)
		}
		sort.Strings(dimIDs)
		for _, dimID := range dimIDs {
			fmt.Printf("SET '%s' = %d\n", dimID, dims[dimID])
		}
		fmt.Println("END")
	}
}

func sortedChartIDs(updates map[string]map[string]uint64) []string {
	order := make([]string, 0, len(updates))
	for chartID := range updates {
		order = append(order, chartID)
	}
	sort.Strings(order)
	return order
}

func sanitizeKey(v string) string {
	if v == "" {
		return ""
	}
	var b strings.Builder
	for _, r := range v {
		switch {
		case r >= '0' && r <= '9':
			b.WriteRune(r)
		case r >= 'a' && r <= 'z':
			b.WriteRune(r)
		case r >= 'A' && r <= 'Z':
			b.WriteRune(r)
		default:
			b.WriteByte('_')
		}
	}
	out := strings.Trim(b.String(), "_")
	for strings.Contains(out, "__") {
		out = strings.ReplaceAll(out, "__", "_")
	}
	return out
}

func setMetric(m map[string]uint64, k string, v uint64) {
	m[k] = v
}

func collectInterface(ifc, mode string) (ifaceReport, error) {
	roots, err := runTC(ifc, "root")
	if err != nil {
		return ifaceReport{}, err
	}
	if len(roots) == 0 {
		return ifaceReport{}, errors.New("no root qdisc found")
	}
	root := roots[0]

	report := ifaceReport{
		Interface:  ifc,
		Mode:       mode,
		RootKind:   root.Kind,
		RootHandle: root.Handle,
		Overview: overview{
			Bytes:   root.Bytes,
			Drops:   root.Drops,
			Backlog: root.Backlog,
		},
	}

	switch root.Kind {
	case "cake":
		report.Queues = []queueReport{queueFromQdisc(root, "root")}
		return report, nil
	case "cake_mq":
		all, err := runTC(ifc)
		if err != nil {
			return ifaceReport{}, err
		}
		children := make([]tcQdisc, 0)
		for _, q := range all {
			if q.Kind == "cake" && strings.HasPrefix(q.Parent, root.Handle) {
				children = append(children, q)
			}
		}
		if len(children) == 0 {
			return ifaceReport{}, errors.New("cake_mq root without child cake queues")
		}
		sort.Slice(children, func(i, j int) bool {
			return queueID(root.Handle, children[i].Parent) < queueID(root.Handle, children[j].Parent)
		})

		if mode == "cake_mq" {
			report.Queues = []queueReport{aggregateQueues(root, children)}
		} else {
			report.Queues = make([]queueReport, 0, len(children))
			for _, c := range children {
				report.Queues = append(report.Queues, queueFromQdisc(c, queueID(root.Handle, c.Parent)))
			}
		}
		return report, nil
	case "mq", "fq_codel":
		report.Queues = []queueReport{{
			QueueID: "root",
			Parent:  "",
			Overview: overview{
				Bytes:   root.Bytes,
				Drops:   root.Drops,
				Backlog: root.Backlog,
			},
		}}
		return report, nil
	default:
		return ifaceReport{}, fmt.Errorf("unsupported root qdisc kind %q", root.Kind)
	}
}

func queueFromQdisc(q tcQdisc, id string) queueReport {
	tins := make([]tinMetrics, 0, len(q.Tins))
	labels := tinLabels(q.Options.Diffserv, len(q.Tins))
	for i, t := range q.Tins {
		tins = append(tins, tinMetrics{
			Tin:               labels[i],
			ThresholdRate:     t.ThresholdRate,
			SentBytes:         t.SentBytes,
			BacklogBytes:      t.BacklogBytes,
			TargetUS:          t.TargetUS,
			PeakDelayUS:       t.PeakDelayUS,
			AvgDelayUS:        t.AvgDelayUS,
			BaseDelayUS:       t.BaseDelayUS,
			Drops:             t.Drops,
			ECNMark:           t.ECNMark,
			AckDrops:          t.AckDrops,
			SparseFlows:       t.SparseFlows,
			BulkFlows:         t.BulkFlows,
			UnresponsiveFlows: t.UnresponsiveFlows,
		})
	}
	return queueReport{
		QueueID: id,
		Parent:  q.Parent,
		Overview: overview{
			Bytes:   q.Bytes,
			Drops:   q.Drops,
			Backlog: q.Backlog,
		},
		Tins: tins,
	}
}

func aggregateQueues(root tcQdisc, children []tcQdisc) queueReport {
	numTins := len(children[0].Tins)
	labels := tinLabels(children[0].Options.Diffserv, numTins)
	agg := queueReport{
		QueueID: "all",
		Parent:  root.Handle,
		Overview: overview{
			Bytes:   root.Bytes,
			Drops:   root.Drops,
			Backlog: root.Backlog,
		},
		Tins: make([]tinMetrics, numTins),
	}
	for i := 0; i < numTins; i++ {
		agg.Tins[i].Tin = labels[i]
	}
	for _, c := range children {
		for i, t := range c.Tins {
			a := &agg.Tins[i]
			a.ThresholdRate += t.ThresholdRate
			a.SentBytes += t.SentBytes
			a.BacklogBytes += t.BacklogBytes
			a.TargetUS = max(a.TargetUS, t.TargetUS)
			a.PeakDelayUS = max(a.PeakDelayUS, t.PeakDelayUS)
			a.AvgDelayUS = max(a.AvgDelayUS, t.AvgDelayUS)
			a.BaseDelayUS = max(a.BaseDelayUS, t.BaseDelayUS)
			a.Drops += t.Drops
			a.ECNMark += t.ECNMark
			a.AckDrops += t.AckDrops
			a.SparseFlows += t.SparseFlows
			a.BulkFlows += t.BulkFlows
			a.UnresponsiveFlows += t.UnresponsiveFlows
		}
	}
	return agg
}

func queueID(rootHandle, parent string) string {
	id := strings.TrimPrefix(parent, rootHandle)
	if id == parent || id == "" {
		return "0"
	}
	var b strings.Builder
	for _, r := range id {
		if (r >= '0' && r <= '9') || (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') {
			b.WriteRune(r)
		}
	}
	out := b.String()
	if out == "" {
		return "0"
	}
	return out
}

func tinLabels(diffserv string, count int) []string {
	var base []string
	switch diffserv {
	case "besteffort":
		base = []string{"T0"}
	case "diffserv3":
		base = []string{"BK", "BE", "VI"}
	case "diffserv4":
		base = []string{"BK", "BE", "VI", "VO"}
	case "diffserv5":
		base = []string{"LE", "BK", "BE", "VI", "VO"}
	default:
		base = []string{"T0", "T1", "T2", "T3", "T4", "T5", "T6", "T7"}
	}
	labels := make([]string, count)
	for i := 0; i < count; i++ {
		if i < len(base) {
			labels[i] = base[i]
		} else {
			labels[i] = fmt.Sprintf("T%d", i)
		}
	}
	return labels
}

func runTC(ifc string, extra ...string) ([]tcQdisc, error) {
	args := append([]string{"-s", "-j", "qdisc", "show", "dev", ifc}, extra...)
	cmd := exec.Command("tc", args...)
	out, err := cmd.Output()
	if err != nil {
		if ee := new(exec.ExitError); errors.As(err, &ee) {
			return nil, fmt.Errorf("tc failed: %s", strings.TrimSpace(string(ee.Stderr)))
		}
		return nil, err
	}
	var qdiscs []tcQdisc
	if err := json.Unmarshal(out, &qdiscs); err != nil {
		return nil, err
	}
	return qdiscs, nil
}

func splitNonEmpty(v, sep string) []string {
	parts := strings.Split(v, sep)
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func max(a, b uint64) uint64 {
	if a > b {
		return a
	}
	return b
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "error:", err)
	os.Exit(1)
}
