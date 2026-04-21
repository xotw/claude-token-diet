#!/usr/bin/env bash
# diet install — one-shot setup
#
# What this does (plain English):
#   1. Installs rtk (Rust Token Killer) if missing — compresses shell command
#      output before Claude sees it.
#   2. Wires rtk into Claude Code as a global PreToolUse hook.
#   3. Appends a "Token Discipline" block to your ~/.claude/CLAUDE.md so Claude
#      follows the rules on tools rtk can't intercept (Read/Grep/Glob).
#   4. Symlinks the `diet` command into ~/.local/bin so you can run it anywhere.
#
# Safe to run more than once. Every change is backed up with a timestamp.
# Reverse everything with: diet undo

set -e
DIET_ROOT="${DIET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$DIET_ROOT/lib/helpers.sh"

DRY_RUN=0
SKIP_RTK=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-rtk) SKIP_RTK=1 ;;
    -h|--help)
      cat <<EOF
diet install — set up the token diet

Usage: diet install [--dry-run] [--skip-rtk]

Options:
  --dry-run    Show what would happen, don't change anything
  --skip-rtk   Don't try to install rtk (assume it's already there)
EOF
      exit 0
      ;;
  esac
done

say()   { echo "  $*"; }
step()  { echo ""; echo "  ${C_BOLD}→${C_RESET} ${C_BOLD}$*${C_RESET}"; }
ok()    { echo "    ${C_GREEN}✓${C_RESET} $*"; }
warn()  { echo "    ${C_YELLOW}!${C_RESET} $*"; }
skip()  { echo "    ${C_DIM}·${C_RESET} $*"; }

echo ""
echo "  ${C_BOLD}Claude Token Diet — install${C_RESET}"
echo ""
say "This will install rtk, wire the global hook, and add behavioral rules"
say "to your Claude Code setup. Every change is backed up and reversible."
say "Run ${C_CYAN}diet undo${C_RESET} any time to roll back."
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
  say "${C_YELLOW}DRY RUN${C_RESET} — nothing will actually change."
fi

# ── Step 1: rtk ──────────────────────────────────────────────────────────────
step "Install rtk (Rust Token Killer)"
if has_cmd rtk && rtk --version >/dev/null 2>&1; then
  ok "rtk already installed ($(rtk --version 2>&1 | head -1))"
elif [[ "$SKIP_RTK" -eq 1 ]]; then
  warn "skipping rtk install (--skip-rtk). You'll need to install it yourself."
else
  if [[ "$DRY_RUN" -eq 1 ]]; then
    skip "would install rtk via brew or curl"
  else
    if has_cmd brew; then
      say "installing via: brew install rtk"
      brew install rtk || die "brew install rtk failed"
    elif has_cmd curl; then
      say "installing via: curl | sh (rtk official installer)"
      curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
    else
      die "need brew or curl to install rtk. Install manually: https://github.com/rtk-ai/rtk"
    fi
    ok "rtk installed"
  fi
fi

# ── Step 2: wire the hook ────────────────────────────────────────────────────
step "Wire rtk hook into Claude Code (global)"
if has_cmd rtk; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    skip "would run: rtk init -g --auto-patch"
  else
    # rtk init creates its own backup
    rtk init -g --auto-patch 2>&1 | sed 's/^/      /'
    ok "hook wired into ~/.claude/settings.json"
  fi
else
  warn "rtk not installed, skipping hook"
fi

# ── Step 3: CLAUDE.md snippet ────────────────────────────────────────────────
step "Add Token Discipline rules to ~/.claude/CLAUDE.md"
SNIPPET="$DIET_ROOT/snippets/claude-md.md"
if [[ ! -f "$SNIPPET" ]]; then
  die "missing snippet file: $SNIPPET"
fi

if [[ -f "$CLAUDE_MD" ]] && grep -q "diet:token-discipline:start" "$CLAUDE_MD"; then
  ok "Token Discipline block already present (run ${C_CYAN}diet undo${C_RESET} to remove)"
else
  if [[ "$DRY_RUN" -eq 1 ]]; then
    skip "would append $(wc -l < "$SNIPPET" | tr -d ' ') lines to $CLAUDE_MD"
  else
    mkdir -p "$(dirname "$CLAUDE_MD")"
    if [[ -f "$CLAUDE_MD" ]]; then
      cp "$CLAUDE_MD" "$CLAUDE_MD.bak-diet-install-$(date +%Y%m%d-%H%M%S)"
    fi
    printf "\n\n" >> "$CLAUDE_MD"
    cat "$SNIPPET" >> "$CLAUDE_MD"
    ok "appended Token Discipline block (backup saved)"
  fi
fi

# ── Step 4: symlink ──────────────────────────────────────────────────────────
step "Make ${C_CYAN}diet${C_RESET} available globally"
BIN_DIR="$HOME/.local/bin"
TARGET="$BIN_DIR/diet"
SOURCE="$DIET_ROOT/bin/diet"

chmod +x "$SOURCE" "$DIET_ROOT/lib/"*.sh 2>/dev/null || true

if [[ "$DRY_RUN" -eq 1 ]]; then
  skip "would symlink $TARGET → $SOURCE"
else
  mkdir -p "$BIN_DIR"
  if [[ -L "$TARGET" ]] || [[ -f "$TARGET" ]]; then
    rm "$TARGET"
  fi
  ln -s "$SOURCE" "$TARGET"
  ok "symlinked $TARGET → $SOURCE"

  if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    warn "$BIN_DIR is not in your PATH."
    echo "      add to your shell rc (~/.zshrc or ~/.bashrc):"
    echo "      ${C_CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${C_RESET}"
  fi
fi

# ── Step 5: install marker (so `diet stats` can show "Since install" row) ───
step "Record install timestamp"
MARKER_DIR="$HOME/.config/diet"
MARKER="$MARKER_DIR/install_epoch"
if [[ "$DRY_RUN" -eq 1 ]]; then
  skip "would write install epoch to $MARKER"
elif [[ -f "$MARKER" ]]; then
  ok "marker already exists (kept original install date)"
else
  mkdir -p "$MARKER_DIR"
  date +%s > "$MARKER"
  ok "wrote $MARKER"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "  ${C_GREEN}${C_BOLD}✓ Install complete.${C_RESET}"
echo ""
echo "  ${C_BOLD}Next steps:${C_RESET}"
echo "    1. ${C_BOLD}Restart Claude Code${C_RESET} — the hook only loads on new sessions"
echo "    2. Work normally for a day"
echo "    3. Run ${C_CYAN}diet stats${C_RESET} to see your savings"
echo ""
echo "  Roll back any time: ${C_CYAN}diet undo${C_RESET}"
echo ""
