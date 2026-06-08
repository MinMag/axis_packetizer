#!/bin/bash

# --- Configuration ---
NUM_RUNS=100                               # Total number of randomized iterations
TEST_NAME="test_heavy_backpressure"         # The specific test case to fuzz
LOG_DIR="regression_results"                # Directory to house the outputs

mkdir -p $LOG_DIR
echo "=========================================================="
echo " Starting Regression: $NUM_RUNS runs of $TEST_NAME"
echo "=========================================================="

FAILED_COUNT=0

for i in $(seq 1 $NUM_RUNS); do
    # 1. Generate a completely unique random seed for this iteration
    # Python/Cocotb accepts any standard integer seed
    SEED=$((RANDOM * RANDOM)) 
    LOG_FILE="$LOG_DIR/run_${i}_seed_${SEED}.log"
    
    echo -n "Running iteration $i/$NUM_RUNS (Seed: $SEED)... "
    
    # 2. Execute bare-metal simulation (CRITICAL: Do NOT run 'make waves' here)
    # We pass the standard 'sim' target to maximize execution speed.
    make RANDOM_SEED=$SEED > $LOG_FILE 2>&1
    
    # 3. Check the exit status of the simulation compile/run
    if [ $? -eq 0 ]; then
        echo "PASSED"
        # Optional: Delete passed logs to save disk space
        rm $LOG_FILE
    else
        echo "FAILED! Check log: $LOG_FILE"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

echo "=========================================================="
echo " Regression Finished!"
echo " Total Failures: $FAILED_COUNT / $NUM_RUNS"
echo "=========================================================="

if [ $FAILED_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi