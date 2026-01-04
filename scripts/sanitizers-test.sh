#!/bin/bash
#
# AddressSanitizer (ASan) and LeakSanitizer (LSan) test runner for sqlite-vec
# Detects buffer overflows, use-after-free, double-free, and memory leaks.
#
# Usage: ./scripts/sanitizers-test.sh
# Or:    make test-asan

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Only run on Linux (macOS has SIP issues with ASan)
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${YELLOW}AddressSanitizer tests currently only supported on Linux.${NC}"
    echo -e "${YELLOW}macOS requires additional setup due to SIP restrictions.${NC}"
    exit 0
fi

# Check for clang or gcc
CC="${CC:-}"
if [[ -z "$CC" ]]; then
    if command -v clang &>/dev/null; then
        CC=clang
    elif command -v gcc &>/dev/null; then
        CC=gcc
    else
        echo -e "${RED}Error: Neither clang nor gcc found. Install one to run ASan tests.${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}=== AddressSanitizer + LeakSanitizer Tests ===${NC}"
echo "Using compiler: $CC"

# Configuration
OUTPUT_FILE="$ROOT_DIR/asan-output.log"
MEMORY_TEST="$ROOT_DIR/dist/memory-test-asan"

# ASan/LSan options
export ASAN_OPTIONS="detect_leaks=1:halt_on_error=1:print_stats=1:check_initialization_order=1"
export LSAN_OPTIONS="print_suppressions=0"

# Clean previous output
rm -f "$OUTPUT_FILE"

# ASan compiler flags
ASAN_CFLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1"
ASAN_LDFLAGS="-fsanitize=address,undefined"

# Build the ASan-instrumented memory test
echo -e "\n${YELLOW}Building memory-test with AddressSanitizer...${NC}"

$CC $ASAN_CFLAGS \
    -fvisibility=hidden \
    -I"$ROOT_DIR/vendor/" -I"$ROOT_DIR/" \
    -DSQLITE_CORE \
    -DSQLITE_VEC_STATIC \
    -DSQLITE_THREADSAFE=0 \
    "$ROOT_DIR/tests/memory-test.c" \
    "$ROOT_DIR/sqlite-vec.c" \
    "$ROOT_DIR/vendor/sqlite3.c" \
    -o "$MEMORY_TEST" \
    $ASAN_LDFLAGS -ldl -lm

if [ ! -f "$MEMORY_TEST" ]; then
    echo -e "${RED}Error: ASan build failed. Binary not found at $MEMORY_TEST${NC}"
    exit 1
fi
echo -e "${GREEN}ASan build complete${NC}"

# Run the ASan-instrumented memory test
echo -e "\n${YELLOW}Running memory tests with AddressSanitizer...${NC}"

set +e
"$MEMORY_TEST" 2>&1 | tee "$OUTPUT_FILE"
TEST_EXIT=${PIPESTATUS[0]}
set -e

echo ""

# Analyze output for ASan/LSan errors
echo -e "${BLUE}=== Analyzing ASan/LSan output ===${NC}"

RESULT=0

# Check for ASan errors
if grep -q "ERROR: AddressSanitizer" "$OUTPUT_FILE"; then
    echo -e "${RED}FAIL: AddressSanitizer found errors:${NC}"
    grep -B 2 -A 20 "ERROR: AddressSanitizer" "$OUTPUT_FILE" | head -50 || true
    RESULT=1
fi

# Check for LSan errors
if grep -q "ERROR: LeakSanitizer" "$OUTPUT_FILE"; then
    echo -e "${RED}FAIL: LeakSanitizer found memory leaks:${NC}"
    grep -B 2 -A 30 "ERROR: LeakSanitizer" "$OUTPUT_FILE" | head -60 || true
    RESULT=1
fi

# Check for undefined behavior
if grep -q "runtime error:" "$OUTPUT_FILE"; then
    echo -e "${RED}FAIL: UndefinedBehaviorSanitizer found issues:${NC}"
    grep -B 2 -A 5 "runtime error:" "$OUTPUT_FILE" | head -30 || true
    RESULT=1
fi

# Check test exit code
if [[ "$TEST_EXIT" -ne 0 && "$RESULT" -eq 0 ]]; then
    echo -e "${RED}FAIL: Tests failed with exit code $TEST_EXIT${NC}"
    RESULT=1
fi

if [[ "$RESULT" -eq 0 ]]; then
    echo -e "\n${GREEN}PASS: No memory errors detected${NC}"
    rm -f "$OUTPUT_FILE"
else
    echo -e "\n${RED}Memory issues detected! See $OUTPUT_FILE for full details.${NC}"
fi

# Clean up ASan build artifacts
echo -e "\n${YELLOW}Cleaning up ASan build...${NC}"
rm -f "$MEMORY_TEST"
echo -e "${GREEN}Cleanup complete${NC}"

exit $RESULT
