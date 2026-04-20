#!/usr/bin/env bash
# diet stats — show token savings
#
# Pulls three signals:
#   1. rtk gain --format json  → exact Bash-tool compression savings
#   2. Claude Code transcripts → actual input/output/cache tokens per session
#   3. MCP server config       → number of MCPs loaded (schema cost estimate)
#
# "Savings" is computed as the delta vs. a realistic baseline — NOT a
# counterfactual fantasy. See --explain for the math.

set -e
DIET_ROOT="${DIET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$DIET_ROOT/lib/helpers.sh"

MODE="today"          # today | week | all
EXPLAIN=0
for arg in "$@"; do
  case "$arg" in
    --today) MODE="today" ;;
    --week)  MODE="week" ;;
    --all)   MODE="all" ;;
    --explain) EXPLAIN=1 ;;
    -h|--help)
      cat <<EOF
diet stats — see your token savings

Usage: diet stats [--today|--week|--all] [--explain]

Options:
  --today      Today only (default)
  --week       Last 7 days
  --all        Since install
  --explain    Show how the numbers are computed

Numbers come from:
  • rtk gain (exact Bash-tool savings)
  • ~/.claude/projects/*.jsonl transcripts (actual tokens used)
  • Current Anthropic pricing (override via DIET_PRICE_* env vars)
EOF
      exit 0
      ;;
  esac
done

require_python3

if [[ "$EXPLAIN" -eq 1 ]]; then
  cat <<EOF
${C_BOLD}How diet stats computes savings${C_RESET}

We pull from three sources:

  ${C_CYAN}1. rtk gain --format json${C_RESET}
     rtk wraps Bash commands and compresses output. It records raw-vs-compressed
     bytes for every call it handles. This number is exact, not estimated.

  ${C_CYAN}2. ~/.claude/projects/*.jsonl${C_RESET}
     Claude Code writes a full transcript per session with per-message usage:
       input_tokens, cache_creation_input_tokens, cache_read_input_tokens,
       output_tokens
     We sum these and compute cache hit rate = cache_read / total_input.

  ${C_CYAN}3. Pricing${C_RESET}
     Input  = \$${PRICE_INPUT}/M, Output = \$${PRICE_OUTPUT}/M,
     Cache read = \$${PRICE_CACHE_READ}/M, Cache write = \$${PRICE_CACHE_WRITE}/M
     Override via env: DIET_PRICE_INPUT, DIET_PRICE_OUTPUT,
                       DIET_PRICE_CACHE_READ, DIET_PRICE_CACHE_WRITE

${C_BOLD}What is NOT counted${C_RESET}
  • Savings from disabling MCP servers (run: diet audit mcp)
  • Savings from CLAUDE.md slimming
  These are structural — you save them every turn, but attributing turn-by-turn
  would be guesswork. We report "opportunities" instead.
EOF
  exit 0
fi

echo ""
echo "  ${C_BOLD}Claude Token Diet${C_RESET} — your savings"
echo ""

# ── Section 1: rtk savings ───────────────────────────────────────────────────
if has_cmd rtk; then
  rtk_json="$(rtk gain --format json 2>/dev/null || echo '{}')"
  python3 - <<PY
import json, os
data = json.loads('''$rtk_json''' or '{}')
s = data.get('summary', {})
cmds = s.get('total_commands', 0)
raw = s.get('total_input', 0)
comp = s.get('total_output', 0)
saved = s.get('total_saved', 0)
pct = s.get('avg_savings_pct', 0)
C = lambda x: f"\033[36m{x}\033[0m" if os.isatty(1) and not os.environ.get('NO_COLOR') else x
B = lambda x: f"\033[1m{x}\033[0m"  if os.isatty(1) and not os.environ.get('NO_COLOR') else x
print(f"  {B('rtk (Bash-tool compression)')}")
if cmds == 0:
    print(f"    {C('— no rtk activity yet —')}  restart Claude Code, then run a shell command")
else:
    print(f"    Commands run:   {cmds:,}")
    print(f"    Raw bytes:      {raw:,}")
    print(f"    Compressed:     {comp:,}")
    print(f"    Saved:          {saved:,} bytes ({pct:.0f}%)")
print()
PY
else
  echo "  ${C_YELLOW}rtk not installed${C_RESET} — run: diet install"
  echo ""
fi

# ── Section 2: session tokens from transcripts ───────────────────────────────
python3 - <<PY
import json, os, glob, time
from datetime import datetime, timezone

MODE = "$MODE"
PROJECTS = "${CLAUDE_PROJECTS_DIR}"
PRICE_IN = float("${PRICE_INPUT}")
PRICE_OUT = float("${PRICE_OUTPUT}")
PRICE_CACHE_R = float("${PRICE_CACHE_READ}")
PRICE_CACHE_W = float("${PRICE_CACHE_WRITE}")

tty = os.isatty(1) and not os.environ.get("NO_COLOR")
def C(code, s):
    return f"\033[{code}m{s}\033[0m" if tty else s
B = lambda s: C("1", s)
CYAN = lambda s: C("36", s)
DIM = lambda s: C("2", s)
GREEN = lambda s: C("32", s)
YEL = lambda s: C("33", s)

now = time.time()
cutoff_s = {
    "today": now - 86400,
    "week":  now - 7*86400,
    "all":   0,
}[MODE]

totals = dict(input=0, cache_read=0, cache_create=0, output=0, msgs=0)
active_sessions = set()

def parse_ts(s):
    if not s: return None
    try:
        # fromisoformat on 3.9 doesn't accept trailing Z
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None

for fp in glob.glob(f"{PROJECTS}/**/*.jsonl", recursive=True):
    # Skip files whose mtime is older than cutoff — can't contain any qualifying messages
    if os.path.getmtime(fp) < cutoff_s: continue
    try:
        with open(fp) as f:
            for line in f:
                try:
                    d = json.loads(line)
                except: continue
                if d.get("type") != "assistant": continue
                ts = parse_ts(d.get("timestamp"))
                if ts is None or ts < cutoff_s: continue
                u = (d.get("message") or {}).get("usage") or {}
                if not u: continue
                totals["msgs"] += 1
                totals["input"] += u.get("input_tokens", 0) or 0
                totals["cache_read"] += u.get("cache_read_input_tokens", 0) or 0
                totals["cache_create"] += u.get("cache_creation_input_tokens", 0) or 0
                totals["output"] += u.get("output_tokens", 0) or 0
                sid = d.get("sessionId") or fp
                active_sessions.add(sid)
    except FileNotFoundError: continue

totals["sessions"] = len(active_sessions)

total_in_any = totals["input"] + totals["cache_read"] + totals["cache_create"]
cache_hit = (totals["cache_read"] / total_in_any * 100) if total_in_any else 0

cost = (
    totals["input"]         * PRICE_IN / 1_000_000 +
    totals["output"]        * PRICE_OUT / 1_000_000 +
    totals["cache_read"]    * PRICE_CACHE_R / 1_000_000 +
    totals["cache_create"]  * PRICE_CACHE_W / 1_000_000
)

# Counterfactual: no cache → every cache_read becomes fresh input
cost_nocache = (
    (totals["input"] + totals["cache_read"] + totals["cache_create"]) * PRICE_IN / 1_000_000 +
    totals["output"] * PRICE_OUT / 1_000_000
)
saved_cache = cost_nocache - cost

label = {"today":"Today", "week":"Last 7 days", "all":"Since install"}[MODE]
print(f"  {B(label + ' — Claude Code usage')}")
if totals["msgs"] == 0:
    print(f"    {DIM('— no sessions in this window —')}")
else:
    print(f"    Sessions:         {totals['sessions']:,}")
    print(f"    Assistant turns:  {totals['msgs']:,}")
    print(f"    Input tokens:     {totals['input'] + totals['cache_read'] + totals['cache_create']:,}")
    print(f"    Output tokens:    {totals['output']:,}")
    print(f"    Cache hit rate:   {cache_hit:.0f}%   " +
          (GREEN("healthy") if cache_hit > 70 else
           YEL("could be higher") if cache_hit > 40 else
           C("31", "low — sessions gapping past 5 min cache TTL")))
    print(f"    Estimated spend:  \${cost:.2f}")
    print(f"    Saved by cache:   \${saved_cache:.2f}   {DIM('(vs. no prompt caching)')}")
print()

# ── Where tokens go (structural breakdown) ──────────────────────────────────
if totals["msgs"]:
    buckets = {
        "Cache (stable context)": totals["cache_read"],
        "New input (this turn)":  totals["input"],
        "Cache writes (updates)": totals["cache_create"],
        "Output (Claude's reply)": totals["output"],
    }
    total = sum(buckets.values())
    print(f"  {B('Where your tokens go')}")
    for name, val in buckets.items():
        pct = (val / total * 100) if total else 0
        w = 30
        filled = min(int(round(pct * w / 100)), w)
        bar = "▇" * filled + " " * (w - filled)
        print(f"    {bar}  {pct:4.1f}%  {name}")
    print()
PY

# ── Section 3: opportunities ─────────────────────────────────────────────────
mcp_count=$(python3 -c "
import json
try:
    with open('${CLAUDE_CONFIG}') as f: d = json.load(f)
    print(len(d.get('mcpServers', {})))
except: print(0)
" 2>/dev/null || echo 0)

echo "  ${C_BOLD}Opportunities still on the table${C_RESET}"
if [[ "$mcp_count" -gt 3 ]]; then
  echo "    ${C_YELLOW}•${C_RESET} You have $mcp_count global MCP servers loaded — each adds tool schemas"
  echo "      to every turn. Run: ${C_CYAN}diet audit mcp${C_RESET}"
fi
if ! has_cmd rtk; then
  echo "    ${C_YELLOW}•${C_RESET} rtk not installed — run: ${C_CYAN}diet install${C_RESET}"
fi
if [[ ! -f "$CLAUDE_MD" ]]; then
  echo "    ${C_YELLOW}•${C_RESET} No ~/.claude/CLAUDE.md — run: ${C_CYAN}diet install${C_RESET}"
elif ! grep -q "Token Discipline" "$CLAUDE_MD" 2>/dev/null; then
  echo "    ${C_YELLOW}•${C_RESET} CLAUDE.md missing the Token Discipline block — run: ${C_CYAN}diet install${C_RESET}"
fi
echo ""
echo "  ${C_DIM}tip: run \`diet stats --explain\` to see how these numbers are computed${C_RESET}"
echo ""
