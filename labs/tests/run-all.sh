#!/bin/bash
###############################################################################
# Lab Test Suite Runner
#
# Usage:
#   bash run-all.sh              # Run all tests
#   bash run-all.sh platform     # Platform prerequisites only
#   bash run-all.sh 1 3 5        # Run specific labs
#   bash run-all.sh 1-6          # Run a range
###############################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
FAILED_LABS=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

run_test() {
  local name="$1" script="$2"
  echo ""
  echo -e "${BOLD}════════════════════════════════════════${NC}"
  bash "$script"
  local exit_code=$?

  # Parse pass/fail/skip from the summary output
  local result
  result=$(bash "$script" 2>&1 | tail -6)
  # Re-run is wasteful; instead capture output once
  echo ""

  if [ $exit_code -ne 0 ]; then
    FAILED_LABS="$FAILED_LABS $name"
  fi
}

# Better approach: capture output and parse
run_test_capture() {
  local name="$1" script="$2"
  echo ""
  echo -e "${BOLD}════════════════════════════════════════${NC}"

  local output
  output=$(bash "$script" 2>&1)
  local exit_code=$?
  echo "$output"

  # Extract counts from summary
  local p f s
  p=$(echo "$output" | grep "Passed:" | grep -o '[0-9]*' | head -1)
  f=$(echo "$output" | grep "Failed:" | grep -o '[0-9]*' | head -1)
  s=$(echo "$output" | grep "Skipped:" | grep -o '[0-9]*' | head -1)

  TOTAL_PASS=$((TOTAL_PASS + ${p:-0}))
  TOTAL_FAIL=$((TOTAL_FAIL + ${f:-0}))
  TOTAL_SKIP=$((TOTAL_SKIP + ${s:-0}))

  if [ "${f:-0}" -gt 0 ]; then
    FAILED_LABS="$FAILED_LABS $name"
  fi
}

# Parse arguments
LABS_TO_RUN=()
if [ $# -eq 0 ]; then
  LABS_TO_RUN=("platform" $(seq 1 13))
elif [ "$1" = "platform" ]; then
  LABS_TO_RUN=("platform")
else
  for arg in "$@"; do
    if [[ "$arg" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      for i in $(seq "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"); do
        LABS_TO_RUN+=("$i")
      done
    else
      LABS_TO_RUN+=("$arg")
    fi
  done
fi

echo -e "${BOLD}Lab Test Suite${NC}"
echo "Running: ${LABS_TO_RUN[*]}"
echo "Started: $(date)"

# Save and restore context
ORIG_NS=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null)

for lab in "${LABS_TO_RUN[@]}"; do
  if [ "$lab" = "platform" ]; then
    run_test_capture "platform" "$SCRIPT_DIR/test-platform.sh"
  else
    padded=$(printf "%02d" "$lab")
    script="$SCRIPT_DIR/test-lab-${padded}.sh"
    if [ -f "$script" ]; then
      run_test_capture "lab-${padded}" "$script"
    else
      echo -e "${YELLOW}Skipping lab $padded — test not found${NC}"
    fi
  fi
done

# Restore namespace context
kubectl config set-context --current --namespace="${ORIG_NS:-default}" &>/dev/null

# Final summary
TOTAL=$((TOTAL_PASS + TOTAL_FAIL + TOTAL_SKIP))
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}           FINAL RESULTS                  ${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed:${NC}  $TOTAL_PASS"
echo -e "  ${RED}Failed:${NC}  $TOTAL_FAIL"
echo -e "  ${YELLOW}Skipped:${NC} $TOTAL_SKIP"
echo "  Total:   $TOTAL"
echo ""

if [ -n "$FAILED_LABS" ]; then
  echo -e "  ${RED}Failed:${NC}$FAILED_LABS"
fi

echo ""
echo "Finished: $(date)"

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
