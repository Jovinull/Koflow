#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
require_tools
cd "$ROOT_DIR"
test_dir="$(mktemp -d)"
child_pids=()
cleanup() {
    for pid in "${child_pids[@]}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    rm -rf -- "$test_dir"
}
trap cleanup EXIT
mkdir -p "$test_dir/source"
cp -R koflow "$test_dir/source/"
cp tests/*.kf "$test_dir/source/"
compile "$test_dir/source" "$test_dir/classes"
test -f "$test_dir/classes/Default/Main.class"
TEST_DB="$test_dir/jobs.db" timeout 60 "$JAVA" -cp "$test_dir/classes:$SQLITE_JDBC" Default.Main

wait_marker() {
    local pid="$1" log="$2" marker="$3"
    local deadline=$((SECONDS + 20))
    until rg -q -- "$marker" "$log"; do
        if ! kill -0 "$pid" 2>/dev/null || ((SECONDS >= deadline)); then
            head -c 12000 "$log" >&2
            echo 'Processo não sinalizou prontidão.' >&2
            exit 1
        fi
        sleep 0.05
    done
}

cp_runtime="$test_dir/classes:$SQLITE_JDBC"
job_id="$(TEST_DB="$test_dir/crash.db" KOF_TEST_ACTION=seed run_class "$test_dir/classes" Default.Main)"
TEST_DB="$test_dir/crash.db" KOF_TEST_ACTION=hold "$JAVA" -cp "$cp_runtime" Default.Main > "$test_dir/hold.log" 2>&1 &
child_pids+=("$!")
wait_marker "${child_pids[0]}" "$test_dir/hold.log" '^CLAIMED '
kill -KILL "${child_pids[0]}"
set +e
wait "${child_pids[0]}" 2>/dev/null
kill_status=$?
set -e
child_pids=()
test "$kill_status" -eq 137
recovery="$(TEST_DB="$test_dir/crash.db" KOF_TEST_ACTION=recover timeout 20 "$JAVA" -cp "$cp_runtime" Default.Main)"
test "$recovery" = "RECOVERED $job_id"
echo 'PASS SIGKILL depois do claim e recuperação em novo processo'

TEST_DB="$test_dir/rollback.db" KOF_TEST_ACTION=uncommitted "$JAVA" -cp "$cp_runtime" Default.Main > "$test_dir/uncommitted.log" 2>&1 &
child_pids+=("$!")
wait_marker "${child_pids[0]}" "$test_dir/uncommitted.log" '^UNCOMMITTED$'
kill -KILL "${child_pids[0]}"
set +e
wait "${child_pids[0]}" 2>/dev/null
kill_status=$?
set -e
child_pids=()
test "$kill_status" -eq 137
TEST_DB="$test_dir/rollback.db" KOF_TEST_ACTION=verify-rollback run_class "$test_dir/classes" Default.Main

TEST_DB="$test_dir/race.db" KOF_TEST_ACTION=seed run_class "$test_dir/classes" Default.Main > "$test_dir/seed.log"
for index in {1..8}; do
    TEST_DB="$test_dir/race.db" KOF_TEST_ACTION=race timeout 20 "$JAVA" -cp "$cp_runtime" Default.Main > "$test_dir/race-$index.log" 2>&1 &
    child_pids+=("$!")
done
for pid in "${child_pids[@]}"; do
    wait "$pid"
done
child_pids=()
test "$(rg -l '^WON$' "$test_dir"/race-*.log | wc -l)" -eq 1
test "$(rg -l '^EMPTY$' "$test_dir"/race-*.log | wc -l)" -eq 7
TEST_DB="$test_dir/race.db" KOF_TEST_ACTION=verify-race run_class "$test_dir/classes" Default.Main
echo 'PASS uma concessão vigente entre oito processos concorrentes'
