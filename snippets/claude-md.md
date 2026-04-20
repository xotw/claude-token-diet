<!-- diet:token-discipline:start -->
## Token Discipline (always on — installed by claude-token-diet)

Claude Code's built-in Read / Grep / Glob tools bypass the rtk hook. These rules
keep context lean where the hook can't help.

### Reading files
- State what you're looking for before reading. If you don't know, Grep first.
- Files >200 lines: use Read's `offset` + `limit`, or call `rtk read <file>` via Bash.
- Never re-read a file you just edited — Edit/Write would have errored if it failed.
- Never re-read a file already in conversation context unless it changed.

### Searching
- Prefer Grep over reading whole files.
- Default `output_mode: "files_with_matches"`. Only switch to `"content"` once you
  know which files matter.
- Scanning >50 files or large logs: call `rtk grep <pattern>` via Bash.

### Running commands
- Always route through rtk: git, gh, ls, cat, find, grep, test runners, linters,
  builds. The PreToolUse hook handles this automatically.
- Long-running tasks: use Bash `run_in_background` + Monitor, not polling loops.

### Agents / delegation
- Only spawn a subagent for truly parallel, independent work.
- Never delegate a search you could do in one Grep call.
- If a subagent returns >2k tokens of findings, a focused Grep probably sufficed.

### Narration
- No running commentary on reasoning. State actions, results, decisions.
- End-of-turn summary: one or two sentences max.
- No "let me think" / "I'll now" preambles.

### Writes
- No README / docs / planning files unless explicitly asked.
- Work from conversation context, not scratch-pad files.
<!-- diet:token-discipline:end -->
