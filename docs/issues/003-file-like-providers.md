# Issue 3: File-like provider wiring — old_files and files

### Parent

PRD: `docs/prd/frecency-enhanced-lua-sorting.md`

### What to build

Extend Frecency to the `old_files` and `files` Providers using the `filepath` key strategy. This slice adds two more Providers to the Frecency system, building on the end-to-end path established by Issue 2 (buffers).

**old_files** — Synchronous provider. Pass `frecency = { provider = "old_files", key_strategy = "filepath" }` in options. The `filepath` strategy resolves keys from `ReferItem.data.filename`. Verify that `vim.v.oldfiles` entries produce items with `data.filename` set to the absolute path; normalize with `vim.fn.fnamemodify(path, ":p")` if needed.

**files** — Asynchronous provider using `pick_async`. Frecency reordering applies to whatever results are currently displayed. The `files` provider uses `post_process` which manually calls `fuzzy.filter` — this call must pass frecency options and the active sorter name through to `fuzzy.filter`/`frecency.reorder` so Frecency applies only when the `lua` sorter is active.

Both providers should ensure `data.filename` contains absolute paths, normalized via `vim.fn.fnamemodify(path, ":p")`. Paths from `fd` output (the `files` provider) are relative to cwd and must be converted to absolute ReferItems with `data.filename` set to the full path before filtering/reordering, while preserving existing display text if desired.

**Empty-query note for files:** The `files` provider has `min_query_len = 2` by default, so empty-query Frecency does not apply under default configuration. Empty-query Frecency for files only works if the user sets `min_query_len = 0` or configures the provider to return all items on empty query. The acceptance criterion for empty-query files is conditional on this configuration.

**Non-participating providers:** Only `M.files` receives Provider identity in this file. `live_grep`, `grep_word`, and `lines` in the same module must remain without Provider identity and must not participate in Frecency.

All ranking acceptance criteria assume the `lua` sorter is active. Under the default `blink` sorter, Frecency does not apply.

### Acceptance criteria

- [ ] `old_files` provider passes `frecency = { provider = "old_files", key_strategy = "filepath" }`
- [ ] `old_files` items have `data.filename` set to absolute file paths (normalized via `vim.fn.fnamemodify(path, ":p")`)
- [ ] Selecting an old file records Frecency for that file; reopening with `lua` sorter active shows it ranked higher
- [ ] `files` provider passes `frecency = { provider = "files", key_strategy = "filepath" }`
- [ ] `files` async `post_process` converts `fd` output to ReferItems with absolute `data.filename` (normalized via `vim.fn.fnamemodify(path, ":p")`) before filtering/reordering
- [ ] `files` async `post_process` passes frecency options and active sorter name to `fuzzy.filter`/`frecency.reorder` so Frecency applies only when the `lua` sorter is active
- [ ] Frecency reordering applies to `files` results as they arrive (async post-process path) when the `lua` sorter is active
- [ ] Frecency does NOT apply to `files` results when a non-`lua` sorter is active (blink, mini, native, or custom)
- [ ] Empty-query `files` picker shows frecent files first — conditional on `min_query_len = 0` being configured; under default `min_query_len = 2`, this criterion does not apply
- [ ] Selecting a file records Frecency; subsequent searches with `lua` sorter active rank it higher
- [ ] Frecency keys for the same file reached from `buffers`, `old_files`, and `files` accumulate independently (per-Provider isolation)
- [ ] Same absolute file selected via `old_files` does not affect `buffers` or `files` frecency, and vice versa
- [ ] `live_grep`, `grep_word`, and `lines` providers remain without Provider identity and do not participate in Frecency
- [ ] Existing tests still pass; new tests cover: old_files Frecency wiring, files async post-process Frecency path, files ReferItem absolute-path normalization, per-Provider isolation across buffers/old_files/files, non-luapath no-reordering for files

### Blocked by

- Issue 2 (End-to-end tracer — buffers with Frecency)
