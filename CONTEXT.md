# refer.nvim — Domain Context

## Glossary

- **Frecency**: A composite ranking score combining frequency (how often an item is selected) and recency (how recently it was selected). Items accessed more often and more recently rank higher. This is the standard interpretation used by Telescope, ctrlp, and fzf-style tools.
- **Sorter**: A function that takes a list of strings and a query, and returns the strings in relevance order. Refer ships four built-in sorters: `blink`, `mini`, `native`, and `lua`.
- **ReferItem**: The canonical item shape `{ text = string, data = any|nil }`. The `text` field is the display string fed to sorters; `data` is an opaque payload carried alongside.
- **Provider**: A source of items for the picker (e.g., buffers, commands, help tags, files, old files, LSP references).

## Decisions

- **Frecency definition**: Frequency-weighted recency — a composite score where items selected more often and more recently rank higher.
- **Persistence**: SQLite via `vim.sqlite` (Neovim 0.10+ built-in). Schema: `provider | item_key | selected_count | last_selected_at`.
- **Frecency scope**: Per-provider. Each provider (buffers, commands, files, etc.) tracks its own frecency independently.
- **Frecency integration**: Post-sort reordering. The existing sorter produces fuzzy-matched results, then frecency scores reorder them as a second pass.
- **Frecency formula**: Mozilla-style bucketed scoring. `score = count / (age_bucket + 1)` where age buckets assign higher multipliers to more recent selections (e.g., last hour, last day, last week, older). Configurable bucket weights.
- **Frecency recording**: On confirm/accept only. Only explicit picker selections (Enter, double-click, etc.) increment frecency counts.
- **Frecency key strategy**: Provider-specific key function with built-in strategies. Providers reference a strategy by name (`"text"`, `"filepath"`, `"filepath_with_lnum"`) or supply a custom function. Default is `"text"`. This avoids per-provider boilerplate.
- **Frecency default**: Opt-out. Frecency boosts are active for all providers unless explicitly disabled per-provider.
- **Frecency boost method**: Neighborhood-based reordering. Fuzzy-match quality is the primary signal; frecency reorders items within groups of similar match quality (neighborhoods of ~10). This prevents weak textual matches from jumping above strong ones.
- **Frecency on empty query**: Yes. When no search term is entered, the full item list is sorted entirely by frecency score. The most frequently/recently used items appear at the top without typing.
- **Frecency eviction**: Lazy eviction on read. Stale DB entries are skipped at query time; a periodic vacuum (on Neovim exit or every N sessions) removes orphaned rows and caps per-provider entries at ~10,000.
- **Frecency sorter scope**: Hardcoded to the `lua` sorter only. Inactive for `blink`, `mini`, `native`, and any custom sorters. If a user brings their own sorter, frecency integration is their responsibility.
- **Module structure**: `lua/refer/frecency/` directory with `init.lua` (public API: record, score, reorder), `db.lua` (SQLite persistence), `score.lua` (bucketed scoring + neighborhood reordering).
- **Provider identity**: New `provider` option on `ReferOptions`. Builtin providers pass `provider = "buffers"` etc. If absent, no frecency is recorded or applied.
- **SQLite unavailable**: Graceful degradation. If `vim.sqlite` is absent (Neovim <0.10 or no SQLite), frecency enters a no-op mode: `record()` does nothing, `reorder()` returns items unchanged. A one-time `DEBUG`-level notice is logged.
- **Score exposure**: The `lua` sorter will expose numeric fuzzy scores (already computed by `simple_fuzzy_score`) so frecency can group items by match-quality neighborhoods rather than arbitrary position boundaries.
