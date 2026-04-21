# Claude Token Diet

**Cut your Claude Code token usage by 60 to 90%. One command to install. Works on Mac and Linux. Reversible any time.**

---

## The problem

If you use Claude Code, it reads a *lot* in the background. Every `git status`, every file open, every search — all that output lands in Claude's memory. You're paying for Claude to read noise.

On a long session, you can easily burn through hundreds of thousands of tokens just on raw command output nobody actually needs.

## The fix

`diet` is a small tool that puts Claude on a diet. Same experience, way less waste.

It does three things:

1. **Compresses command output** before Claude sees it (80-90% smaller on average)
2. **Teaches Claude to read smarter** — no re-reading files, no useless searches, no writing random planning documents
3. **Audits your setup** — tells you which Claude extensions (MCP servers) you're paying for but never actually using

## Install (2 minutes)

Copy-paste this into your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/xotw/claude-token-diet/main/install.sh | bash
```

Then **restart Claude Code**. That's it.

If you'd rather clone the repo:

```bash
git clone https://github.com/xotw/claude-token-diet.git ~/.claude-token-diet
~/.claude-token-diet/install.sh
```

**You need:** macOS or Linux, Python 3 (pre-installed on Mac), and either Homebrew or `curl`.

## See what you saved

After a day of normal work:

```bash
diet stats
```

You get something like this:

```
  Claude Token Diet — your savings

  rtk (Bash-tool compression)  cumulative since install
    115 commands  •  4,037,054 bytes raw  →  5,982 bytes after  (100% smaller)

  Claude Code usage  (from your transcripts in ~/.claude/projects)

    Period                Sessions  Turns    Spend       Cache  Anthropic cache $
    ────────────────────  ────────  ───────  ──────────  ─────  ─────────────────
    Last 24 hours                9    1,345      $80.84    95%            $332.31
    Last 48 hours               15    1,841     $111.41    94%            $400.51
    Last 7 days                978   11,454     $627.88    88%          $1,651.92
    Last 30 days             6,171   44,729   $2,477.57    92%          $8,975.69
    Since diet install           7      977      $62.39    95%            $232.47

    diet installed: 2026-04-20 13:50
```

Reading the table:

- **The top line** is what diet directly saved you: 4 MB of shell output that Claude never had to read.
- **The table** is your normal Claude Code usage, broken into rolling time windows.
- **Since diet install** grows every session, so you can watch diet's impact in real time.

## Commands

```
diet stats        # see your savings
diet audit        # find what's still wasting tokens
  ├─ diet audit mcp    which Claude extensions are sitting idle
  ├─ diet audit md     how big is your CLAUDE.md
  └─ diet audit files  which files you're reading most
diet undo         # roll everything back, cleanly
diet help
```

## Safety

- Every change gets a timestamped backup before anything is touched
- `diet undo` reverses the install in seconds (removes the hook, removes the CLAUDE.md block, removes the symlink)
- Nothing leaves your machine — everything runs locally
- Works alongside your existing Claude Code setup, doesn't replace it

## FAQ

**Is this official Anthropic tooling?**
No. This is an open-source layer on top of Claude Code + [rtk](https://github.com/rtk-ai/rtk). It uses Claude Code's public hook system — nothing hacky.

**Does it work with Cursor / Windsurf / Cline?**
The underlying tool (rtk) supports them. `diet install` currently wires Claude Code. For other agents, run `rtk init --agent cursor` (or `windsurf`, `cline`, `codex`, etc.) manually after `diet install`.

**What if my cache hit rate is low?**
Usually means you're pausing more than 5 minutes between Claude Code messages (Anthropic's prompt cache expires after 5 min), or editing your `CLAUDE.md` mid-session (cache invalidation). Keep sessions moving.

**How accurate are the numbers?**
- **rtk compression line**: exact, measured by rtk.
- **Token counts**: exact, pulled from Claude Code's own transcript files.
- **Spend**: tokens × current Anthropic public pricing (override with `DIET_PRICE_*` env vars if you're on a different tier).
- **Anthropic cache $**: counterfactual — what you'd pay if every cached read had been a fresh input. Directionally honest, not exact-to-the-cent.

**Why does the table show 30 days of data if I only installed diet yesterday?**
Because Claude Code has been writing your usage to disk the whole time. diet just reads those transcripts. The **Since diet install** row is the only one scoped to after you installed diet.

**Can I uninstall cleanly?**
Yes. `diet undo` removes everything diet added. Run `brew uninstall rtk` if you also want the underlying compression tool gone.

---

MIT license. Built by [@xotw](https://github.com/xotw). Issues, PRs, feedback welcome.

Credit: the compression engine is [rtk](https://github.com/rtk-ai/rtk). diet stacks behavioral rules, auditing, and honest accounting on top of it.
