#!/usr/bin/env bash
# diet stats — show token savings across rolling time windows
#
# Default output: a table of 4 rolling windows (24h / 48h / 7d / 30d) with
# sessions, turns, spend, cache hit rate, and $ saved by prompt caching.
#
# Pulls three signals:
#   1. rtk gain --format json  → exact Bash-tool compression savings (cumulative)
#   2. ~/.claude/projects/*.jsonl transcripts → actual per-message token usage,
#      filtered by each message's own `timestamp` (not file mtime)
#   3. MCP server config → number of MCPs loaded (flagged as opportunity)

set -e
DIET_ROOT="${DIET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$DIET_ROOT/lib/helpers.sh"

EXPLAIN=0
WINDOW=""   # empty = show all four; otherwise one of 24h,48h,7d,30d
for arg in "$@"; do
  case "$arg" in
    --explain) EXPLAIN=1 ;;
    --24h|--today)    WINDOW="24h" ;;
    --48h)            WINDOW="48h" ;;
    --7d|--week)      WINDOW="7d" ;;
    --30d|--month)    WINDOW="30d" ;;
    --all)            WINDOW="all" ;;
    -h|--help)
      cat <<EOF
diet stats — see your token savings

Usage: diet stats [--window] [--explain]

By default, prints a stacked view across 4 rolling windows:
  Last 24 hours, Last 48 hours, Last 7 days, Last 30 days

Single-window flags (optional):
  --24h        Just the last 24 hours
  --48h        Just the last 48 hours
  --7d         Just the last 7 days
  --30d        Just the last 30 days
  --all        Since install (unbounded)

Other:
  --explain    Show how the numbers are computed

Numbers come from:
  • rtk gain (exact Bash-tool savings, cumulative)
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

Three sources:

  ${C_CYAN}1. rtk gain --format json${C_RESET}
     rtk wraps Bash commands and compresses output. Cumulative only
     (rtk doesn't timestamp per call).

  ${C_CYAN}2. ~/.claude/projects/*.jsonl${C_RESET}
     Claude Code writes full transcripts with per-message usage:
       input_tokens, cache_creation_input_tokens, cache_read_input_tokens,
       output_tokens, timestamp
     We filter by each message's own timestamp, not file mtime.

  ${C_CYAN}3. Pricing${C_RESET}
     Input \$${PRICE_INPUT}/M, Output \$${PRICE_OUTPUT}/M,
     Cache read \$${PRICE_CACHE_READ}/M, Cache write \$${PRICE_CACHE_WRITE}/M
     Override: DIET_PRICE_INPUT / DIET_PRICE_OUTPUT / DIET_PRICE_CACHE_READ /
               DIET_PRICE_CACHE_WRITE

${C_BOLD}"Saved by cache" column${C_RESET}
  Counterfactual: if every cache_read had been fresh input at \$${PRICE_INPUT}/M,
  plus no cache_write premium. Directionally honest, not exact.

${C_BOLD}Not counted${C_RESET}
  Savings from disabled MCPs or slimmed CLAUDE.md — structural, not
  turn-attributable. Use ${C_CYAN}diet audit${C_RESET} for those opportunities.
EOF
  exit 0
fi

echo ""
echo "  ${C_BOLD}Claude Token Diet${C_RESET} — your savings"
echo ""

# ── Section 1: rtk savings (cumulative) ──────────────────────────────────────
if has_cmd rtk; then
  export RTK_JSON="$(rtk gain --format json 2>/dev/null || echo '{}')"
  python3 - <<'PY'
import json, os
data = json.loads(os.environ.get("RTK_JSON") or '{}')
s = data.get('summary', {})
cmds = s.get('total_commands', 0)
raw = s.get('total_input', 0)
comp = s.get('total_output', 0)
saved = s.get('total_saved', 0)
pct = s.get('avg_savings_pct', 0)
tty = os.isatty(1) and not os.environ.get('NO_COLOR')
C = lambda code,x: f"\033[{code}m{x}\033[0m" if tty else x
B = lambda x: C("1", x); DIM = lambda x: C("2", x); CYAN = lambda x: C("36", x)
print(f"  {B('rtk (Bash-tool compression)')}  {DIM('cumulative since install')}")
if cmds == 0:
    print(f"    {DIM('— no rtk activity yet —')}  restart Claude Code, then run any shell command")
else:
    ratio = (1 - comp/raw) * 100 if raw else 0
    print(f"    {cmds:,} commands  •  {raw:,} bytes raw  →  {comp:,} bytes after  ({ratio:.0f}% smaller)")
PY
else
  echo "  ${C_YELLOW}rtk not installed${C_RESET} — run: diet install"
fi

# ── Section 2: rolling-window table from transcripts ─────────────────────────
python3 - <<PY
import json, os, glob, time
from datetime import datetime

PROJECTS = "${CLAUDE_PROJECTS_DIR}"
PRICE_IN = float("${PRICE_INPUT}")
PRICE_OUT = float("${PRICE_OUTPUT}")
PRICE_CACHE_R = float("${PRICE_CACHE_READ}")
PRICE_CACHE_W = float("${PRICE_CACHE_WRITE}")
WINDOW_FILTER = "${WINDOW}"

tty = os.isatty(1) and not os.environ.get("NO_COLOR")
def C(code, s): return f"\033[{code}m{s}\033[0m" if tty else s
B = lambda s: C("1", s); DIM = lambda s: C("2", s)
GREEN = lambda s: C("32", s); YEL = lambda s: C("33", s); RED = lambda s: C("31", s)

ALL_WINDOWS = [
    ("24h", "Last 24 hours", 86400),
    ("48h", "Last 48 hours", 2*86400),
    ("7d",  "Last 7 days",   7*86400),
    ("30d", "Last 30 days",  30*86400),
    ("all", "All time",      None),
]

if WINDOW_FILTER:
    windows = [w for w in ALL_WINDOWS if w[0] == WINDOW_FILTER]
else:
    # default: skip "all time" in the stacked view (keeps table tight)
    windows = [w for w in ALL_WINDOWS if w[0] != "all"]

now = time.time()
max_window_sec = max((w[2] for w in windows if w[2] is not None), default=None)
cutoff_oldest = 0 if max_window_sec is None else now - max_window_sec

# Walk every jsonl once, bucket messages into all matching windows
stats = {w[0]: dict(input=0, cache_read=0, cache_create=0, output=0,
                    msgs=0, sessions=set()) for w in windows}

def parse_ts(s):
    if not s: return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None

for fp in glob.glob(f"{PROJECTS}/**/*.jsonl", recursive=True):
    # Cheap file-level filter: if file untouched since oldest cutoff, skip
    if max_window_sec is not None and os.path.getmtime(fp) < cutoff_oldest:
        continue
    try:
        with open(fp) as f:
            for line in f:
                try: d = json.loads(line)
                except: continue
                if d.get("type") != "assistant": continue
                ts = parse_ts(d.get("timestamp"))
                if ts is None: continue
                age = now - ts
                u = (d.get("message") or {}).get("usage") or {}
                if not u: continue
                sid = d.get("sessionId") or fp
                for wkey, _, wsec in windows:
                    if wsec is None or age <= wsec:
                        s = stats[wkey]
                        s["input"] += u.get("input_tokens", 0) or 0
                        s["cache_read"] += u.get("cache_read_input_tokens", 0) or 0
                        s["cache_create"] += u.get("cache_creation_input_tokens", 0) or 0
                        s["output"] += u.get("output_tokens", 0) or 0
                        s["msgs"] += 1
                        s["sessions"].add(sid)
    except FileNotFoundError:
        continue

def row_metrics(s):
    total_in = s["input"] + s["cache_read"] + s["cache_create"]
    hit = (s["cache_read"] / total_in * 100) if total_in else 0
    spend = (
        s["input"] * PRICE_IN / 1_000_000 +
        s["output"] * PRICE_OUT / 1_000_000 +
        s["cache_read"] * PRICE_CACHE_R / 1_000_000 +
        s["cache_create"] * PRICE_CACHE_W / 1_000_000
    )
    spend_nocache = (
        total_in * PRICE_IN / 1_000_000 +
        s["output"] * PRICE_OUT / 1_000_000
    )
    saved = spend_nocache - spend
    return len(s["sessions"]), s["msgs"], spend, hit, saved

def hit_color(h):
    if h > 70: return GREEN(f"{h:>3.0f}%")
    if h > 40: return YEL(f"{h:>3.0f}%")
    return RED(f"{h:>3.0f}%")

def fmt_money(x): return f"\${x:,.2f}"

# Print table
print()
print(f"  {B('Usage by rolling window')}  {DIM('(from Claude Code transcripts)')}")
print()
headers = ["Period", "Sessions", "Turns", "Spend", "Cache", "Saved by cache"]
widths  = [15, 9, 8, 10, 6, 15]
line = "    " + "  ".join(h.ljust(w) for h,w in zip(headers, widths))
print(B(line))
print("    " + "  ".join("─"*w for w in widths))

for wkey, wlabel, _ in windows:
    sessions, turns, spend, hit, saved = row_metrics(stats[wkey])
    if turns == 0:
        cells = [wlabel.ljust(widths[0]), DIM("— no activity —").ljust(widths[1]+20)]
        print("    " + "  ".join(cells))
        continue
    row = [
        wlabel.ljust(widths[0]),
        f"{sessions:,}".rjust(widths[1]),
        f"{turns:,}".rjust(widths[2]),
        fmt_money(spend).rjust(widths[3]),
        hit_color(hit).rjust(widths[4] + (len(hit_color(hit)) - 4 if tty else 0)),
        fmt_money(saved).rjust(widths[5]),
    ]
    print("    " + "  ".join(row))
print()

# Quick-read line for the first (most recent) window present
w0_key, w0_label, _ = windows[0]
_, t0, sp0, hit0, sv0 = row_metrics(stats[w0_key])
if t0:
    print(f"    {DIM('Read:')} {w0_label.lower()}  {t0:,} turns  •  {fmt_money(sp0)} spend  •  {fmt_money(sv0)} saved by cache")
else:
    print(f"    {DIM('No Claude Code activity in this window yet.')}")
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
echo "  ${C_DIM}tip: \`diet stats --30d\` drills into one window · \`diet stats --explain\` shows the math${C_RESET}"
echo ""
