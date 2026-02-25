#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$REPO_ROOT/tests/install-test.sh"
bash "$REPO_ROOT/tests/sqm-go-collector-bin-test.sh"
(
	cd "$REPO_ROOT/sqm-go-collector"
	go test ./...
)

echo "All tests passed."
