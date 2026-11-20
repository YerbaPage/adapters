#!/bin/bash
# Grading follows the original harness (src/evaluation/test_run.py, analyze_test_output):
#   fail if the eval script prints OMNIGRIL_TEST_PATCH_APPLY_FAILED=1;
#   otherwise pass iff the last OMNIGRIL_EXIT_CODE=<n> is 0 AND the script exits 0
#   (if no marker is printed, pass iff the script exits 0).
# Like the original harness (_run_single_patch_with_retry), a NON_ZERO_EXIT whose log matches a known
# transient signature is re-run up to 2 more times. The original re-runs in a fresh container; here the
# eval script is re-run in place, which is safe because it restores the test files before applying the
# hidden test patch.
# The agent's edits are already in /testbed; the eval script applies the hidden test patch itself.
set -u
mkdir -p /logs/verifier
LOG=/logs/verifier/eval_output.log
cp /tests/eval.sh /tmp/evaluate.sh
chmod a+r /tmp/evaluate.sh
FLAKY_PATTERNS='initialize timeout: Elapsed|timeout: Elapsed\(\(\)\)'
FLAKY_MAX_RETRIES=2

for attempt in $(seq 0 "$FLAKY_MAX_RETRIES"); do
  bash /tmp/evaluate.sh > "$LOG" 2>&1
  rc=$?
  marker_exit=$(grep -aoE 'OMNIGRIL_EXIT_CODE=[0-9]+[[:space:]]*$' "$LOG" | tail -n 1 | grep -oE '[0-9]+')
  if grep -aq 'OMNIGRIL_TEST_PATCH_APPLY_FAILED=1' "$LOG"; then
    reason=TEST_PATCH_APPLY_FAILED; reward=0
  elif [ -n "$marker_exit" ]; then
    if [ "$marker_exit" -eq 0 ] && [ "$rc" -eq 0 ]; then reason=SUCCESS; reward=1; else reason=NON_ZERO_EXIT; reward=0; fi
  elif [ "$rc" -ne 0 ]; then
    reason=NON_ZERO_EXIT; reward=0
  else
    reason=SUCCESS; reward=1
  fi
  if [ "$reason" = NON_ZERO_EXIT ] && [ "$attempt" -lt "$FLAKY_MAX_RETRIES" ] && grep -aqE "$FLAKY_PATTERNS" "$LOG"; then
    cp "$LOG" "/logs/verifier/eval_output.attempt$attempt.log"
    echo "PROMAX_FLAKY_RETRY attempt=$attempt (known transient failure signature)"
    continue
  fi
  break
done

tail -n 60 "$LOG"
echo "PROMAX_RESULT reason=$reason script_rc=$rc omnigril_exit=${marker_exit:-none} attempts=$((attempt + 1))"
echo "$reward" > /logs/verifier/reward.txt
[ "$reward" -eq 1 ]
