#!/usr/bin/env bash
# Issue #6: disposable, branch-local runtime test verification; no GitHub writes.
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1/runtime/tests" ]]; then
  echo 'usage: run-runtime-branch-tests.sh <checked-out-repository-root>' >&2
  exit 64
fi
root="$(cd "$1" && pwd -P)"
command -v node >/dev/null || { echo 'BLOCKED: node missing' >&2; exit 69; }
command -v npm >/dev/null || { echo 'BLOCKED: npm missing' >&2; exit 69; }
command -v python3 >/dev/null || { echo 'BLOCKED: python3 missing' >&2; exit 69; }
node -v

# Caller supplies a disposable directory, never a live app installation.
if [[ -z "${RUNNER_TEMP:-}" || ! -d "$RUNNER_TEMP" ]]; then
  echo 'BLOCKED: set RUNNER_TEMP to an existing disposable directory' >&2
  exit 69
fi
prefix="$RUNNER_TEMP/dsh"
pnpm_prefix="$RUNNER_TEMP/pnpm"
if [[ -e "$prefix" || -e "$pnpm_prefix" ]]; then
  echo 'BLOCKED: target prefix already exists; refuse to overwrite it' >&2
  exit 73
fi

version="$(sed -nE 's/^DSH_VERSION="\$\{DSH_VERSION:-(.+)\}"$/\1/p' "$root/runtime/build-runtime.sh")"
pnpm_version="$(sed -nE 's/^PNPM_VERSION="\$\{PNPM_VERSION:-(.+)\}"$/\1/p' "$root/runtime/build-runtime.sh")"
[[ -n "$version" && -n "$pnpm_version" ]] || { echo 'BLOCKED: unable to resolve pinned versions' >&2; exit 65; }
[[ -f "$root/runtime/locks/dsh-$version/package-lock.json" && -f "$root/runtime/locks/pnpm-$pnpm_version/package-lock.json" ]] || { echo 'BLOCKED: pinned lockfiles absent' >&2; exit 65; }

mkdir "$prefix" "$pnpm_prefix"
cp "$root/runtime/locks/dsh-$version/"{package.json,package-lock.json} "$prefix/"
npm ci --prefix "$prefix" --ignore-scripts --no-audit --no-fund
cp "$prefix/node_modules/@deepseek-ai/dsh-fs-local/lib/index.js" "$prefix/fs-local-original.js"
python3 -I "$root/runtime/lib/rtbuild.py" patch-dsh --prefix "$prefix" --dsh-version "$version" --target android
cp "$root/runtime/locks/pnpm-$pnpm_version/"{package.json,package-lock.json} "$pnpm_prefix/"
npm ci --prefix "$pnpm_prefix" --ignore-scripts --no-audit --no-fund

export DSH_PREFIX="$prefix" DSH_TEST_PREFIX="$prefix"
export PNPM_BIN="$pnpm_prefix/node_modules/pnpm/bin/pnpm.mjs"
export DSH_INSTALL="$prefix/node_modules/@deepseek-ai/dsh"
export DSH_TOOLS_DIR="$prefix/node_modules/@deepseek-ai/dsh-tools"
export DSH_FS_LOCAL_ORIGINAL_JS="$prefix/fs-local-original.js"

cd "$root"

# Test glob expansion must find actual files, and TAP must contain real passing tests.
shopt -s nullglob
files=("$root"/runtime/tests/*.test.mjs "$root"/app/tool/engine_auth/*.test.mjs)
(( ${#files[@]} > 0 )) || { echo 'FAIL: zero matching test files' >&2; exit 1; }
set +e
node --test --test-reporter=tap "${files[@]}" > "$RUNNER_TEMP/runtime-tests.tap" 2>&1
status=$?
set -e
cat "$RUNNER_TEMP/runtime-tests.tap"
if (( status != 0 )); then echo "FAIL: node exit $status" >&2; exit "$status"; fi
read_tap() { sed -nE "s/^# $1 ([0-9]+)$/\1/p" "$RUNNER_TEMP/runtime-tests.tap" | tail -1; }
tests="$(read_tap tests)"; passed="$(read_tap pass)"; failed="$(read_tap fail)"
if [[ ! "$tests" =~ ^[0-9]+$ || ! "$passed" =~ ^[0-9]+$ || ! "$failed" =~ ^[0-9]+$ ]] || (( tests == 0 || passed == 0 || failed != 0 )); then
  echo 'FAIL: zero-test, skip-only, incomplete TAP summary, or failing tests' >&2
  exit 1
fi
echo "PASS: $passed of $tests tests passed; remaining tests may be skipped (inspect TAP)."
