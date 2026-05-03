#!/usr/bin/env bash
# 2026-05-03 三阶段 batch 测试 runner
# 每个测试独立 matlab -batch（隔离 clear functions / clear all 串扰）
# 解析输出 PASS/FAIL，输出汇总表

set -u

MATLAB="/c/Program Files/MATLAB/R2025b/bin/matlab"
ROOT=D:/Claude/TechReq/UWAcomm-claude
ST=$ROOT/modules/14_Streaming/src/Matlab/tests
BT=$ROOT/modules/13_SourceCode/src/Matlab/tests/bench_common
LOG=$ROOT/scripts/run_phase123_tests.log
SUMMARY=$ROOT/scripts/run_phase123_tests_summary.txt

rm -f "$LOG" "$SUMMARY"
echo "===========================================================" | tee "$SUMMARY"
echo " UWAcomm-claude 2026-05-03 三阶段 batch 测试汇总" | tee -a "$SUMMARY"
echo "===========================================================" | tee -a "$SUMMARY"
echo "Date: $(date)" | tee -a "$SUMMARY"
echo "HEAD: $(cd $ROOT && git rev-parse --short HEAD)" | tee -a "$SUMMARY"
echo "" | tee -a "$SUMMARY"

# tests: label | dir | script
declare -a TESTS=(
  "P1_alpha_gate|$ST|test_p4_alpha_gate.m"
  "P1_ui_alignment_smoke|$ST|test_p4_ui_alignment_smoke.m"
  "P1_ui_runner_equivalence|$ST|test_p4_ui_runner_equivalence.m"
  "P1_ui_jakes_alpha_gate_e2e|$ST|test_p4_ui_jakes_alpha_gate_e2e.m"
  "P2_bench_common|$BT|test_bench_common.m"
  "P3_p5_three_process_smoke|$ST|test_p5_three_process_smoke.m"
  "P3_p6_amc_decision|$ST|test_p6_amc_decision.m"
  "P3_p6_amc_demo_ui_smoke|$ST|test_p6_amc_demo_ui_smoke.m"
  "P3_p5_extended_soak|$ST|test_p5_extended_soak.m"
)

printf "%-32s | %-7s | %-9s | %s\n" "Test" "Status" "Time(s)" "Detail" | tee -a "$SUMMARY"
printf '%s\n' "$(printf '%.0s-' {1..100})" | tee -a "$SUMMARY"

total_ok=0
total_fail=0

for t in "${TESTS[@]}"; do
  IFS='|' read -r label dir script <<< "$t"
  echo "" >> "$LOG"
  echo "============ $label ============" >> "$LOG"

  t0=$(date +%s.%N)
  out=$("$MATLAB" -batch "cd('$dir'); run('$script')" 2>&1)
  rc=$?
  t1=$(date +%s.%N)
  elapsed=$(awk -v a=$t0 -v b=$t1 'BEGIN{printf "%.2f", b-a}')

  echo "$out" >> "$LOG"

  # 解析 PASS/FAIL
  pass_count=$(echo "$out" | grep -c "^\[PASS\]")
  fail_count=$(echo "$out" | grep -c "^\[FAIL\]")
  result_line=$(echo "$out" | grep -E "^Result: [0-9]+/[0-9]+" | tail -1)

  if [ $rc -eq 0 ] && [ -n "$result_line" ]; then
    status="OK"
    detail="$result_line"
    total_ok=$((total_ok + 1))
  elif [ $rc -eq 0 ]; then
    # script 跑完无 throw 但无 Result 行（如 RCA 测试）→ 看 PASS 数
    status="OK"
    detail="passes=$pass_count fails=$fail_count"
    total_ok=$((total_ok + 1))
  else
    status="EXC"
    last_err=$(echo "$out" | grep -E "ERROR:|^错误|^错误使用" | head -1 | tr -d '\r')
    detail="passes=$pass_count fails=$fail_count rc=$rc ${last_err:0:40}"
    total_fail=$((total_fail + 1))
  fi

  printf "%-32s | %-7s | %9.2f | %s\n" "$label" "$status" "$elapsed" "$detail" | tee -a "$SUMMARY"
done

printf '%s\n' "$(printf '%.0s-' {1..100})" | tee -a "$SUMMARY"
echo "总计: $total_ok OK / $total_fail FAIL / ${#TESTS[@]} 测试" | tee -a "$SUMMARY"
echo "" | tee -a "$SUMMARY"
echo "完整输出: $LOG" | tee -a "$SUMMARY"
