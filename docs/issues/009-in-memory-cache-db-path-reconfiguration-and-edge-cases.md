# Issue 9: In-memory cache — db_path reconfiguration and edge cases

### Parent

PRD: `docs/prd/frecency-cache-and-clock-cleanup.md`

### What to build

Complete the in-memory cache by adding invalidation when `configure()` changes `db_path`, and add comprehensive edge-case test coverage for the cache behavior alongside the mutable-closure clock pattern.

In `db.lua`'s `configure()` function, when `opts.db_path` is provided, set `cached_store = nil` alongside the existing `db_path = opts.db_path` assignment. This ensures that when the store path changes, the next `load_store()` re-reads from the new file rather than returning stale cached data from the old file.

In `init.lua`, update the `configure()` pass-through comment (if any) to note that `db_path` changes invalidate the in-memory cache.

Add edge-case tests that exercise the full cache lifecycle:

- **db_path change invalidates cache:** Configure with path A, record data, configure with path B, verify `read_scores()` returns data from path B (empty store, not stale data from path A). Configure back to path A, verify `read_scores()` returns the original data from path A (re-read from disk, not from a stale cache).

- **Persistence failure clears cache:** Write a corrupt file, trigger a read, verify no-op mode, verify `cached_store` is nil (observable via `read_scores()` returning empty and `is_available()` returning false). Verify that no stale data from a previous session is returned.

- **Mutable-closure clock with cache:** Use the `configure({ clock_fn = function() return t end })` pattern with `t` advanced between calls. Record at time T, advance to T+3600, call `read_scores()`. Verify scores reflect the time difference, proving that the cache stores the data correctly and the clock function is used consistently.

- **Cleanup reflects in-session writes:** Record data during a session, call `cleanup()`, verify the on-disk store contains the recorded data (cleanup wrote through the cached store). Verify cleanup operates on the in-memory cache (not re-reading from disk).

- **Empty file / missing file caching:** Verify that when the JSON file does not yet exist, `load_store()` returns `default_store()` and caches it. Verify that the first `record()` call creates the file. Verify that an empty or `{}` file is normalized and cached.

This slice completes the cache correctness guarantees: reconfiguration invalidation, edge cases, and proof that the mutable-closure clock pattern works correctly with the cached store.

### Acceptance criteria

- [x] `db.configure()` sets `cached_store = nil` when `opts.db_path` is provided, ensuring the next access reads from the new path
- [x] Changing `db_path` via `configure()` causes `read_scores()` to return data from the new file, not stale cache from the old file
- [x] Switching `db_path` back to the original path re-reads from disk (no stale cache)
- [x] Persistence failure (corrupt file, unreadable file, write failure) sets `cached_store = nil`; subsequent `read_scores()` returns empty, `is_available()` returns false
- [x] No stale data is returned after a persistence failure — the cache does not retain pre-failure data
- [x] Mutable-closure clock pattern (`local t; configure({ clock_fn = function() return t end })`) works correctly with the cached store: recording at time T and reading at T+3600 produces the expected frecency scores
- [x] `cleanup()` writes through the cached store to disk when changes are made during a session
- [x] Missing JSON file: `load_store()` returns and caches `default_store()`; first `record()` call creates the file
- [x] Empty or `{}` JSON file: `normalize_store()` handles it correctly and caches the result
- [x] All existing tests pass (no behavioral regressions)
- [x] New edge-case tests cover: db_path change, persistence failure clearing cache, mutable-closure clock with cache, cleanup write-through, empty/missing file edge cases

### Blocked by

- Issue 8 (In-memory cache core)
