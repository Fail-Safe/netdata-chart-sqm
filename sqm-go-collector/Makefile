SHELL := /bin/bash

APP := sqm-go-collector
CMD := ./cmd/sqm-go-collector
BIN_DIR := bin
LDFLAGS := -s -w
BUILD_FLAGS := -trimpath -ldflags "$(LDFLAGS)"

ARTIFACTS := \
	$(BIN_DIR)/$(APP)-linux-amd64 \
	$(BIN_DIR)/$(APP)-linux-arm64 \
	$(BIN_DIR)/$(APP)-linux-mipsle-softfloat

.PHONY: all clean size size-upx report report-upx

RELEASE_DIR := release
CHECKSUM_FILE := SHA256SUMS
NOTES_FILE := RELEASE_NOTES.txt
BENCH_RUNS ?= 20
BENCH_INNER ?= 50
BENCH_IFC ?= eth0,ifb4eth0
BENCH_MODE ?= overlay
BENCH_FORMAT ?= metrics

.PHONY: all clean size size-upx report report-upx release verify-release

all: $(ARTIFACTS)

$(BIN_DIR):
	@mkdir -p $(BIN_DIR)

$(BIN_DIR)/$(APP)-linux-amd64: | $(BIN_DIR)
	@CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(BUILD_FLAGS) -o $@ $(CMD)

$(BIN_DIR)/$(APP)-linux-arm64: | $(BIN_DIR)
	@CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(BUILD_FLAGS) -o $@ $(CMD)

$(BIN_DIR)/$(APP)-linux-mipsle-softfloat: | $(BIN_DIR)
	@CGO_ENABLED=0 GOOS=linux GOARCH=mipsle GOMIPS=softfloat go build $(BUILD_FLAGS) -o $@ $(CMD)

size: all report

report:
	@printf "\n%-44s %14s %10s\n" "Artifact" "Bytes" "MiB"
	@printf "%-44s %14s %10s\n" "--------------------------------------------" "--------------" "----------"
	@for f in $(ARTIFACTS); do \
		bytes=$$(wc -c < "$$f" | tr -d ' '); \
		mib=$$(awk "BEGIN {printf \"%.2f\", $$bytes/1048576}"); \
		printf "%-44s %14s %10s\n" "$$f" "$$bytes" "$$mib"; \
	done

size-upx: all
	@if ! command -v upx >/dev/null 2>&1; then \
		echo "upx not found in PATH; skipping compression step."; \
		echo "Install UPX and rerun 'make size-upx' for compressed size comparison."; \
	else \
		for f in $(ARTIFACTS); do \
			cp "$$f" "$$f.upx"; \
			upx --best --lzma "$$f.upx" >/dev/null; \
		done; \
		$(MAKE) report-upx; \
	fi

report-upx:
	@printf "\n%-36s %14s %14s %10s\n" "Artifact" "Orig Bytes" "UPX Bytes" "Saved"
	@printf "%-36s %14s %14s %10s\n" "------------------------------------" "--------------" "--------------" "----------"
	@for f in $(ARTIFACTS); do \
		orig=$$(wc -c < "$$f" | tr -d ' '); \
		comp=$$(wc -c < "$$f.upx" | tr -d ' '); \
		saved=$$(awk "BEGIN {printf \"%.1f%%\", (1-($$comp/$$orig))*100}"); \
		printf "%-36s %14s %14s %10s\n" "$${f##*/}" "$$orig" "$$comp" "$$saved"; \
	done

clean:
	@rm -rf $(BIN_DIR)

release: all
	@rm -rf $(RELEASE_DIR)
	@mkdir -p $(RELEASE_DIR)
	@for f in $(ARTIFACTS); do \
		cp "$$f" "$(RELEASE_DIR)/$${f##*/}"; \
	done
	@if command -v upx >/dev/null 2>&1; then \
		echo "UPX found: creating compressed release artifacts"; \
		for f in $(ARTIFACTS); do \
			cp "$$f" "$(RELEASE_DIR)/$${f##*/}.upx"; \
			upx --best --lzma "$(RELEASE_DIR)/$${f##*/}.upx" >/dev/null; \
		done; \
	else \
		echo "UPX not found: skipping compressed release artifacts"; \
	fi
	@{ \
		echo "sqm-go-collector release notes"; \
		echo "==============================="; \
		echo; \
		echo "Artifacts in this folder include:"; \
		echo "- standard stripped binaries (recommended runtime default)"; \
		echo "- optional .upx binaries when UPX is available"; \
		echo "- SHA256SUMS for integrity verification"; \
		echo; \
		echo "UPX guidance:"; \
		echo "- Use .upx artifacts for transfer/storage constrained environments."; \
		echo "- Prefer standard binaries for runtime on low-power devices."; \
		echo "- UPX can reduce size significantly but may add startup overhead."; \
		echo; \
		echo "Recommendation:"; \
		echo "- Production collector runtime: standard stripped binary."; \
		echo "- Distribution convenience: optional .upx binary."; \
		echo; \
		echo "Measured example (EQ14):"; \
		echo "- Command: DEBUG_TIMER=1 ./scripts/compare-startup.sh --std ./sqm-go-collector-linux-amd64 --upx ./sqm-go-collector-linux-amd64.upx --runs 20 --inner 50 -- -ifc eth0,ifb4eth0 -mode overlay -format metrics"; \
		echo "- Result: std ~7.69 ms, upx ~80.39 ms, delta ~+72.70 ms (+945.38%)."; \
		echo; \
		echo "Validate checksums with:"; \
		echo "  make verify-release"; \
		echo; \
		echo "Benchmark startup impact with:"; \
		echo "  ./scripts/compare-startup.sh --std <std-bin> --upx <upx-bin> --runs 20 --inner 50 -- <args>"; \
	} > $(RELEASE_DIR)/$(NOTES_FILE)
	@if [[ "$${AUTO_BENCH:-1}" == "1" ]]; then \
		bench_std=""; \
		for f in "$(RELEASE_DIR)/$(APP)-linux-amd64" "$(RELEASE_DIR)/$(APP)-linux-arm64" "$(RELEASE_DIR)/$(APP)-linux-mipsle-softfloat"; do \
			if [[ -x "$$f" ]] && "$$f" -h >/dev/null 2>&1; then \
				bench_std="$$f"; \
				break; \
			fi; \
		done; \
		if [[ -n "$$bench_std" && -x "$$bench_std.upx" ]]; then \
			if ./scripts/compare-startup.sh --std "$$bench_std" --upx "$$bench_std.upx" --runs "$(BENCH_RUNS)" --inner "$(BENCH_INNER)" -- -ifc "$(BENCH_IFC)" -mode "$(BENCH_MODE)" -format "$(BENCH_FORMAT)" > "$(RELEASE_DIR)/BENCHMARK.txt" 2>&1; then \
				{ \
					echo; \
					echo "Auto benchmark:"; \
					echo "- Binary: $${bench_std##*/} and $${bench_std##*/}.upx"; \
					echo "- Args: -ifc $(BENCH_IFC) -mode $(BENCH_MODE) -format $(BENCH_FORMAT)"; \
					echo "- Runs: $(BENCH_RUNS), inner: $(BENCH_INNER)"; \
					sed 's/^/  /' "$(RELEASE_DIR)/BENCHMARK.txt"; \
				} >> "$(RELEASE_DIR)/$(NOTES_FILE)"; \
			else \
				{ \
					echo; \
					echo "Auto benchmark:"; \
					echo "- Failed for $${bench_std##*/}; see $(RELEASE_DIR)/BENCHMARK.txt"; \
				} >> "$(RELEASE_DIR)/$(NOTES_FILE)"; \
			fi; \
		else \
			{ \
				echo; \
				echo "Auto benchmark:"; \
				echo "- Skipped: no runnable release binary for this host architecture."; \
				echo "- Tip: run on target host or set AUTO_BENCH=0 to disable this check."; \
			} >> "$(RELEASE_DIR)/$(NOTES_FILE)"; \
		fi; \
	fi
	@cd $(RELEASE_DIR) && shasum -a 256 * > $(CHECKSUM_FILE)
	@echo "Release artifacts written to $(RELEASE_DIR)/"
	@echo "Checksums: $(RELEASE_DIR)/$(CHECKSUM_FILE)"
	@echo "Notes: $(RELEASE_DIR)/$(NOTES_FILE)"

verify-release:
	@test -f "$(RELEASE_DIR)/$(CHECKSUM_FILE)" || { echo "Missing $(RELEASE_DIR)/$(CHECKSUM_FILE). Run 'make release' first."; exit 1; }
	@cd $(RELEASE_DIR) && shasum -a 256 -c $(CHECKSUM_FILE)
