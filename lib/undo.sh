#!/usr/bin/env bash
# diet undo — reverse every change diet install made

set -e
DIET_ROOT="${DIET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$DIET_ROOT/lib/helpers.sh"

echo ""
echo "  ${C_BOLD}diet undo${C_RESET} — reverse the install"
echo ""
echo "  This will:"
echo "    • Remove the Token Discipline block from ~/.claude/CLAUDE.md"
echo "    • Remove the ${C_CYAN}rtk hook claude${C_RESET} PreToolUse hook from settings.json"
echo "    • Remove the ~/.local/bin/diet symlink"
echo ""
echo "  It will NOT:"
echo "    • Uninstall rtk (run: brew uninstall rtk)"
echo "    • Touch your MCP config or other settings"
echo ""
read -r -p "  Continue? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "  aborted."; exit 0; }

# 1. CLAUDE.md snippet removal (between markers)
if [[ -f "$CLAUDE_MD" ]] && grep -q "<!-- diet:token-discipline:start -->" "$CLAUDE_MD"; then
  cp "$CLAUDE_MD" "$CLAUDE_MD.bak-diet-undo-$(date +%Y%m%d-%H%M%S)"
  python3 - <<PY
import re
p = "${CLAUDE_MD}"
with open(p) as f: s = f.read()
s = re.sub(
    r"\n?<!-- diet:token-discipline:start -->.*?<!-- diet:token-discipline:end -->\n?",
    "\n",
    s, flags=re.DOTALL
)
with open(p, "w") as f: f.write(s)
PY
  echo "  ${C_GREEN}✓${C_RESET} removed Token Discipline block from CLAUDE.md"
fi

# 2. settings.json — remove rtk hook entry
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak-diet-undo-$(date +%Y%m%d-%H%M%S)"
  python3 - <<PY
import json
p = "${CLAUDE_SETTINGS}"
with open(p) as f: s = json.load(f)
hooks = s.get("hooks", {}).get("PreToolUse", [])
kept = []
for h in hooks:
    inner = h.get("hooks", [])
    inner_kept = [x for x in inner if "rtk hook" not in (x.get("command") or "")]
    if inner_kept:
        h["hooks"] = inner_kept
        kept.append(h)
if hooks and "PreToolUse" in s.get("hooks", {}):
    s["hooks"]["PreToolUse"] = kept
with open(p, "w") as f: json.dump(s, f, indent=2)
PY
  echo "  ${C_GREEN}✓${C_RESET} removed rtk hook from settings.json"
fi

# 3. symlink
if [[ -L "$HOME/.local/bin/diet" ]]; then
  rm "$HOME/.local/bin/diet"
  echo "  ${C_GREEN}✓${C_RESET} removed ~/.local/bin/diet"
fi

echo ""
echo "  Done. Restart Claude Code for changes to take effect."
echo ""
