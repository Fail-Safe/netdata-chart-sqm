package main

import (
	"bytes"
	"io"
	"os"
	"strings"
	"testing"
)

func captureStdout(t *testing.T, fn func()) string {
	t.Helper()

	old := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	os.Stdout = w
	defer func() { os.Stdout = old }()

	fn()
	_ = w.Close()

	var buf bytes.Buffer
	_, _ = io.Copy(&buf, r)
	_ = r.Close()
	return buf.String()
}

func TestBuildPlanOverlayDimensions(t *testing.T) {
	in := result{
		Reports: []ifaceReport{
			{
				Interface: "eth0",
				Mode:      "overlay",
				Overview:  overview{Bytes: 1000, Drops: 1, Backlog: 0},
				Queues: []queueReport{
					{
						QueueID: "1",
						Tins: []tinMetrics{
							{
								Tin:           "BE",
								ThresholdRate: 125000000,
								SentBytes:     200000,
							},
						},
					},
				},
			},
		},
	}

	plan := buildPlan(in)
	var foundChart *chartDef
	for i := range plan.Charts {
		if plan.Charts[i].ID == "SQM.eth0_BE_traffic" {
			foundChart = &plan.Charts[i]
			break
		}
	}
	if foundChart == nil {
		t.Fatalf("missing chart SQM.eth0_BE_traffic")
	}

	var q1Bytes, q1Thres *dimensionDef
	for i := range foundChart.Dims {
		switch foundChart.Dims[i].ID {
		case "q1_bytes":
			q1Bytes = &foundChart.Dims[i]
		case "q1_thres":
			q1Thres = &foundChart.Dims[i]
		}
	}
	if q1Bytes == nil || q1Thres == nil {
		t.Fatalf("missing expected overlay dimensions in traffic chart")
	}
	if q1Bytes.Algo != "incremental" || q1Bytes.Mul != 1 || q1Bytes.Div != 125 {
		t.Fatalf("unexpected q1_bytes dim config: %+v", *q1Bytes)
	}
	if q1Thres.Algo != "absolute" || q1Thres.Mul != 1 || q1Thres.Div != 125 {
		t.Fatalf("unexpected q1_thres dim config: %+v", *q1Thres)
	}
}

func TestEmitNetdataCreateAndUpdate(t *testing.T) {
	plan := planOutput{
		Charts: []chartDef{
			{
				ID:      "SQM.eth0_overview",
				Title:   "SQM qdisc eth0 Overview",
				Units:   "mixed",
				Family:  "eth0 Qdisc",
				Context: "overview",
				Dims: []dimensionDef{
					{ID: "bytes", Name: "Bytes", Algo: "incremental", Mul: 1, Div: 1},
				},
			},
		},
		Updates: map[string]map[string]uint64{
			"SQM.eth0_overview": {"bytes": 1234},
		},
	}

	createOut := captureStdout(t, func() {
		emitNetdataCreate(plan, 90000, 1)
	})
	if !strings.Contains(createOut, `CHART "SQM.eth0_overview"`) {
		t.Fatalf("missing CHART line in create output: %s", createOut)
	}
	if !strings.Contains(createOut, `DIMENSION 'bytes' 'Bytes' incremental 1 1`) {
		t.Fatalf("missing DIMENSION line in create output: %s", createOut)
	}

	updateOut := captureStdout(t, func() {
		emitNetdataUpdate(plan, 1000000)
	})
	if !strings.Contains(updateOut, `BEGIN "SQM.eth0_overview" 1000000`) {
		t.Fatalf("missing BEGIN line in update output: %s", updateOut)
	}
	if !strings.Contains(updateOut, `SET 'bytes' = 1234`) {
		t.Fatalf("missing SET line in update output: %s", updateOut)
	}
	if !strings.Contains(updateOut, "END") {
		t.Fatalf("missing END line in update output: %s", updateOut)
	}
}
