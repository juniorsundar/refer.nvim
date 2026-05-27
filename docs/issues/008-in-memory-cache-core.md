# Issue 8: In-memory cache core

### Parent

PRD: `docs/prd/frecency-cache-and-clock-cleanup.md`

### What to build

Add an in-memory cache to `db.lua` so that `read_scores()` no longer performs redundant JSON decoding on every picker keystroke (~20ms debounce). On first access, the store is loaded from disk and cached in a module-local `cached_store` variable. Subsequent `read_scores()` calls return the cached value without I/O. `record()` updates the in-memory cache and writes through to disk atomically.

In `db.lua`, add a module-local `cached_store` variable initialized to `nil`. Modify `load_store()` to check `cached_store` first: if non-nil, return it directly without disk I/O. If `nil`, read from disk, decode, normalize, store the result in `cached_store`, and return it. The cache entry shape is the same as the JSON store shape (`{ version = 1, providers = { ... } }`). A `nil` `cached_store` means "not yet loaded"; an empty but non-nil `{ version = 1, providers = {} }` means "loaded and empty".

Modify `record()` to update `cached_store` in memory after a successful `load_store()` call, then call `write_store(cached_store)` to persist. If `write_store()` fails, set `cached_store = nil` and enter no-op mode — this matches the current failure behavior but adds cache invalidation.

Modify `read_scores()` — no changes needed beyond what `load_store()` already provides, since it calls `load_store()` which will now return the cached value.

Invalidate the cache in `enter_noop()` by setting `cached_store = nil`. Invalidate in `_reset()` by setting `cached_store = nil`. The `cleanup()` function already calls `load_store()` which will return the cached store, so it automatically operates on in-memory data. When `cleanup()` calls `write_store()`, it passes the cached store reference, ensuring in-session writes are reflected.

New tests should verify:
- **Cache hit after record:** Record data, delete the on-disk file, call `read_scores()` — it should still return the recorded data from cache (proving no disk re-read).
- **No-op invalidation:** Trigger persistence failure (corrupt file or write failure), verify `read_scores()` returns empty (cache invalidated), verify `record()` is a no-op.
- **Reset clears cache:** Record data, call `_reset()`, call `configure()` with same path, `read_scores()` should read from disk (not return stale cached data).

This slice delivers the primary performance benefit of the PRD: `read_scores()` no longer re-reads and re-decodes the JSON store on every keystroke within a session.

### Acceptance criteria

- [x] `db.lua` has a module-local `cached_store` variable initialized to `nil`
- [x] `load_store()` checks `cached_store` first: if non-nil, returns it without disk I/O; if nil, reads from disk, decodes, normalizes, caches, and returns
- [x] `record()` updates `cached_store` in memory after `load_store()` and calls `write_store(cached_store)` to persist
- [x] `record()` sets `cached_store = nil` and enters no-op mode if `write_store()` fails
- [x] `read_scores()` benefits from cache via `load_store()` — no redundant JSON decoding on repeated calls within a session
- [x] `cleanup()` operates on the cached store (via `load_store()`) and writes through only if changes were made
- [x] `enter_noop()` sets `cached_store = nil` (cache invalidated on persistence failure)
- [x] `_reset()` sets `cached_store = nil` (cache invalidated on test teardown)
- [x] Cache hit test: after `record()`, delete the JSON file, `read_scores()` still returns recorded data from cache
- [x] No-op invalidation test: after persistence failure, `read_scores()` returns empty (no stale cache), `record()` is a no-op
- [x] Reset clears cache test: after `_reset()` and re-`configure()`, `read_scores()` reads from disk (not stale cache)
- [x] A missing JSON file (first access) returns `default_store()` and caches it
- [x] A corrupt or unreadable JSON file enters no-op mode and sets `cached_store = nil`
- [x] All existing tests pass (no behavioral regressions)

### Blocked by

- Issue 7 (Remove per-call `clock_fn` injection)
