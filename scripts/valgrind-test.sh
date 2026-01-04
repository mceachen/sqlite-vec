#!/bin/bash
#
# Valgrind memory leak detection script for sqlite-vec
# Detects memory leaks, use-after-free, double-free, and other memory errors.
#
# Usage: ./scripts/valgrind-test.sh
# Or:    make test-valgrind

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Only run on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${YELLOW}Valgrind tests only run on Linux. Skipping.${NC}"
    exit 0
fi

# Check if valgrind is available
if ! command -v valgrind &>/dev/null; then
    echo -e "${YELLOW}Warning: valgrind not found. Install with: sudo apt-get install valgrind${NC}"
    exit 0
fi

MEMORY_TEST="$ROOT_DIR/dist/memory-test"
SUPP_FILE="$ROOT_DIR/.valgrind.supp"
LOG_FILE="$ROOT_DIR/valgrind.log"

echo -e "${BLUE}=== Valgrind Memory Leak Detection ===${NC}"

# Check if memory-test binary exists
if [ ! -f "$MEMORY_TEST" ]; then
    echo "Building memory-test binary..."
    make -C "$ROOT_DIR" dist/memory-test
fi

# Ensure suppressions file exists
if [ ! -f "$SUPP_FILE" ]; then
    echo -e "${RED}Error: Valgrind suppressions file not found at $SUPP_FILE${NC}"
    exit 1
fi

# Pre-flight check: run the test without valgrind first
echo "Running pre-flight check..."
if ! "$MEMORY_TEST" >/dev/null 2>&1; then
    echo -e "${RED}Error: Memory test binary failed. Running again to show error:${NC}"
    "$MEMORY_TEST"
    exit 1
fi
echo -e "${GREEN}Pre-flight check passed${NC}"

# Valgrind options
VALGRIND_OPTS=(
    --leak-check=full
    --show-leak-kinds=definite,indirect,possible
    --track-origins=yes
    --error-exitcode=1
    --suppressions="$SUPP_FILE"
    --gen-suppressions=all
)

echo -e "\n${YELLOW}Running valgrind memory analysis...${NC}"
echo "This may take a few minutes..."

# Run valgrind and capture output
set +e
valgrind "${VALGRIND_OPTS[@]}" "$MEMORY_TEST" 2>&1 | tee "$LOG_FILE"
VALGRIND_EXIT=${PIPESTATUS[0]}
set -e

echo ""

# Analyze results
DEFINITELY_LOST=$(grep -oP "definitely lost: \K[0-9,]+" "$LOG_FILE" 2>/dev/null | tr -d ',' || echo "0")
INDIRECTLY_LOST=$(grep -oP "indirectly lost: \K[0-9,]+" "$LOG_FILE" 2>/dev/null | tr -d ',' || echo "0")
POSSIBLY_LOST=$(grep -oP "possibly lost: \K[0-9,]+" "$LOG_FILE" 2>/dev/null | tr -d ',' || echo "0")
STILL_REACHABLE=$(grep -oP "still reachable: \K[0-9,]+" "$LOG_FILE" 2>/dev/null | tr -d ',' || echo "0")
ERROR_COUNT=$(grep -oP "ERROR SUMMARY: \K[0-9,]+" "$LOG_FILE" 2>/dev/null | tr -d ',' || echo "0")

echo -e "${BLUE}=== Valgrind Summary ===${NC}"
echo "  Definitely lost: $DEFINITELY_LOST bytes"
echo "  Indirectly lost: $INDIRECTLY_LOST bytes"
echo "  Possibly lost:   $POSSIBLY_LOST bytes"
echo "  Still reachable: $STILL_REACHABLE bytes"
echo "  Errors:          $ERROR_COUNT"

# Determine pass/fail
RESULT=0

if [[ "$DEFINITELY_LOST" != "0" ]]; then
    echo -e "\n${RED}FAIL: Definite memory leaks detected!${NC}"
    grep -A 20 "definitely lost" "$LOG_FILE" | head -30 || true
    RESULT=1
fi

if [[ "$INDIRECTLY_LOST" != "0" ]]; then
    echo -e "\n${RED}FAIL: Indirect memory leaks detected!${NC}"
    grep -A 20 "indirectly lost" "$LOG_FILE" | head -30 || true
    RESULT=1
fi

if [[ "$ERROR_COUNT" != "0" ]]; then
    echo -e "\n${RED}FAIL: Memory errors detected!${NC}"
    grep -B 5 -A 10 "Invalid" "$LOG_FILE" | head -50 || true
    RESULT=1
fi

if [[ "$RESULT" -eq 0 ]]; then
    echo -e "\n${GREEN}PASS: No memory leaks or errors detected in sqlite-vec code${NC}"
    rm -f "$LOG_FILE"
else
    echo -e "\n${RED}Memory issues detected! See $LOG_FILE for full details.${NC}"
    echo -e "${YELLOW}To generate suppressions for false positives, check the log file.${NC}"
fi

exit $RESULT
