# Claude Token Diet

**Cut your Claude Code token usage by 60–90%. One install. Works everywhere. Reversible any time.**

---

Claude Code is powerful, but it reads a lot. Every `git status`, every file
read, every grep — all that output lands in your context window. On a long
session you can easily burn 500k+ tokens on raw command output that nobody
reads twice.

`diet` wraps three proven techniques into a single setup:

1. **Output compression** — via [`rtk`](https://github.com/rtk-ai/rtk), a shell
   proxy that compresses command output before Claude sees it.
2. **Behavioral rules** — a drop-in `CLAUDE.md` block that tells Claude to stop
   re-reading files, narrating every step, or spawning agents for trivial work.
3. **Context audit** — a command to tell you *where your tokens are going*
   right now, and what to prune next.

Plus a single command — `diet stats` — that shows what you saved.

---

## Install

**One line:**

```bash
curl -fsSL https://raw.githubusercontent.com/xotw/claude-token-diet/main/install.sh | bash
```

Or, if you cloned the repo:

```bash
git clone https://github.com/xotw/claude-token-diet.git ~/.claude-token-diet
~/.claude-token-diet/install.sh
```

That's it. Restart Claude Code when it tells you to.

**Requirements:** macOS or Linux, `python3` (pre-installed on Mac), and either
`brew` or `curl` (for installing rtk). No Rust toolchain needed.

---

## Usage

```bash
diet stats          # Show your savings (today by default)
diet stats --week   # Last 7 days
diet stats --all    # Since install
diet stats --explain   # How the numbers are computed

diet audit          # Find what's still eating your context
diet audit mcp      #   → MCP servers: which are idle, which earn their keep
diet audit md       #   → CLAUDE.md size + trim suggestions
diet audit files    #   → Heaviest file reads this week

diet undo           # Roll back every change cleanly
diet help
```

### Example: `diet stats`

```
  Claude Token Diet — your savings

  rtk (Bash-tool compression)
    Commands run:   347
    Raw bytes:      682,104
    Compressed:     143,220
    Saved:          538,884 bytes (79%)

  Today — Claude Code usage
    Sessions:         8
    Assistant turns:  412
    Input tokens:     2,104,330
    Output tokens:    58,420
    Cache hit rate:   88%   healthy
    Estimated spend:  $3.42
    Saved by cache:   $28.10   (vs. no prompt caching)

  Where your tokens go
    ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇   82.1%  Cache (stable context)
    ▇▇                              5.3%  New input (this turn)
    ▇▇                              6.2%  Cache writes (updates)
    ▇▇                              6.4%  Output (Claude's reply)

  Opportunities still on the table
    • You have 8 global MCP servers loaded — each adds tool schemas
      to every turn. Run: diet audit mcp
```

---

## What's actually happening?

### Layer 1 — Tool output bloat (the part rtk handles)

Shell commands are noisy. `ls` dumps every file. `git status` lists everything.
`cat` returns entire files. When Claude uses the Bash tool, all that output
gets pasted into the model's context, whether Claude actually needs it or not.

`rtk` sits between Claude and your shell. `git status` → `rtk git status`
transparently, and Claude sees a compressed version. **60-90% smaller** for
most dev commands.

### Layer 2 — Behavioral waste (the part CLAUDE.md handles)

Claude Code has three file-reading tools — `Read`, `Grep`, `Glob` — that
bypass the shell entirely. rtk can't help there. Instead, we give Claude a
set of rules in `CLAUDE.md`:

- Don't re-read a file you just edited
- Don't read a file without knowing what you're looking for
- Don't spawn a subagent when a single Grep would do
- Don't write summaries between every tool call

These are small rules, but they compound across a long session.

### Layer 3 — Always-loaded context (the silent whale)

Every Claude Code session loads your `CLAUDE.md` *and* the schema for every
MCP server you have configured. One MCP is fine. Ten MCPs is 30-80k tokens of
tool schemas loaded before you type anything. `diet audit mcp` shows which of
your MCPs haven't been called in 30 days so you can disable the dead weight.

### Layer 4 — Cache hit rate (the free multiplier)

Anthropic's prompt cache is 10× cheaper to read than fresh input. Cache TTL
is 5 minutes. If you're pausing between Claude Code messages for 6+ minutes,
you're blowing the cache every time. `diet stats` shows your cache hit rate
so you can see if your session rhythm is costing you.

---

## How `diet stats` computes savings

Run `diet stats --explain` for the full breakdown. Short version:

- **rtk savings**: exact. Measured by rtk itself, compressed-vs-raw bytes.
- **Session tokens**: exact. Parsed from Claude Code's own transcripts in
  `~/.claude/projects/*.jsonl`.
- **Cost**: exact × current Anthropic pricing (override via `DIET_PRICE_*`
  env vars if you're on a different tier).
- **Cache savings**: counterfactual — what you'd pay if every `cache_read`
  were a fresh `input`. Clearly a ballpark, but directionally honest.

We don't fake precision. If a number is estimated, the tool says so.

---

## Uninstall

```bash
diet undo
```

Removes the hook from `settings.json`, removes the `CLAUDE.md` block, removes
the symlink. Leaves rtk installed (run `brew uninstall rtk` yourself if you
want it gone). All changes are backed up with timestamps.

---

## FAQ

**Does this send my data anywhere?**
No. Everything runs locally. `diet` reads files on your machine and prints to
your terminal. rtk is the same. Nothing phones home.

**Will this break my existing CLAUDE.md or settings?**
No. `diet install` appends to `CLAUDE.md` with clearly marked start/end
comments. It uses rtk's own `--auto-patch` to merge into `settings.json`.
Both files get timestamped backups before any change. `diet undo` is clean.

**I use Cursor / Windsurf / Cline / something else, not Claude Code.**
rtk supports all of those. `diet install` currently wires Claude Code by
default. For other agents, run `rtk init --agent cursor` (or windsurf, cline,
etc.) manually after `diet install` — see the rtk docs.

**My cache hit rate is low. Why?**
Usually one of:
- You let the session idle >5 minutes between messages (cache TTL)
- You edited `CLAUDE.md` mid-session (cache invalidation)
- You added/removed MCP servers mid-session (cache invalidation)

Keep sessions moving or use `/clear` at natural breaks.

**Is `diet stats` accurate?**
The rtk numbers and token counts are exact — they're read from source of
truth. The cost and cache-savings estimates use current Anthropic public
pricing; if you're on a different plan, override with `DIET_PRICE_INPUT`,
`DIET_PRICE_OUTPUT`, `DIET_PRICE_CACHE_READ`, `DIET_PRICE_CACHE_WRITE` env
vars.

---

## Credits

- [rtk](https://github.com/rtk-ai/rtk) does the hard part (shell output
  compression). Diet is a thin layer that makes it accessible and adds the
  other layers.
- Anthropic's prompt caching is the silent hero of long Claude Code sessions.

MIT license.
