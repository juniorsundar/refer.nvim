# ADR 0001: Frecency-Enhanced Sorting for the lua Sorter

## Status

Accepted

## Context

refer.nvim's built-in `lua` sorter performs fuzzy matching but has no history-based ranking. Items that a user selects frequently still appear in purely text-match order every session. Other sorters (`blink`, `mini`, `native`) either have their own ranking or delegate to external engines. The `lua` sorter has no built-in recency or frequency signal.

## Decision

Add a frecency module (`lua/refer/frecency/`) that records item selections and reorders results for the `lua` sorter using frequency-weighted recency (Mozilla-style bucketed scoring).

Key design choices:

1. **Persistence**: SQLite via `vim.sqlite` (Neovim 0.10+). Schema: `(provider, item_key, selected_count, last_selected_at)`. Graceful no-op degradation if SQLite is unavailable.

2. **Scope**: Per-provider, opt-out by default. Each provider tracks its own frecency independently via a `provider` option on `ReferOptions`.

3. **Integration**: Post-sort reordering. The existing sorter runs first, then frecency reorders items within score-based neighborhoods (~10 items). The `lua` sorter will expose numeric fuzzy scores so frecency can group by match quality rather than arbitrary position boundaries.

4. **Formula**: `score = count / (age_bucket + 1)` with configurable bucket weights (last hour, last day, last week, older).

5. **Recording**: On confirm/accept only — explicit picker selections increment frecency counts.

6. **Key strategy**: Built-in strategies (`"text"`, `"filepath"`, `"filepath_with_lnum"`) plus custom function support. Default is `"text"`.

7. **Empty query**: When no search term is entered, items are sorted entirely by frecency score.

8. **Sorter scope**: Hardcoded to `lua` only. `blink`, `mini`, `native`, and custom sorters are not affected.

9. **Eviction**: Lazy on read; periodic vacuum on Neovim exit caps per-provider at ~10,000 entries.

## Consequences

- **Positive**: Users of the `lua` sorter get history-based ranking without external dependencies (SQLite is built into Neovim 0.10+). Most-used items surface immediately on empty query. Fuzzy match quality remains the primary signal, preventing weak matches from jumping to the top.

- **Negative**: Adds a SQLite dependency path (gracefully degraded). The `lua` sorter's behavior diverges from other sorters — the same query on `lua` vs `blink` may produce different orderings due to frecency. This is intentional: sorters with built-in ranking don't need our frecency layer.

- **Risk**: The `lua` sorter currently returns `string[]` only. Exposing scores requires internal changes to `fuzzy.filter()` to preserve score data when the `lua` sorter is active. This is a limited-scope change but touches a core path.

## Alternatives Considered

- **JSON file persistence**: Simpler but scales poorly and lacks atomic writes.
- **Global frecency**: Cross-provider tracking risks confusing the same text appearing in different contexts.
- **Hybrid score formula**: Would require all sorters to expose numeric scores, changing the `ReferSorterFn` interface.
- **Top-N frecency promotion**: Too aggressive — weak matches could jump to position 1.
- **Configurable sorter scope**: More flexible, but shifts optimization burden to users for custom sorters.
