#!/usr/bin/env bash
# diet audit — find what's still eating your context

set -e
DIET_ROOT="${DIET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$DIET_ROOT/lib/helpers.sh"

SUB="${1:-summary}"
shift || true

require_python3

audit_mcp() {
  echo ""
  echo "  ${C_BOLD}MCP audit${C_RESET} — which servers are you paying schema-cost for?"
  echo ""
  python3 - <<PY
import json, os, glob, time
from pathlib import Path

cfg_path = "${CLAUDE_CONFIG}"
proj_dir = "${CLAUDE_PROJECTS_DIR}"

tty = os.isatty(1) and not os.environ.get("NO_COLOR")
def C(code, s): return f"\033[{code}m{s}\033[0m" if tty else s
B = lambda s: C("1", s); DIM = lambda s: C("2", s)
GREEN = lambda s: C("32", s); YEL = lambda s: C("33", s); RED = lambda s: C("31", s)

try:
    with open(cfg_path) as f: cfg = json.load(f)
except Exception as e:
    print(f"  cannot read {cfg_path}: {e}"); raise SystemExit

servers = cfg.get("mcpServers", {}) or {}
if not servers:
    print("  No global MCP servers configured. Nothing to audit.")
    raise SystemExit

# Scan recent transcripts for assistant tool_use of mcp__<server>__* tools.
# Counting raw marker occurrences over-counts because tool *schemas* dumped
# into system turns also match. So we walk only assistant messages and look
# for tool_use blocks whose 'name' starts with the MCP prefix.
from datetime import datetime
cutoff_ts = time.time() - 30 * 86400
used = {name: 0 for name in servers}

def ts_of(d):
    s = d.get("timestamp")
    if not s: return 0
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except: return 0

markers = {}
for name in servers:
    # MCP tool names normalize hyphens to underscores, but not always.
    markers[name] = {f"mcp__{name}__", f"mcp__{name.replace('-', '_')}__"}

for fp in glob.glob(f"{proj_dir}/**/*.jsonl", recursive=True):
    if os.path.getmtime(fp) < cutoff_ts: continue
    try:
        with open(fp) as f:
            for line in f:
                try: d = json.loads(line)
                except: continue
                if d.get("type") != "assistant": continue
                if ts_of(d) < cutoff_ts: continue
                msg = d.get("message") or {}
                content = msg.get("content")
                if not isinstance(content, list): continue
                for part in content:
                    if not isinstance(part, dict): continue
                    if part.get("type") != "tool_use": continue
                    tool_name = part.get("name") or ""
                    for srv, mks in markers.items():
                        if any(tool_name.startswith(m) for m in mks):
                            used[srv] += 1
                            break
    except: continue

total = len(servers)
idle = [n for n,c in used.items() if c == 0]
active = [n for n,c in used.items() if c > 0]

print(f"  Total MCP servers:  {total}")
print(f"  Active (30 days):   {GREEN(str(len(active)))}")
print(f"  Idle (30 days):     {YEL(str(len(idle))) if idle else GREEN('0')}")
print()
print(f"  {B('Per-server usage (last 30 days)')}")
# Sort by usage desc
for name in sorted(servers, key=lambda n: -used[n]):
    cnt = used[name]
    status = GREEN("active ") if cnt > 10 else YEL("rare   ") if cnt > 0 else RED("idle   ")
    print(f"    {status} {name:30s} {cnt:>5} calls")

print()
if idle:
    print(f"  {B('Suggested action')}")
    print(f"    {len(idle)} MCP(s) haven't been called in 30 days. Each one adds")
    print(f"    tool schemas to every Claude Code turn (~200-1000 tokens each).")
    print()
    print(f"    To disable, edit {cfg_path} and remove from 'mcpServers',")
    print(f"    OR run per-project: claude mcp disable <name>")
    print()
    print(f"    Idle MCPs: {', '.join(idle)}")
else:
    print(f"  {GREEN('✓ all MCPs are earning their keep')}")
PY
  echo ""
}

audit_files() {
  echo ""
  echo "  ${C_BOLD}File-read audit${C_RESET} — which files are eating the most tokens?"
  echo ""
  python3 - <<PY
import json, os, glob, time, re
from collections import Counter

proj_dir = "${CLAUDE_PROJECTS_DIR}"
cutoff = time.time() - 7 * 86400
tty = os.isatty(1) and not os.environ.get("NO_COLOR")
def C(code, s): return f"\033[{code}m{s}\033[0m" if tty else s
B = lambda s: C("1", s); DIM = lambda s: C("2", s)

# Rough heuristic: count Read tool calls per file path, size by bytes returned
file_calls = Counter()
for fp in glob.glob(f"{proj_dir}/**/*.jsonl", recursive=True):
    if os.path.getmtime(fp) < cutoff: continue
    try:
        with open(fp) as f:
            for line in f:
                try: d = json.loads(line)
                except: continue
                if d.get("type") != "user": continue
                msg = d.get("message") or {}
                content = msg.get("content")
                if not isinstance(content, list): continue
                for part in content:
                    if not isinstance(part, dict): continue
                    if part.get("type") != "tool_result": continue
                    text = part.get("content")
                    if isinstance(text, list):
                        text = "".join(p.get("text","") for p in text if isinstance(p, dict))
                    if not isinstance(text, str): continue
                    # look for cat -n line pattern from Read
                    m = re.search(r"^\s*\d+→", text, re.M)
                    if not m: continue
                    # We don't have the file path here directly — track by length instead
                    file_calls["__total__"] += len(text)
    except: continue

print(f"  Approx bytes returned by Read calls (last 7 days): {file_calls.get('__total__', 0):,}")
print(f"  {DIM('(per-file breakdown requires tool_use → tool_result join; planned)')}")
print()
print(f"  {B('Quick wins right now')}:")
print(f"    • For any file > 200 lines, use Read with offset+limit")
print(f"    • For scans across many files, call `rtk grep` via Bash")
print(f"    • Don't re-read a file after editing — Edit errors if it failed")
PY
  echo ""
}

audit_claude_md() {
  echo ""
  echo "  ${C_BOLD}CLAUDE.md audit${C_RESET} — is your always-loaded context slim?"
  echo ""
  if [[ ! -f "$CLAUDE_MD" ]]; then
    echo "  ${C_YELLOW}No $CLAUDE_MD found.${C_RESET}"
    return
  fi
  local lines words chars
  lines=$(wc -l < "$CLAUDE_MD" | tr -d ' ')
  words=$(wc -w < "$CLAUDE_MD" | tr -d ' ')
  chars=$(wc -c < "$CLAUDE_MD" | tr -d ' ')
  local approx_tokens=$((chars / 4))
  echo "  File:          $CLAUDE_MD"
  echo "  Size:          $lines lines, $words words, ~$approx_tokens tokens"
  echo ""
  if [[ "$approx_tokens" -gt 2000 ]]; then
    echo "  ${C_YELLOW}Heavy.${C_RESET} Every Claude Code turn pays ~$approx_tokens tokens just for CLAUDE.md."
    echo "  Over a 50-turn session, that's ~$((approx_tokens * 50 / 1000))k tokens."
    echo ""
    echo "  ${C_BOLD}How to cut it:${C_RESET}"
    echo "    • Move command definitions into slash commands (.claude/commands/*.md) —"
    echo "      those load on demand, not on every turn"
    echo "    • Keep in CLAUDE.md: identity, always-on rules, critical context only"
    echo "    • Move project-specifics into per-repo CLAUDE.md files"
  elif [[ "$approx_tokens" -gt 800 ]]; then
    echo "  ${C_GREEN}Reasonable.${C_RESET} Some room to trim but not urgent."
  else
    echo "  ${C_GREEN}Lean.${C_RESET} Nice."
  fi
  echo ""
}

case "$SUB" in
  mcp)    audit_mcp ;;
  files)  audit_files ;;
  md|claude-md) audit_claude_md ;;
  summary|"")
    audit_claude_md
    audit_mcp
    audit_files
    ;;
  -h|--help)
    cat <<EOF
diet audit — find context bloat

Usage: diet audit [subcommand]

Subcommands:
  mcp          List MCP servers and which are idle
  files        Biggest file reads this week
  md           CLAUDE.md size + trim suggestions
  summary      All of the above (default)
EOF
    ;;
  *)
    die "unknown audit target: $SUB (try: mcp, files, md, summary)"
    ;;
esac
