#!/usr/bin/env bash
# Measure ataegina's line coverage from the bats suite and gate on a threshold.
#
# Why per-file + union, not `bashcov -- bats tests/`: bats spawns hundreds of bash
# processes, and SimpleCov's single coverage/.resultset.json can't absorb their
# concurrent writes — the aggregate under-counts badly (races drop data). Running
# bashcov ONE FILE at a time is reliable; we union the per-file line hits in Python.
#
# Requires: ruby + bashcov (gem), bats, python3. Runs the HERMETIC (unit) suite by
# default — fast, no real servers — which already reaches the gate: the real-process
# lines are covered hermetically via fake port tools + `true` backends. Set
# ATE_TEST_INTEGRATION=1 to additionally trace the real-server tier (slower; the
# number is unchanged). Usage:
#   scripts/coverage.sh [MIN_PERCENT]     (default 99)
set -u
cd "$(dirname "$0")/.."
MIN="${1:-99}"
command -v bashcov >/dev/null 2>&1 || { echo "coverage: bashcov not found (gem install bashcov)"; exit 127; }
command -v bats    >/dev/null 2>&1 || { echo "coverage: bats not found"; exit 127; }
command -v python3 >/dev/null 2>&1 || { echo "coverage: python3 not found"; exit 127; }

# Default to the hermetic tier (integration tests skip); opt in with ATE_TEST_INTEGRATION=1.
export ATE_TEST_INTEGRATION="${ATE_TEST_INTEGRATION:-0}"
UNION="$(mktemp)"
python3 -c 'import json,sys;json.dump({},open(sys.argv[1],"w"))' "$UNION"

for f in tests/*.bats; do
  rm -f coverage/.resultset.json coverage/.resultset.json.lock
  bashcov --root "$PWD" -- bats "$f" >/dev/null 2>&1 || true
  python3 - "$UNION" <<'PY' || true
import json,sys
union=sys.argv[1]
try: d=json.load(open("coverage/.resultset.json"))
except Exception: sys.exit(0)
cov=None
for _,info in d.items():
    for p,data in info["coverage"].items():
        if p.endswith("/ataegina"): cov=data["lines"] if isinstance(data,dict) else data
if cov is None: sys.exit(0)
u=json.load(open(union)); um=u.get("lines")
if um is None: um=[None]*len(cov); u["lines"]=um
for i,v in enumerate(cov):
    if i>=len(um): break
    if isinstance(v,int): um[i]=(0 if um[i] is None else um[i])+(1 if v>0 else 0)
json.dump(u,open(union,"w"))
PY
done

python3 - "$UNION" "$MIN" <<'PY'
import json,sys
u=json.load(open(sys.argv[1]))["lines"]; mn=float(sys.argv[2])
hit=sum(1 for x in u if isinstance(x,int) and x>0); rel=sum(1 for x in u if isinstance(x,int))
pct=100*hit/rel if rel else 0
print(f"ataegina line coverage: {hit}/{rel} = {pct:.2f}%  (min {mn}%)")
sys.exit(0 if pct>=mn else 1)
PY
rc=$?
rm -f "$UNION"
exit "$rc"
