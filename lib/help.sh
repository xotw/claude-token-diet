#!/usr/bin/env bash
DIET_ROOT="${DIET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$DIET_ROOT/lib/helpers.sh"

cat <<EOF

  ${C_BOLD}diet${C_RESET} — Claude Token Diet

  Cut your Claude Code token usage 60-90%. Works on any Mac/Linux.
  Safe to uninstall any time.

  ${C_BOLD}Commands${C_RESET}
    ${C_CYAN}diet install${C_RESET}      One-shot setup (rtk + global hook + behavioral rules)
    ${C_CYAN}diet stats${C_RESET}        Show your savings (today | --week | --all)
    ${C_CYAN}diet audit${C_RESET}        Find what's still bloating your context
      ├─ diet audit mcp     MCP servers — which are idle, which earn their keep
      ├─ diet audit md      CLAUDE.md size check
      └─ diet audit files   Heaviest file reads
    ${C_CYAN}diet undo${C_RESET}         Reverse everything cleanly
    ${C_CYAN}diet help${C_RESET}         This message

  ${C_BOLD}Start here${C_RESET}
    1. Run ${C_CYAN}diet install${C_RESET}
    2. Restart Claude Code
    3. Work normally for a day
    4. Run ${C_CYAN}diet stats${C_RESET} to see what you saved

  ${C_BOLD}Docs${C_RESET}
    README:  $DIET_ROOT/README.md
    GitHub:  https://github.com/xotw/claude-token-diet

EOF
