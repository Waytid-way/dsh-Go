# Issue #6: branch-local runtime verification

This is a **disposable local/sandbox runner**, not a GitHub Actions trigger. It does not push, open a PR, modify `main`, deploy, or use application secrets.

## Exact source and toolchain

- Fork base: `046b0c604056abbe81961f146cf414e3431ff6c5`.
- Upstream at investigation: `d9dae8d8cd1cf534c80f4bd6f08a3b68ecefac88` (18 commits ahead).
- Source of setup contract: upstream `.github/workflows/ci.yml` lines 227–299 (read on 2026-11-20).
- CI pins **Node 24.22.1**, **Flutter 3.47.7**, **Gradle 9.3.1**; runner is Ubuntu 24.04. This script exercises the Node runtime path only. It requires `node`, `npm`, `python3` and access to pinned npm dependencies.
- Pinned DSH and pnpm versions come from `runtime/build-runtime.sh`; npm lockfiles from `runtime/locks/`. Do not replace them with unpinned package versions.

## How to run

From an **isolated checkout of the branch being verified**:

```bash
# Verify checkout and exact SHA before execution:
git rev-parse HEAD
git status --short
node --version
python3 --version

# Disposable directory must be empty; the script refuses to overwrite its prefixes.
export RUNNER_TEMP="$(mktemp -d)"
bash tooling/verify-runtime-branch-tests.sh "$PWD"
# Capture stdout/stderr and exit status in the evidence comment.
# Review and remove RUNNER_TEMP only after verifying it belongs to this test.
```

The script mirrors the runtime CI preparation sequence: install DSH from lock, copy original fs-local module, patch Android DSH via `rtbuild.py`, install pinned pnpm, export `DSH_PREFIX`, `DSH_TEST_PREFIX`, `PNPM_BIN`, `DSH_INSTALL`, `DSH_TOOLS_DIR`, `DSH_FS_LOCAL_ORIGINAL_JS`, and run the Node tests. It checks the Node exit status and TAP summary, rejecting zero tests, skip-only, missing summary, or nonzero failures.

**Important:** CI has additional Python, native addon, bridge guard, Flutter and device checks. This script does not claim their results. Passing it is **targeted runtime Node verification**, not `CI OK`.

## Observed verification

- Local authoring environment: Node `v22.16.0`, Python `3.13.5`, Bash `5.2.37`. It is not the CI-pinned Node 24 environment.
- `bash -n` on the candidate script: **PASS** (syntax check only).
- Invalid checkout path test: **PASS** expected rejection with exit `64`; no tests executed.
- Real pinned npm installation, patch-dsh and runtime Node tests on this new branch: **NOT_RUN**. They require an isolated checkout with Node 24 and network access to pinned npm packages.
- Flutter 3.47.7 widget tests, OHOS ArkTS, Android/OHOS real device: **NOT_RUN**.
- Prior Vercel run on the fork baseline: raw Node test command failed because the patched prefix was absent. See [Issue #6 earlier checkpoint](https://github.com/Waytid-way/dsh-Go/issues/6#issuecomment-7017721252).

## Next verification

Use a single short-lived Vercel Sandbox (or an equivalent isolated Linux environment) with Node 24.22.1, pinned commit, and outbound npm registry access. Execute the script and capture the exit code, TAP test/pass/fail/skip totals, runtime versions, git SHA and exact failure if any. Stop the sandbox. If npm preparation fails deterministically, diagnose once and stop rather than retrying blindly.

**Security:** This runner installs third-party npm packages and executes patching code from the checked-out repository; run only in a disposable sandbox with no production credentials. It deliberately does not delete the disposable directory itself, so an operator can inspect failures before cleanup.
