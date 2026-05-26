# Issue 1: Frecency deep module — scoring, JSON persistence, and public API

### Parent

PRD: `docs/prd/frecency-enhanced-lua-sorting.md`

### What to build

Implement the Frecency deep module as three internal files behind a public facade:

- **`lua/refer/frecency/score.lua`** — Mozilla-style bucketed scoring (`score = count / (age_bucket + 1)`), key strategy resolution (`text`, `filepath`, `filepath_with_lnum`, custom function), neighborhood-based reordering, and empty-query full-sort ordering. Timestamps must be injectable for deterministic tests. Bucket boundaries and multipliers should be configurable but have sensible defaults. Neighborhood size defaults to 10. When scores are equal within a neighborhood, preserve original order. When items have no Frecency score, preserve their original order after scored items. Handle edge cases: future timestamps, zero/negative age, and missing timestamps (treat as lowest recency bucket).

  Default bucket boundaries and divisors (age is `now - last_selected_at` in seconds):
  - Bucket 0: age < 3600 (last hour) — divisor 1
  - Bucket 1: age < 86400 (last day) — divisor 2
  - Bucket 2: age < 604800 (last week) — divisor 4
  - Bucket 3: age >= 604800 (older) — divisor 8
  Score formula: `score = count / divisor`. Equivalently, `divisor = 2^bucket_index`.
  Boundaries are half-open: `[0, 3600)`, `[3600, 86400)`, `[86400, 604800)`, `[604800, ∞)`.

  The `reorder(provider, items, opts)` function receives fuzzy scores as a separate map at `opts.scores`, keyed by item text (the same key used for deduplication in `fuzzy.filter`). When `opts.scores` is nil (non-lua sorter paths), no neighborhood grouping is applied and items are returned unchanged unless the facade is explicitly handling empty-query full Frecency ordering. When `opts.scores` is present, items are grouped into neighborhoods of similar fuzzy score and reordered within each neighborhood by Frecency score.

- **`lua/refer/frecency/db.lua`** — JSON persistence. Store shape:

  ```json
  {
    "version": 1,
    "providers": {
      "provider_name": {
        "item_key": {
          "selected_count": 3,
          "last_selected_at": 1234567890.123
        }
      }
    }
  }
  ```

  Upsert on record (increment `selected_count`, update `last_selected_at`). Read multiple keys for a provider. Store file defaults to `stdpath("data") .. "/refer/frecency.json"`, with configurable `db_path` override for testing. Directory is created on first use. Writes use an atomic temp-file + rename flow. If the JSON file is missing, start from an empty store. If the JSON file exists but cannot be read or decoded, log a one-time WARN, leave the file untouched, and enter session no-op mode. When a runtime write fails (permission error, rename failure, invalid path, corrupt existing file discovered on read), log a one-time WARN and switch to no-op mode for the rest of the session. When a read fails, return empty results so the picker still works.

- **`lua/refer/frecency/init.lua`** — Public facade exposing: `configure(opts)`, `record(provider, item_key)`, `score(provider, item_keys)`, `reorder(provider, items, opts)`, `resolve_key(item, strategy)`, `is_available()`. Persistence and scoring internals remain hidden behind this interface. A `cleanup()` function will be added in Issue 6 when eviction behavior is implemented.

  `score(provider, item_keys)` returns a table mapping `item_key → frecency_score_number`. Keys without frecency records are absent from the table. Callers check for key presence to determine whether an item has a score.

  `configure(opts)` accepts: `db_path` (string, defaults to `stdpath('data') .. '/refer/frecency.json'`), `buckets` (table, default bucket boundaries and multipliers), `neighborhood_size` (number, defaults to 10), `clock_fn` (function, defaults to `vim.loop.hrtime` or equivalent — injectable for deterministic tests). `refer.setup({ frecency = { ... } })` calls `frecency.configure(opts)` internally.

All three components must have unit tests (Plenary/Busted style) covering:
- score: bucket calculation, score ordering, tie handling, empty-query sorting, neighborhood reordering, key strategy resolution, fallback behavior, clock edge cases
- db: initialization, upsert, multi-key reads, provider isolation, missing-store empty behavior, corrupt JSON no-op behavior, atomic write failure handling
- init: public API delegation, key strategy dispatch

This slice delivers no picker integration — the module is testable in isolation.

### Acceptance criteria

- [x] `score.lua` computes Mozilla-style bucketed Frecency scores correctly with injectable timestamps, using default boundaries: `[0,3600)` → divisor 1, `[3600,86400)` → divisor 2, `[86400,604800)` → divisor 4, `[604800,∞)` → divisor 8; `score = count / divisor`
- [x] `score.lua` performs neighborhood-based reordering: items are reordered only within groups of similar fuzzy score, original order preserved for equal Frecency scores and items without scores
- [x] `score.lua` sorts by Frecency alone when query is empty
- [x] `score.lua` resolves `text`, `filepath`, `filepath_with_lnum` key strategies and custom functions; falls back to `text` when `filepath` data is absent
- [x] When `provider` is nil/empty or `item_key` resolves to nil, `record()` is a silent no-op, `score()` returns an empty result, and `reorder()` returns items unchanged — no logging, no error
- [x] `filepath` strategy normalizes relative paths to absolute paths via `vim.fn.fnamemodify(path, ':p')`
- [x] `filepath_with_lnum` strategy concatenates absolute path and line number; falls back to `text` when either `data.filename` or `data.lnum` is absent
- [x] Two ReferItems with the same display text but different `data.filename` resolve to different Frecency keys under `filepath` strategy
- [x] Custom key function returning nil falls back to `text` strategy
- [x] `db.lua` initializes a versioned JSON store at `stdpath("data") .. "/refer/frecency.json"`, creates the directory if needed, and supports `db_path` override for testing
- [x] `db.lua` upserts on record (increments `selected_count`, updates `last_selected_at`)
- [x] `db.lua` reads scores for multiple item keys per provider, returns a map `item_key → frecency_score_number`; keys without records are absent; returns empty map when the store is missing or unavailable
- [x] Missing-score items in `reorder()` are preserved in original order after scored items; items with equal Frecency scores in the same neighborhood preserve their original fuzzy-sort order
- [x] `db.lua` writes atomically via temp file + rename
- [x] `db.lua` enters session no-op mode after corrupt/unreadable JSON or runtime write failures (one-time WARN), leaving corrupt files untouched
- [x] `init.lua` exposes `configure`, `record`, `score`, `reorder`, `resolve_key`, `is_available` as the public interface; internals are not exported
- [x] `configure(opts)` accepts `db_path`, `buckets`, `neighborhood_size`, and `clock_fn`; `refer.setup()` passes `frecency` options through to `frecency.configure()`
- [x] Unit tests pass for score, db, and init modules
- [x] No picker behavior changes — existing tests still pass

### Blocked by

None — can start immediately.
