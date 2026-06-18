#!/usr/bin/env bash
# tools/run_tests.sh — run the ACKS Arbiter headless test suite in an
# APPDATA-isolated user dir (bash / git-bash mirror of tools/run_tests.ps1).
#
# Godot derives user:// from %APPDATA% (+ the project name), which is identical
# across every git worktree of this project. Pointing %APPDATA% at a private
# per-worktree temp dir gives the suite its own campaign.db + saves, so it never
# wipes the player's live save data and concurrent worktrees don't collide on
# one DB ("database is locked"). The dir is stable per worktree, so re-runs
# reuse the same isolated test DB (no fresh-DB FK-noise every run).
#
# It also passes `-- --test` so CampaignRepository redirects to campaign_test.db
# even if APPDATA isolation were somehow bypassed.
#
# Usage:  bash tools/run_tests.sh           # run twice, report run 2
#         bash tools/run_tests.sh 1         # single run (fresh-DB FK noise)
#         GODOT=/c/godot/other.exe bash tools/run_tests.sh
set -euo pipefail

GODOT="${GODOT:-/c/godot/Godot_v4.6.1-stable_win64_console.exe}"
RUNS="${1:-2}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root_unix="$(cd "$script_dir/.." && pwd)"
# Windows form of the project root, used both for Godot --path and for a stable
# per-worktree hash. `pwd -W` yields C:/... in git-bash; fall back to the unix path.
project_root_win="$(cd "$script_dir/.." && pwd -W 2>/dev/null || echo "$project_root_unix")"

hash="$(printf '%s' "$project_root_win" | sha1sum | cut -c1-8)"
# %APPDATA% must be a Windows-style path for Godot to consume it.
temp_win="$(cygpath -w "${TEMP:-${TMP:-/tmp}}" 2>/dev/null || echo "$TEMP")"
isolated_appdata="${temp_win}\\acks_test_appdata_${hash}"
mkdir -p "$(cygpath -u "$isolated_appdata" 2>/dev/null || echo "/tmp/acks_test_appdata_${hash}")" 2>/dev/null || true

export APPDATA="$isolated_appdata"
echo "ACKS Arbiter test suite"
echo "  project        : $project_root_win"
echo "  isolated APPDATA: $isolated_appdata"
echo "  (live save data in your real %APPDATA% is never touched)"

log="$project_root_unix/headless_test_run.log"
for i in $(seq 1 "$RUNS"); do
  echo "--- Run $i of $RUNS ---"
  "$GODOT" --headless --path "$project_root_win" res://tests/test_runner.tscn -- --test > "$log" 2>&1
done

echo "Done. Full log: $log"
echo "Summary (last lines):"
grep -E "TEST MODE|passed|failed|PASS|FAIL|TOTAL" "$log" | tail -n 12 | sed 's/^/  /'
