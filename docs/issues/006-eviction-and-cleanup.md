# Issue 6: Eviction and cleanup

### Parent

PRD: `docs/prd/frecency-enhanced-lua-sorting.md`

### What to build

Add JSON store maintenance: periodic cleanup on Neovim exit to cap per-Provider storage and remove aged-out entries.

**Cleanup scope** — "Orphaned records" are defined as records expired by age or exceeding the per-Provider cap. There is no live-key pruning at VimLeavePre because no current Provider result set is available for comparison. Stale entries (referring to items no longer present in any Provider) are harmless at query time — they simply receive no boost — and are removed only by age-based deletion and per-Provider capping.

**Age-based deletion** — Delete records where `last_selected_at` is older than a configurable threshold (default: 180 days / 15,552,000 seconds). Age is computed from the current time at cleanup.

**Per-Provider cap** — When a Provider exceeds `max_entries_per_provider` (default: 10,000 — exact value, not approximate), delete the excess records with the lowest computed frecency score. Eviction ordering uses: computed frecency score ascending (lowest first), then `last_selected_at` ascending (oldest first), then `selected_count` ascending (lowest first), then `item_key` ascending for deterministic tie-breaking.

**Configuration** — Add cleanup options to the global `frecency` config in `setup()`:
- `max_entries_per_provider` (number, default: 10000): per-Provider entry cap
- `cleanup_max_age_days` (number, default: 180): age threshold in days for deletion

These join the existing `frecency.configure()` options alongside `db_path`, `buckets`, `neighborhood_size`, and `clock_fn`.

**VimLeavePre autocmd** — Register a `VimLeavePre` autocmd in a dedicated augroup that calls `frecency.cleanup()`. The autocmd is registered once during `setup()` (or `configure()`). Repeated `setup()` calls clear and re-register the augroup to avoid duplicates.

**Cleanup behavior in disabled/degraded/no-op states** — When Frecency is globally disabled or the session is in no-op mode, cleanup is a no-op. Cleanup does not create, read, or write the JSON store solely because Neovim exits. If no Frecency operations occurred during the session, cleanup is skipped entirely.

**Store rewrite** — After successful age deletion and capping, rewrite the JSON store using the same atomic temp-file + rename path as normal writes. If the rewrite fails, log a one-time WARN and continue shutdown. Rewriting runs only when cleanup has read a valid store.

**Failure handling** — Wrap all cleanup work in `pcall`. If any step fails (read/decode, age deletion, capping, or write), log a one-time WARN and return. Never raise from the autocmd. The `cleanup()` function never blocks Neovim exit beyond normal synchronous JSON file IO.

### Acceptance criteria

- [ ] On `VimLeavePre`, Frecency runs cleanup: deletes entries older than `cleanup_max_age_days` days (default 180) and caps per-Provider storage to exactly `max_entries_per_provider` entries (default 10000)
- [ ] `cleanup_max_age_days` and `max_entries_per_provider` are configurable via `setup().frecency` and `frecency.configure()`; age threshold is defined in days (converted to seconds internally for comparison)
- [ ] Per-Provider cap deletes entries ordered by: computed frecency score ascending (lowest first), then `last_selected_at` ascending (oldest first), then `selected_count` ascending (lowest first), then `item_key` ascending for deterministic tie-breaking
- [ ] After cleanup changes the store, the JSON file is atomically rewritten via temp file + rename
- [ ] If any cleanup step fails, a one-time WARN is logged and cleanup returns without raising
- [ ] `cleanup()` is wrapped in `pcall` and never raises from the `VimLeavePre` autocmd
- [ ] Stale entries (referring to items no longer present in any Provider) are harmless at query time — they receive no boost and are not eagerly deleted during reads or writes
- [ ] No eager deletion happens during read or write operations; all cleanup is deferred to `VimLeavePre`
- [ ] When Frecency is globally disabled, cleanup is a no-op and does not create, read, or write the JSON store
- [ ] When the session is in no-op mode, cleanup is a no-op and does not create, read, or write the JSON store
- [ ] When no Frecency operations occurred during the session, cleanup is skipped entirely
- [ ] The `VimLeavePre` autocmd is registered in a dedicated augroup during `setup()`/`configure()`; repeated `setup()` calls clear and re-register the augroup (no duplicates)
- [ ] Existing tests still pass; new tests cover: age deletion with deterministic timestamps, per-Provider cap with exact eviction ordering, deterministic tie-breaking, no deletion when at or below cap, no-op when disabled/no-op/no-operations, single autocmd registration, autocmd error handling (pcall), atomic rewrite after cleanup

### Blocked by

- Issue 2 (End-to-end tracer — buffers with Frecency)
- Issue 1 transitively (public `cleanup()` API and persistence internals)
