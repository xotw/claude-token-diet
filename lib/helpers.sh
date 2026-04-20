#!/usr/bin/env bash
# Shared helpers for diet scripts

# Colors (degrade if NO_COLOR set or not a tty)
if [[ -n "$NO_COLOR" ]] || [[ ! -t 1 ]]; then
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_CYAN=""
else
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
fi

# Anthropic pricing per million tokens (Claude Sonnet 4.x default).
# Users can override via DIET_PRICE_INPUT / DIET_PRICE_OUTPUT / DIET_PRICE_CACHE_READ / DIET_PRICE_CACHE_WRITE.
PRICE_INPUT="${DIET_PRICE_INPUT:-3.00}"          # $/M input tokens
PRICE_OUTPUT="${DIET_PRICE_OUTPUT:-15.00}"       # $/M output tokens
PRICE_CACHE_READ="${DIET_PRICE_CACHE_READ:-0.30}"  # $/M cache read
PRICE_CACHE_WRITE="${DIET_PRICE_CACHE_WRITE:-3.75}" # $/M cache write (5m)

CLAUDE_PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
CLAUDE_CONFIG="${CLAUDE_CONFIG:-$HOME/.claude.json}"
CLAUDE_SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
CLAUDE_MD="${CLAUDE_MD:-$HOME/.claude/CLAUDE.md}"

has_cmd() { command -v "$1" >/dev/null 2>&1; }

die() { echo "${C_RED}error:${C_RESET} $*" >&2; exit 1; }

require_python3() {
  has_cmd python3 || die "python3 is required (install via: brew install python3)"
}

# Format a number with thousands separators: 12345 -> 12,345
fmt_num() {
  printf "%'d" "${1:-0}" 2>/dev/null || echo "$1"
}

# Format a dollar amount from a float: 0.4234 -> $0.42
fmt_money() {
  python3 -c "print(f'\${float(\"${1:-0}\"):.2f}')"
}

# Bar chart for percentages (0-100) in fixed-width
fmt_bar() {
  local pct="$1" width="${2:-20}"
  local filled
  filled=$(python3 -c "print(min(int(round(float(${pct}) * ${width} / 100)), ${width}))")
  local empty=$((width - filled))
  printf '%*s' "$filled" '' | tr ' ' '▇'
  printf '%*s' "$empty" ''
}
