# PRD: Frecency In-Memory Cache and Clock Injection Cleanup

## Problem Statement

The Frecency persistence module (`db.lua`) reads and decodes the JSON store from disk on every `record()` and `read_scores()` call. In the picker's interactive path, `read_scores()` is invoked on every keystroke that triggers a refresh (~20ms debounce). For a typical store of a few hundred entries, this means redundant JSON decoding on every keystroke — I/O and parsing work that is unnecessary because the data has not changed since the last write within the same session.

Additionally, `record()` and `read_scores()` accept an `opts.clock_fn` parameter that permanently mutates the module-level `clock_fn` variable. This mechanism exists solely for test determinism and is marked `[TEST-ONLY]`, but it lives in the production code path. Any production caller that accidentally passes `clock_fn` via `opts` would clobber the module's clock for the rest of the session.

## Solution

### 1. In-memory cache

Add an in-memory cache to `db.lua`. On first access, the store is loaded from disk and cached. Subsequent `read_scores()` calls read from the in-memory cache. `record()` updates the in-memory cache and writes through to disk. The on-disk file remains authoritative across sessions; within a session, the in-memory cache is the source of truth.

The cache is invalidated (set to `nil`) only when:
- The module enters no-op mode (persistence failure).
- `_reset()` is called (test teardown).
- `configure()` changes the `db_path` (the cached store belongs to a different file).

`cleanup()` continues to operate on the in-memory cache and writes through to disk if changes were made.

### 2. Remove per-call `clock_fn` injection

Remove the `opts.clock_fn` parameter from `record()` and `read_scores()`. All clock injection goes through `configure({ clock_fn = ... })`. Tests use mutable closures to advance time between calls:

```lua
local t = 1000000
db.configure({ clock_fn = function() return t end })
db.record("p", "k")
t = t + 3600
local scores = db.read_scores("p", { "k" })
```

This removes a production code path that mutates module state and forces tests to be explicit about clock setup.

## User Stories

1. As a refer.nvim user, I want frecency to respond instantly to my keystrokes, so that picker refreshes are not noticeably delayed by frecency store reads.

2. As a refer.nvim user, I want my frecency history to persist across sessions, so that the on-disk JSON store remains the cross-session source of truth.

3. As a refer.nvim user running multiple Neovim sessions, I want each session's frecency writes to be durable, so that atomic write-through continues to protect my data.

4. As a refer.nvim user, I want frecency to remain in no-op mode for the rest of the session if the JSON store becomes unreadable, so that my picker never crashes.

5. As a refer.nvim maintainer, I want the db module to have no production code paths that mutate module-level state via per-call opts, so that the API surface is predictable and test-only mechanisms are isolated.

6. As a test author, I want deterministic clock injection through `configure()` only, so that tests control time explicitly without relying on per-call mutation.

7. As a test author, I want the mutable-closure pattern (`local t = 1000; configure({ clock_fn = function() return t end })`) to be the standard way to control time in tests, so that tests are explicit about when time advances.

8. As a refer.nvim user, I want frecency cleanup (`VimLeavePre`) to operate on the in-memory cache, so that cleanup reflects all in-session writes.

9. As a refer.nvim user, I want the frecency module's `_reset()` function to clear the in-memory cache, so that tests start from a clean state.

10. As a refer.nvim maintainer, I want changing `db_path` via `configure()` to invalidate the in-memory cache, so that the cache always corresponds to the current file path.

## Implementation Decisions

### Module changes

**`db.lua`** — The persistence module.

Add a module-local `cached_store` variable. `load_store()` populates it on first access and returns the cached value on subsequent calls. `record()` updates the cached store in memory and writes through to disk. `read_scores()` reads from the cached store. `cleanup()` operates on the cached store and conditionally writes through.

The cache entry shape is the same as the JSON store shape: `{ version = 1, providers = { ... } }`. A `nil` `cached_store` means "not yet loaded"; an empty but non-nil `{ version = 1, providers = {} }` means "loaded and empty".

On persistence failure, `cached_store` is set to `nil` (cache invalidated) and the module enters no-op mode, matching current behavior.

On `_reset()`, `cached_store` is set to `nil`, matching current reset semantics.

On `configure()` with a new `db_path`, `cached_store` is set to `nil`, so the next access re-reads from the new path.

`record()` updates `cached_store` in memory after a successful `load_store()`, then calls `write_store()` to persist. If `write_store()` fails, the module enters no-op mode and `cached_store` is set to `nil`.

`read_scores()` reads from `cached_store` (which `load_store()` populates). No additional I/O.

`cleanup()` calls `load_store()` to get the cached store, performs eviction logic, and calls `write_store()` only if changes were made.

**`init.lua`** — The public frecency module.

Remove the `clock_fn` field from the `opts` parameter type annotations for `record()` and `score()`. Remove the `clock_fn` field from the `opts` table passed to `db.read_scores()` inside `reorder()`. The `FrecencyConfig` type already has `clock_fn?` for `configure()`, which remains unchanged.

`configure()` continues to pass `clock_fn` through to `db.configure()`. No change.

### Clock injection removal details

**Remove from `db.lua`:** The `if opts and opts.clock_fn then clock_fn = opts.clock_fn end` blocks in `record()` and `read_scores()`. Remove the `[TEST-ONLY]` comments.

**Remove from `db.lua` type annotations:** The `opts` parameter for `record()` and `read_scores()` no longer includes `clock_fn`.

**Remove from `init.lua`:** The `clock_fn` field from the `@param opts` annotations on `record()` and `score()`. Remove `clock_fn` from the `opts` table constructed inside `reorder()` that is passed to `db.read_scores()`.

**Keep in `init.lua`:** The `clock_fn` field in `FrecencyConfig` and the pass-through to `db.configure()` inside `M.configure()`. Tests that currently pass `clock_fn` via `configure()` continue to work without changes.

### Cache semantics

- **Cache population:** `load_store()` checks `cached_store`. If `nil`, reads from disk, decodes JSON, normalizes, and stores the result in `cached_store`. Returns the cached value. If `cached_store` is non-nil, returns it directly without disk I/O.

- **Cache invalidation on db_path change:** `configure({ db_path = ... })` sets `db_path` and sets `cached_store = nil`, so the next `load_store()` re-reads from the new path.

- **Cache invalidation on persistence failure:** `enter_noop()` sets `cached_store = nil`. No further reads or writes are attempted.

- **Cache update on record:** After successfully loading the store (via `load_store()` which may have populated the cache), `record()` mutates `cached_store` in memory and then calls `write_store(cached_store)` to persist. If `write_store()` fails, `cached_store` is set to `nil` and the module enters no-op mode.

- **Cache invalidation on _reset():** `_reset()` sets `cached_store = nil` alongside existing resets.

- **Empty file / missing file:** When the JSON file does not yet exist, `load_store()` returns `default_store()` and caches it. The first `record()` call will write the store to disk. When the file exists but is empty or contains `{}`, `normalize_store()` handles it (setting `version = 1`, `providers = {}`) and caches the result.

- **No-op mode:** When the module is in no-op mode, `load_store()` returns `nil` immediately, bypassing the cache and disk. `record()` and `read_scores()` short-circuit before reaching `load_store()`. This matches current behavior.

### Concurrent session handling

The in-memory cache does not change concurrent session semantics. Each Neovim session has its own Lua state, so each session has its own `cached_store`. The last-writer-wins behavior of the JSON file is preserved: when session A writes, session B's cached copy may be stale, but this is already the case — session B never reads session A's mid-session writes. The cache simply avoids re-reading the same file within a single session.

### Test changes

All tests currently passing `clock_fn` via `opts` to `record()` and `read_scores()` must be refactored to use `configure()` instead. The standard pattern becomes:

```lua
local t = 1000000
db.configure({ db_path = path, clock_fn = function() return t end })
db.record("provider", "key")
t = t + 3600
local scores = db.read_scores("provider", { "key" })
```

For tests that need different timestamps for record vs. score, they advance the mutable `t` variable between calls rather than passing a different `clock_fn` per call.

Tests that currently use `setup_frecency()` helper functions that pass `clock_fn` through `configure()` already use the correct pattern and need only minor adjustments.

The `frecency_db_spec.lua`, `frecency_init_spec.lua`, `frecency_cleanup_spec.lua`, and `regression_frecency_e2e_spec.lua` files all use `clock_fn` via `opts` and will need updates. The `frecency_score_spec.lua` file does not use `clock_fn` (scoring is purely computational) and needs no changes.

The `_reset()` function in `db.lua` must also reset `cached_store = nil` so that tests don't leak state between test cases.

### Backward compatibility

No changes to the public `frecency` module API consumed by providers or the picker. The `record()`, `score()`, `reorder()`, `is_available()`, `status()`, `cleanup()`, and `resolve_key()` functions retain their signatures and behavior.

The `configure()` function's signature is unchanged — it already accepts `clock_fn` and passes it through to `db.configure()`.

The JSON store format is unchanged.

The only breaking change is the removal of the undocumented `opts.clock_fn` parameter from `db.record()` and `db.read_scores()`, and the `opts.clock_fn` parameter from `frecency.record()` and `frecency.score()`. These were marked `[TEST-ONLY]` and were never part of the documented public API (the `FrecencyConfig` type annotation for `configure()` existed, but `record()` and `score()` never documented `clock_fn` in their public-facing annotations).

## Testing Decisions

### What makes a good test

Tests should exercise observable behavior — not internal cache state. Tests verify that:

- `record()` persists data (observable via `read_scores()`).
- `read_scores()` returns correct scores after one or more records.
- Persistence failures enter no-op mode (observable via `is_available()` and `status()`).
- `_reset()` clears all state including the cache (observable via subsequent `read_scores()` returning empty).
- Changing `db_path` clears the cache (observable via `read_scores()` returning data from the new path).

Tests should not assert that `cached_store` is `nil` or non-nil — that is an implementation detail.

### Modules to test

- **`db.lua`**: Same test surface as today (record, read_scores, is_available, cleanup, _reset, JSON failure, no-op mode), plus new tests for cache behavior:
  - `read_scores()` returns data immediately after `record()` without re-reading the file.
  - Changing `db_path` via `configure()` causes the next `read_scores()` to read the new file.
  - `_reset()` clears the cache (subsequent `read_scores()` returns data from a fresh store).
  - Cache is invalidated on persistence failure (no-op mode).

- **`init.lua`**: Same test surface as today. The `configure()` pass-through of `clock_fn` is already tested. The removal of `opts.clock_fn` from `record()` and `score()` is tested by confirming that calling these functions without `opts` still works (the existing tests that pass `clock_fn` via `configure()` already cover this).

### Prior art

The existing `frecency_db_spec.lua` and `frecency_init_spec.lua` already test `record()` and `read_scores()` via `configure({ clock_fn = ... })` in `before_each` blocks. The pattern is established. The change is removing an alternative (per-call) injection path, not introducing a new one.

### New test cases

1. **Cache hit after record:** Verify that `read_scores()` returns data that was just `record()`ed without re-reading the JSON file. (Test by recording, then deleting the file — `read_scores()` should still return the recorded data from cache.)

2. **Cache invalidation on db_path change:** Configure with one path, record data, then configure with a different path — `read_scores()` should return data from the new path (or an empty store if no data exists there).

3. **Cache invalidation on _reset:** Record data, call `_reset()`, call `configure()` with the same path — `read_scores()` should read from disk (not return stale cached data).

4. **No stale data after persistence failure:** Enter no-op mode (corrupt file), verify `read_scores()` returns empty (cache invalidated), verify `record()` is a no-op.

5. **Clock injection through configure only:** Verify that `record()` and `read_scores()` use the clock set via `configure()` and do not accept `clock_fn` in `opts`. This is a negative test — calling `record("p", "k", { clock_fn = ... })` should either ignore the parameter or raise an error. (Implementation choice: silently ignore, since the parameter was undocumented.)

## Out of Scope

- SQLite or any non-JSON persistence backend.
- Cross-session cache synchronization (the last-writer-wins behavior is acceptable).
- Caching of score computation results (only store I/O is cached; scoring is always recomputed from store records).
- Changes to the `score.lua` module (scoring logic is unaffected).
- Changes to the `reorder()` or `sort_by_frecency()` functions.
- Changes to the picker integration or provider wiring.
- Changes to the `on_change` position-based scoring path.
- Adding a cache expiration or time-to-live mechanism.

## Further Notes

- The in-memory cache eliminates redundant JSON decoding for `read_scores()` calls during interactive picker use, which is the primary performance benefit. A typical workflow involves many `read_scores()` calls (one per keystroke during picker use) and fewer `record()` calls (one per selection).

- The `write_store()` on every `record()` call remains necessary for crash safety — the user's selection should be persisted to disk as soon as it happens, not batched for later write. The in-memory cache ensures the next `read_scores()` call does not need to re-read this data from disk.

- The clock injection cleanup is a pure API simplification. It removes a mutation path from production code without changing any functionality. Tests that use `configure({ clock_fn = ... })` already work correctly and represent the correct pattern going forward.

- This PRD follows the existing architecture decision (ADR 0001) for Frecency-enhanced sorting. The cache and clock cleanup are implementation improvements that do not change the Frecency contract, scoring formula, or persistence format.
