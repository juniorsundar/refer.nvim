# PRD: Frecency-Enhanced Lua Sorting in refer.nvim

## Problem Statement

refer.nvim currently has a built-in `lua` sorter that performs fuzzy matching but does not learn from user selections. A user can repeatedly choose the same item from a Provider, but that item will continue to appear according to text-match quality alone. This makes the `lua` sorter feel less capable than modern picker experiences that surface recently and frequently used items.

The project already supports multiple Sorters, including external or native engines that may have their own ranking behavior. The gap is specifically in refer.nvim's built-in `lua` sorter: it lacks a persistent Frecency signal and therefore cannot prioritize items that are repeatedly useful to the user.

## Solution

Add a Frecency system for the built-in `lua` sorter only. The system records explicit picker selections per Provider, persists selection history with SQLite when available, computes a frequency-weighted recency score, and uses that score to reorder fuzzy-matched results after the existing fuzzy matching pass.

From the user's perspective:

- The `lua` sorter remains a normal fuzzy sorter.
- When a user selects items over time, those items begin to surface higher in future results.
- When the query is empty, the picker can show the most useful items first.
- Textual match quality remains the primary ranking signal when a query is present.
- Frecency is active only for the built-in `lua` sorter and only for Providers that identify themselves.
- If SQLite is unavailable, the feature degrades gracefully and the picker continues to work without Frecency.

## User Stories

1. As a refer.nvim user, I want the built-in `lua` sorter to remember items I select often, so that my most useful items become easier to reach.

2. As a refer.nvim user, I want recently selected items to rank higher than stale items, so that the picker adapts to my current work.

3. As a refer.nvim user, I want frequently selected items to rank higher than one-off selections, so that repeated habits are reflected in search results.

4. As a refer.nvim user, I want Frecency to combine frequency and recency, so that the ranking favors items I use often and have used recently.

5. As a refer.nvim user, I want Frecency to persist across Neovim sessions, so that the picker keeps learning over time.

6. As a refer.nvim user, I want the picker to remain usable if persistence is unavailable, so that my workflow is never blocked by the Frecency layer.

7. As a refer.nvim user, I want the empty-query picker state to show frecent items first, so that I can often select what I need without typing.

8. As a refer.nvim user, I want fuzzy text matching to remain the primary signal when I type a query, so that bad textual matches do not jump above good textual matches.

9. As a refer.nvim user, I want Frecency to reorder only similarly good fuzzy matches, so that history improves ranking without making results feel random.

10. As a refer.nvim user, I want the `lua` sorter to support Frecency without changing how I call the picker, so that the feature feels integrated.

11. As a refer.nvim user, I want Blink's sorter behavior to remain independent, so that external sorter engines continue to own their own optimization choices.

12. As a refer.nvim user, I want Mini's sorter behavior to remain independent, so that refer.nvim does not layer unexpected ranking behavior on top of external sorters.

13. As a refer.nvim user, I want the native Vim sorter behavior to remain independent, so that native sorting remains predictable.

14. As a refer.nvim user with a custom Sorter, I want refer.nvim not to apply hidden Frecency logic to my custom Sorter, so that my Sorter remains responsible for its own ranking semantics.

15. As a refer.nvim user, I want buffer selections to be tracked separately from command selections, so that unrelated Providers do not contaminate each other's rankings.

16. As a refer.nvim user, I want file selections to be tracked separately from help tag selections, so that each Provider can learn its own usage pattern.

17. As a refer.nvim user, I want two Providers with similar display text to maintain separate Frecency histories, so that the same text in different contexts does not produce confusing ranking changes.

18. As a refer.nvim user, I want repeated selection of a file-like item to use the file's stable identity, so that display formatting changes do not unnecessarily reset history.

19. As a refer.nvim user, I want line-specific locations to be tracked distinctly when appropriate, so that references or location-like items can learn at the right granularity.

20. As a refer.nvim user, I want simple text items to use their display text as the Frecency key, so that simple Providers do not need custom identity logic.

21. As a Provider author, I want built-in Frecency key strategies, so that I do not have to rewrite common identity extraction boilerplate.

22. As a Provider author, I want to choose a Frecency key strategy by name, so that my Provider can opt into the correct identity model with minimal code.

23. As a Provider author, I want to supply a custom key function when built-in strategies are insufficient, so that unusual Provider item shapes can still participate in Frecency.

24. As a Provider author, I want Frecency to do nothing when no Provider identity is supplied, so that ad hoc pickers do not accidentally write anonymous history.

25. As a plugin maintainer, I want Frecency hidden behind a small public module interface, so that persistence and scoring details can change without spreading complexity through the codebase.

26. As a plugin maintainer, I want SQLite logic isolated from scoring logic, so that database behavior can be tested and maintained separately.

27. As a plugin maintainer, I want scoring logic isolated from picker action handling, so that ranking behavior can be tested without UI setup.

28. As a plugin maintainer, I want the existing Sorter contract to remain stable for external Sorters, so that existing custom Sorters do not break.

29. As a plugin maintainer, I want the `lua` sorter to expose scores internally, so that Frecency can group results by match quality without changing every Sorter.

30. As a plugin maintainer, I want Frecency recording to happen only on explicit accept actions, so that accidental cursor movement or typing does not pollute history.

31. As a plugin maintainer, I want marked-item selection to record each accepted item, so that batch actions still reflect intentional user choices.

32. As a plugin maintainer, I want raw input confirmation not to create Provider item history unless it corresponds to an actual selected ReferItem, so that arbitrary typed text does not pollute Provider Frecency.

33. As a plugin maintainer, I want stale Frecency entries to be harmless at query time, so that deleted files or unavailable items do not affect visible ranking.

34. As a plugin maintainer, I want periodic cleanup to cap database growth, so that long-term use does not create unbounded local state.

35. As a plugin maintainer, I want the Frecency store to be per-user local state, so that repository behavior remains deterministic and no user history enters source control.

36. As a plugin maintainer, I want a graceful no-op mode when SQLite is unavailable, so that tests and older environments can still exercise the picker.

37. As a plugin maintainer, I want documentation to explain that Frecency applies only to the `lua` sorter, so that users understand why other Sorters behave differently.

38. As a plugin maintainer, I want health or diagnostics to make Frecency availability understandable, so that users can debug missing SQLite support without reading code.

39. As a tester, I want deterministic scoring tests with injected timestamps, so that Frecency behavior can be tested without depending on wall-clock time.

40. As a tester, I want integration tests around filtering and selection, so that the feature is validated through observable picker behavior rather than private implementation details.

41. As a user who cycles Sorters, I want Frecency to apply when the active Sorter is `lua` and stop applying when the active Sorter changes away from `lua`, so that sorter cycling remains predictable.

42. As a user who disables Frecency for a Provider, I want that Provider to retain normal `lua` fuzzy behavior, so that opt-out is safe and localized.

43. As a user upgrading refer.nvim, I want the feature to require no manual migration, so that existing configuration continues to work.

44. As a user upgrading refer.nvim, I want initial Frecency history to start empty, so that results only change after I begin making selections.

45. As a future contributor, I want the accepted Frecency decisions captured in project documentation, so that implementation work follows the same domain language and constraints.

46. As a refer.nvim user, I want Frecency to track file identity by absolute path, so that opening the same file from different directories or with different display formatting still accumulates history correctly.

47. As a refer.nvim user, I want to globally disable Frecency recording and reordering, so that I can turn off the feature entirely without disabling each Provider individually.

48. As a refer.nvim user, I want the picker to remain responsive even if the Frecency database is locked or slow, so that database latency never blocks the UI.

49. As a refer.nvim user running an async Provider like files or live grep, I want Frecency to still work for items I have selected, so that async Providers participate in history when they have results.

50. As a plugin maintainer, I want the Frecency system to handle database corruption or write failures gracefully, so that a damaged store does not crash the picker or lose all history.

51. As a plugin maintainer, I want Sorter identity to be tracked by name rather than by function reference, so that Frecency activation can be determined reliably even after sorter cycling.

## Implementation Decisions

### Module architecture

- Build a Frecency module as a deep module with a small public interface. The public surface should expose operations for recording selections, computing or retrieving Frecency scores, reordering matched ReferItems, resolving item keys, checking availability, and performing cleanup. Persistence, scoring, key extraction, and cleanup should remain internal details.

- Split Frecency internals into persistence and scoring responsibilities. The persistence component owns SQLite availability, schema initialization, writes, reads, no-op degradation, and vacuuming. The scoring component owns bucketed score calculation, key strategy application, empty-query ordering, and neighborhood-based reordering.

### Persistence

- Persist Frecency with SQLite through Neovim's built-in SQLite support. The store records Provider identity, item key, selected count, and last selected timestamp. The Provider identity and item key form the logical unique identity of a Frecency record.

- Store the database at `stdpath("data") .. "/refer/frecency.db"`. The directory must be created on first use if it does not exist.

- Handle SQLite runtime failures gracefully. If a write fails (locked DB, permission error, corrupt file, schema mismatch), log a one-time `WARN` message and continue in no-op mode for the rest of the session. Do not crash or block the picker. If a read fails, return empty results so the picker still functions with no Frecency data.

- Gracefully degrade when SQLite is unavailable. In degraded mode, recording is a no-op and reordering returns its input unchanged. The rest of refer.nvim must continue to work.

### Scoring formula

- Use Mozilla-style bucketed Frecency scoring: `score = count / (age_bucket + 1)`. Age buckets assign multipliers based on when the item was last selected: items selected within the last hour receive the highest multiplier, items within the last day receive a lower multiplier, items within the last week receive a lower one, and older items receive the lowest. Bucket boundaries and multipliers are configurable via setup options but have sensible defaults.

- Evict lazily. Stale entries do not appear in results unless a Provider presents a matching item. Periodic vacuuming on Neovim exit removes orphaned rows and caps per-Provider storage at approximately 10,000 entries.

### Sorter detection

- Apply Frecency only when the active Sorter is the built-in `lua` sorter. Frecency is inactive for Blink, Mini, native Vim sorting, and custom Sorters. Custom Sorter authors remain responsible for their own optimization and ranking behavior.

- Determine whether the active Sorter is the built-in `lua` sorter by name, not function reference. The Picker already tracks `available_sorters` by name and `sorter_idx`. When Frecency needs to decide whether to activate, it compares the current sorter name against `"lua"`. After a Sorter cycle, the name is re-evaluated, so Frecency applies only during cycles where the `lua` Sorter is active.

- Preserve the public custom Sorter contract. Existing Sorters continue to accept items and a query and return ordered matches. Internal score exposure is limited to the built-in `lua` sorter path.

- Extend the built-in `lua` sorter path so numeric fuzzy scores can be preserved internally. These scores are used to form match-quality neighborhoods for Frecency reordering.

### Post-sort reordering

- Use post-sort reordering. The `lua` sorter first filters and ranks by fuzzy match quality. Frecency then reorders results within groups of similar fuzzy score (neighborhoods of approximately 10 items). This keeps fuzzy relevance primary while allowing history to break ties and near-ties.

- When two or more items have the same Frecency score within a neighborhood, preserve their original fuzzy-sort order.

- For non-empty queries where items have no Frecency score, preserve the original fuzzy-sort order.

- For empty queries, sort the full Provider item set by Frecency. Items without Frecency records remain visible and should preserve their original Provider order after scored items.

### Provider identity and configuration

- Track Frecency per Provider. Builtin Providers must pass explicit Provider identity through picker options. Pickers without Provider identity do not record or apply Frecency.

- Add a `frecency` option group to `ReferOptions`. When present, it enables Frecency for that Picker. The option group contains:
  - `provider` (string, required for Frecency to activate): the Provider identity, e.g. `"buffers"`, `"commands"`, `"help_tags"`.
  - `key_strategy` (string, one of `"text"`, `"filepath"`, `"filepath_with_lnum"`, or a custom function): how to extract the Frecency key from a ReferItem. Defaults to `"text"`.
  - `enabled` (boolean, defaults to `true`): allows a Provider to opt out of Frecency even when a Provider identity is present.

- Add a global `frecency` option in `setup()` for top-level configuration:
  - `enabled` (boolean, defaults to `true`): global kill switch for all Frecency recording and reordering.
  - `db_path` (string, optional): override the database file path. Defaults to `stdpath("data") .. "/refer/frecency.db"`. Useful for testing.
  - `buckets` (table, optional): override recency bucket boundaries and multipliers. Defaults to sensible values (last hour, last day, last week, older).
  - `neighborhood_size` (number, defaults to `10`): number of items in a match-quality neighborhood for post-sort reordering.

- Builtin Provider Frecency coverage:
  - `buffers`: Provider `"buffers"`, key strategy `"filepath"`
  - `old_files`: Provider `"old_files"`, key strategy `"filepath"`
  - `files` (sync): Provider `"files"`, key strategy `"filepath"`
  - `commands`: Provider `"commands"`, key strategy `"text"`
  - `help_tags`: Provider `"help_tags"`, key strategy `"text"`
  - `macros`: Provider `"macros"`, key strategy `"text"`
  - Provider identity is not passed for LSP references, live grep, grep word, or lines Providers because these are ephemeral (items change per query, per buffer, or per session). Providers not listed above do not receive Provider identity and therefore do not participate in Frecency.

### Key strategies

- Built-in strategies are `text`, `filepath`, and `filepath_with_lnum`. Providers may select a named strategy or supply a custom function. The default strategy is `text`.

- The `filepath` strategy extracts the absolute file path from `ReferItem.data.filename`. If `data.filename` is not present or nil, the strategy falls back to `ReferItem.text`. Paths are normalized to absolute paths before being used as Frecency keys, so that the same file reached from different working directories accumulates history correctly.

- The `filepath_with_lnum` strategy concatenates the absolute file path and line number from `ReferItem.data` as `filename:lnum`, falling back to `ReferItem.text` if `data.filename` or `data.lnum` is absent.

- When multipleReferItems within the same Provider have identical display text but distinct `data` identities (e.g., two buffers with the same basename), the key strategy must resolve to different Frecency keys. The `filepath` strategy handles this by using the full path. The `text` strategy does not and may collapse distinct items — Providers with potential duplicate display text should not use `"text"`.

### Recording semantics

- Record Frecency only on explicit accept actions. The actions that trigger recording are:
  - `select_entry`: records the selected ReferItem.
  - `edit_entry`, `split_entry`, `vsplit_entry`, `tab_entry`: records the selected ReferItem (they call `open_entry` which closes the picker and navigates).
  - `open_marked`: records each marked ReferItem individually.

- Actions that do **not** trigger recording:
  - `select_input`: records raw typed text only if it corresponds to a ReferItem in `current_matches`.
  - `complete_selection`: completes the query but does not close the picker.
  - `refresh`, `next_item`, `prev_item`, `toggle_mark`, `cycle_sorter`, `toggle_preview`, `close`: navigation and UI actions.

- Recording happens before the picker closes, so that the selected item is still available in `current_matches`.

- The `select_input` action resolves the current input against `current_matches`. If the input matches an existing ReferItem, that item is recorded. If the input is arbitrary text with no matching item, nothing is recorded.

### Async and on_change Providers

- Frecency applies to all Providers that pass Provider identity, whether synchronous or asynchronous.
  - For synchronous Providers (buffers, commands, help_tags, macros, old_files), empty-query Frecency can reorder the full item set because items are available immediately.
  - For asynchronous Providers (files via `pick_async`, live grep), items arrive incrementally. Frecency reorders whatever results are currently displayed. Empty-query behavior depends on the Provider: if the Provider returns all items on an empty query, Frecency can reorder them. If the Provider requires a minimum query length before returning results, Frecency applies only when results arrive.

- The `commands` Provider uses `on_change` to provide completion results rather than passing through `fuzzy.filter()`. Frecency reordering is applied in the `on_change` callback path when Provider identity and the `lua` Sorter are active.

### Health and diagnostics

- Update the existing health check to report Frecency status:
  - SQLite available and Frecency active.
  - SQLite unavailable (Neovim <0.10 or no SQLite build) — Frecency disabled.
  - Frecency globally disabled via configuration.

- Update documentation to describe Frecency semantics, the `lua` Sorter scope, Provider identity, key strategies, opt-out behavior, SQLite graceful degradation, and cleanup behavior.

## Testing Decisions

- Tests should validate external behavior and module contracts, not private implementation details. Good tests assert that user-visible ordering, recording behavior, graceful degradation, Provider isolation, and Sorter scoping behave correctly.

- Test the Frecency public module as a deep module. Use deterministic inputs and injected timestamps where needed. Verify that recording a selection changes future ordering for the same Provider and key.

- Test the persistence component through observable operations: initialization, upsert-on-record, reading multiple keys, Provider isolation, missing SQLite no-op behavior, and cleanup limits. Avoid tests that depend on the exact internal SQL beyond the agreed schema contract.

- Test the scoring component independently from SQLite. Cover bucket selection, score ordering, tie handling, empty-query sorting, items without scores, and neighborhood-based reordering.

- Test key strategies. Verify text-based keys, filepath-based keys, filepath-with-line keys, missing data behavior, and custom key functions.

- Test key strategy edge cases. Verify that `filepath` strategy normalizes relative paths to absolute paths. Verify that duplicate display text within a Provider resolves to different Frecency keys when using filepath strategy. Verify that fallback to `text` occurs when `data.filename` is absent.

- Test the built-in `lua` sorter integration. Existing fuzzy behavior should remain intact while Frecency changes ordering only when Provider identity is present, Frecency is enabled, and the active Sorter is `lua`.

- Test that Frecency does not apply to Blink, Mini, native Vim sorting, or custom Sorters.

- Test Sorter identity detection. Verify that Frecency activates by comparing the current sorter name to `"lua"`, not by function reference. Verify that cycling from `lua` to another sorter deactivates Frecency and cycling back reactivates it.

- Test Picker action recording. Verify that `select_entry`, `edit_entry`, `split_entry`, `vsplit_entry`, `tab_entry`, and `open_marked` each record the selected ReferItem(s). Verify that `complete_selection`, `refresh`, navigation, and `close` do not record. Verify that `select_input` records only when the input matches a ReferItem in `current_matches`.

- Test Provider identity propagation through builtin Providers. Verify that buffers passes `provider = "buffers"` and `key_strategy = "filepath"`, that commands passes `provider = "commands"` and `key_strategy = "text"`, and so on for each participating Provider.

- Test opt-out behavior. A Provider with `frecency.enabled = false` should retain normal sorting and should not write history.

- Test global disable. When `frecency.enabled = false` at the setup level, no Provider should record or apply Frecency regardless of individual Provider settings.

- Test graceful degradation. When SQLite is unavailable, Frecency should not throw, should not reorder, and should not prevent selection.

- Test SQLite runtime failures. Verify that a locked DB, write failure, or corrupt file does not crash the picker. Verify that a one-time warning is logged and that the session continues in no-op mode.

- Test async and on_change Provider behavior. Verify that file Provider items receive Frecency reordering when results arrive. Verify that command-completion Provider items receive Frecency reordering through the `on_change` path. Verify that empty-query Frecency works for synchronous Providers and degrades gracefully for async Providers that require a minimum query length.

- Test duplicate display text. Verify that items with the same display text but different `data` identities resolve to different Frecency keys when using filepath or filepath_with_lnum strategy.

- Test tie-breaking. When Frecency scores are equal within a neighborhood, original fuzzy-sort order should be preserved. When items have no Frecency score, they should appear in their original order after scored items.

- Test clock edge cases. Verify behavior with future timestamps, zero/negative age values, and missing timestamps. Scoring should treat missing or invalid timestamps as the lowest recency bucket.

- Test health check output. Verify that health reports show Frecency as available, unavailable, or globally disabled correctly.

- Use the existing Plenary/Busted test style already present in the project. Prior art includes fuzzy sorter tests, ReferItem contract tests, custom Sorter tests, picker behavior tests, action tests, Provider tests, and regression tests for Sorter cycling and selection actions.

- Run the full test suite through the existing project test command after implementation.

## Out of Scope

- Applying refer.nvim Frecency to Blink, Mini, native Vim sorting, or custom Sorters.

- Replacing or disabling Blink's own internal Frecency behavior.

- Implementing a JSON persistence fallback.

- Implementing global cross-Provider Frecency.

- Adding a UI for browsing, editing, importing, or exporting Frecency history.

- Syncing Frecency history across machines.

- Tracking hover, cursor movement, typed characters, preview dwell time, or other implicit signals.

- Changing the public custom Sorter contract for all Sorters.

- Designing a new fuzzy algorithm beyond the score exposure needed for the built-in `lua` sorter.

- Completely reworking Provider item models. However, minimal metadata additions to builtin Providers (such as ensuring `data.filename` contains absolute paths for file-like items) are in scope, since stable Frecency keys depend on them.

## Further Notes

- This PRD follows the accepted architecture decision for Frecency-enhanced sorting (see `docs/adr/0001-frecency-enhanced-sorting.md`).

- The central product constraint is that Frecency improves the built-in `lua` sorter without surprising users of other Sorters.

- The Frecency module should be treated as a deep module: callers should not need to understand SQLite, bucket math, cleanup policy, or key extraction internals.

- The domain glossary terms used here are Frecency, Sorter, ReferItem, and Provider (see `CONTEXT.md`).

- Initial implementation should prefer clear behavior and deterministic tests over over-tuning the scoring formula. Bucket weights and cleanup thresholds can be adjusted later without changing the product contract.

- Builtin Providers that participate in Frecency may need minimal metadata adjustments to ensure `data.filename` contains absolute paths. This is in scope even though broader Provider model rework is not.

- The exact Frecency scoring formula is `score = count / (age_bucket + 1)` with configurable bucket boundaries and multipliers. Default buckets are: last hour (highest multiplier), last day, last week, older (lowest multiplier).

- The database is stored at `stdpath("data") .. "/refer/frecency.db"` by default. This path can be overridden in configuration for testing or alternative setups.

- Sorter identity for Frecency activation is determined by name (`"lua"`) rather than by function reference. This avoids ambiguity when sorter cycling changes the active function or when a custom sorter wraps the built-in `lua` sorter.
