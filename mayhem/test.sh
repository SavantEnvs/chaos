#!/usr/bin/env bash
#
# mayhem/test.sh — RUN upstream's own functional test suites (built by mayhem/build.sh).
#
# What runs (upstream's own tests, upstream's own golden files):
#   1. interpreter file-mode golden tests — every tests/<t>.kaos executed as
#      `chaos tests/<t>.kaos`, stdout compared byte-for-byte against the committed
#      tests/<t>.out (same check as loop 1 of tests/interpreter.sh / `make test-no-shell`).
#   2. AST golden tests — upstream's tests/ast.sh verbatim (`make test-ast`): AST dump of
#      every tests/<t>.kaos compared against the committed tests/<t>.json.
# Both assert exact golden OUTPUT, so a neutered/no-op binary fails them.
#
# Known upstream-HEAD failures (XFAIL, not our port): at 61a4337 (merge #107 "feat/jit")
# the 6 function/module tests below fail upstream's own recipe too — reproduced with
# gcc -O3 + bison/flex on a clean ubuntu:20.04 exactly per upstream's Makefile (module1/
# module2 SIGSEGV; everything/function/function_redefinition/module report
# "Undefined function" on module imports). They are counted as "other" in CTRF and do
# not gate; every remaining test must pass.
#
# Skipped upstream suites (documented, not silently dropped):
#   - interpreter.sh piped-REPL loop (loop 2): EVERY piped-REPL invocation of upstream
#     HEAD segfaults in compile_interactive->run_cpu (jump to NULL JIT code) — also
#     reproduced with upstream's own recipe on ubuntu:20.04. Upstream-HEAD breakage.
#   - tests/shell/*: needs an interactive TTY (upstream itself skips via --no-shell).
#   - compiler.sh / cli_args.sh / extensions / rosetta: compiler mode needs
#     `make install` into /usr/local as root + gcc-compiling generated C at runtime.
#   - memcheck: needs valgrind.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

XFAIL_UPSTREAM="everything function function_redefinition module module1 module2"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

ORACLE="$SRC/build-test/bin/chaos"
if [ ! -x "$ORACLE" ]; then
  echo "FATAL: test oracle $ORACLE missing — mayhem/build.sh did not produce it" >&2
  emit_ctrf "chaos-tests" 0 1
  exit 1
fi
export PATH="$SRC/build-test/bin:$PATH"

passed=0 failed=0 xfailed=0

# --- 1. interpreter file-mode golden tests (loop 1 of tests/interpreter.sh) ---
for f in tests/*.kaos; do
  t="$(basename "$f" .kaos)"
  [ -f "tests/$t.out" ] || continue
  got="$(chaos "tests/$t.kaos" 2>&1)"
  exp="$(cat "tests/$t.out")"
  if [ "$got" = "$exp" ]; then
    echo "(interpreter) $t: OK"; passed=$((passed+1))
  elif printf ' %s ' $XFAIL_UPSTREAM | grep -q " $t "; then
    echo "(interpreter) $t: XFAIL (known upstream-HEAD failure)"; xfailed=$((xfailed+1))
  else
    echo "(interpreter) $t: FAIL"; failed=$((failed+1))
    diff <(printf '%s\n' "$exp") <(printf '%s\n' "$got") | head -20
  fi
done

# --- 2. AST golden tests (upstream tests/ast.sh verbatim) ---
AST_LOG=$(mktemp)
bash tests/ast.sh >"$AST_LOG" 2>&1
ast_ok=$(grep -cx 'OK' "$AST_LOG" || true)
ast_fail=$(grep -cx 'Fail' "$AST_LOG" || true)
echo "(ast) $ast_ok OK, $ast_fail Fail"
[ "$ast_fail" -gt 0 ] && { echo "---- ast.sh output (tail) ----"; tail -40 "$AST_LOG"; }
passed=$((passed+ast_ok)); failed=$((failed+ast_fail))

# A neutered suite (0 executed tests) must fail loudly.
[ "$passed" -gt 0 ] || { emit_ctrf "chaos-tests" 0 1; exit 1; }

emit_ctrf "chaos-tests" "$passed" "$failed" 0 0 "$xfailed"
