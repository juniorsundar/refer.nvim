# Issue 4: Text provider wiring — commands, help_tags, macros + on_change path

### Parent

PRD: `docs/prd/frecency-enhanced-lua-sorting.md`

### What to build

Extend Frecency to the `commands`, `help_tags`, and `macros` Providers using the `text` key strategy. This slice also handles the `on_change` integration path, which the `commands` Provider uses instead of the normal `fuzzy.filter` pipeline.

**commands** — Uses `on_change` for real-time completion. Frecency reordering is applied in the `on_change` callback path when Provider identity is present and the `lua` Sorter is active. The callback's native completion order serves as the base order. For non-empty input, Frecency reorders within similar-position neighborhoods (no fuzzy scores are available on this path — position in the callback result list is the base). For empty input, Frecency fully sorts by frecency score. Pass `frecency = { provider = "commands", key_strategy = "text" }`.

**help_tags** — Synchronous provider. Pass `frecency = { provider = "help_tags", key_strategy = "text" }`. Items use display text as the Frecency key.

**macros** — Two-level picker. The outer picker (register selection) passes `frecency = { provider = "macros", key_strategy = "text" }`. The inner picker (macro content editing) must NOT inherit the outer `frecency` option — it must be stripped or overridden before calling `refer.pick` since macro editing is ephemeral.

The `text` key strategy uses `ReferItem.text` directly as the Frecency key. This is appropriate for Providers where display text is unique within the Provider. If duplicate display text exists, the `text` strategy will treat them as the same item — Providers with potential duplicates should not use `text`.

All ranking acceptance criteria assume the `lua` sorter is active. Under the default `blink` sorter, Frecency does not apply.

### Acceptance criteria

- [x] `commands` provider passes `frecency = { provider = "commands", key_strategy = "text" }`
- [x] Frecency reordering applies in the `on_change` callback path for commands when the `lua` Sorter is active — callback results are the base order, Frecency reorders within position-based neighborhoods for non-empty input
- [x] Empty-query commands picker with `lua` sorter active shows frecent commands first (full frecency ordering)
- [x] Frecency does NOT reorder command results when a non-`lua` sorter is active, when Provider identity is absent, when Frecency is globally disabled, or when per-provider Frecency is disabled
- [x] Selecting a command records Frecency for that command text; reopening with `lua` sorter active shows it ranked higher
- [x] `select_input` in the commands picker records only when the input exactly matches a ReferItem's `text` field in `current_matches`; arbitrary typed command text that doesn't match a completion does not record
- [x] `help_tags` provider passes `frecency = { provider = "help_tags", key_strategy = "text" }`
- [x] Selecting a help tag records Frecency; subsequent searches with `lua` sorter active show it ranked higher
- [x] Empty-query help_tags picker with `lua` sorter active shows frecent tags first
- [x] `macros` outer picker passes `frecency = { provider = "macros", key_strategy = "text" }`; inner macro-editing picker does NOT inherit or apply Frecency (the `frecency` option is stripped before the inner `refer.pick` call)
- [x] Frecency keys from `commands`, `help_tags`, and `macros` are isolated per-Provider (same text in different Providers does not cross-contaminate)
- [x] Cycling the sorter away from `lua` disables Frecency reordering in the `on_change` path; cycling back to `lua` re-enables it
- [x] Existing tests still pass; new tests cover: commands on_change Frecency reorder path, commands `on_change` no-reorder under non-lua sorters, empty-query ordering for commands/help_tags/macros, provider isolation, macros inner-picker no-Frecency, `select_input` recording semantics

### Blocked by

- Issue 2 (End-to-end tracer — buffers with Frecency)
