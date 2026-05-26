# ADR 0001: Frecency-Enhanced Sorting for the lua Sorter

## Status

Accepted

## Context

refer.nvim's built-in `lua` sorter performs fuzzy matching but has no history-based ranking. Items that a user selects frequently still appear in purely text-match order every session. Other sorters (`blink`, `mini`, `native`) either have their own ranking or delegate to external engines. The `lua` sorter has no built-in recency or frequency signal.

Frecency history needs local persistence so ranking can improve across Neovim sessions. Neovim does not provide a standard built-in SQLite API, so a SQLite-only implementation would either require an external dependency or silently disable Frecency for normal installs.

## Decision

Add a frecency module (`lua/refer/frecency/`) that records item selections and reorders results for the `lua` sorter using frequency-weighted recency (Mozilla-style bucketed scoring).

Key design choices:

1. **Persistence**: Store Frecency records in a JSON file. The default path is `stdpath("data") .. "/refer/frecency.json"`, configurable via `db_path`. The JSON shape is versioned and grouped by Provider:

   ```json
   {
     "version": 1,
     "providers": {
       "buffers": {
         "/abs/path/file.lua": {
           "selected_count": 3,
           "last_selected_at": 1234567890.123
         }
       }
     }
   }
   ```

   Writes use an atomic temp-file + rename flow. If the store cannot be read, decoded, or written, Frecency enters session no-op mode and leaves the existing file untouched.

2. **Scope**: Per-provider, opt-out by default. Each provider tracks its own frecency independently via a `provider` option on `ReferOptions`.

3. **Integration**: Post-sort reordering. The existing sorter runs first, then frecency reorders items within score-based neighborhoods (~10 items). The `lua` sorter will expose numeric fuzzy scores so frecency can group by match quality rather than arbitrary position boundaries.

4. **Formula**: `score = count / (age_bucket + 1)` with configurable bucket weights (last hour, last day, last week, older).

5. **Recording**: On confirm/accept only — explicit picker selections increment frecency counts.

6. **Key strategy**: Built-in strategies (`"text"`, `"filepath"`, `"filepath_with_lnum"`) plus custom function support. Default is `"text"`.

7. **Empty query**: When no search term is entered, items are sorted entirely by frecency score.

8. **Sorter scope**: Hardcoded to `lua` only. `blink`, `mini`, `native`, and custom sorters are not affected.

9. **Eviction**: Lazy on read; periodic cleanup on Neovim exit caps per-provider entries at ~10,000 and rewrites the JSON store.

## Consequences

- **Positive**: Users of the `lua` sorter get history-based ranking with no external dependencies. Most-used items surface immediately on empty query. Fuzzy match quality remains the primary signal, preventing weak matches from jumping to the top.

- **Positive**: The persistence format is inspectable and portable. Tests can exercise real persistence behavior without mocking a native dependency.

- **Negative**: JSON persistence rewrites the store as a whole. This is acceptable for the planned per-provider cap (~10,000 entries), but it is less scalable than SQLite for very large histories.

- **Negative**: JSON lacks database-level locking and transactions. Atomic temp-file + rename reduces the risk of truncated writes, but concurrent Neovim sessions may still race. The last writer wins.

- **Risk**: The `lua` sorter currently returns `string[]` only. Exposing scores requires internal changes to `fuzzy.filter()` to preserve score data when the `lua` sorter is active. This is a limited-scope change but touches a core path.

## Alternatives Considered

- **SQLite via plugin dependency**: More scalable and queryable, but would require users to install an additional plugin/native library path for Frecency to work.
- **SQLite via nonexistent `vim.sqlite`**: Rejected because standard Neovim does not provide this API.
- **Global frecency**: Cross-provider tracking risks confusing the same text appearing in different contexts.
- **Hybrid score formula**: Would require all sorters to expose numeric scores, changing the `ReferSorterFn` interface.
- **Top-N frecency promotion**: Too aggressive — weak matches could jump to position 1.
- **Configurable sorter scope**: More flexible, but shifts optimization burden to users for custom sorters.
