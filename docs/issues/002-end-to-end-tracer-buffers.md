# Issue 2: End-to-end tracer — buffers with Frecency

### Parent

PRD: `docs/prd/frecency-enhanced-lua-sorting.md`

### What to build

Wire the Frecency module (from Issue 1) into the picker end-to-end so that the `buffers` Provider demonstrates Frecency-enhanced sorting. This is the first visible demo: open the buffers picker, select a buffer, reopen the picker, and see that buffer ranked higher.

This slice touches every integration layer:

1. **Sorter name tracking** — The Picker must know which sorter is active by name (not function reference). When `cycle_sorter` runs, the Picker updates `self.sorter_name`. Frecency checks `self.sorter_name == "lua"` to decide whether to activate.

2. **Lua sorter score exposure** — The built-in `lua` sorter currently returns matched strings only. Extend it so `fuzzy.filter` can preserve numeric fuzzy scores internally when the `lua` sorter is active. These scores form neighborhoods for Frecency reordering. Other sorters continue returning plain string lists.

3. **Provider identity plumbing** — Add a `frecency` option group to `ReferOptions`:
   - `provider` (string): Provider identity, e.g. `"buffers"`. Required for Frecency to activate.
   - `key_strategy` (string or function): defaults to `"text"`.
   - `enabled` (boolean): defaults to `true`. Per-provider opt-out.

   Add global `frecency` config in `setup()` (minimal plumbing for this slice — Issue 5 owns the full global-disable behavior, health check, and graceful degradation):
   - `enabled` (boolean): global kill switch, defaults to `true`.
   - `db_path` (string): override JSON store path.
   - `buckets` (table): override bucket boundaries/multipliers.
   - `neighborhood_size` (number): defaults to `10`.

4. **Post-sort reorder path** — When the `lua` sorter is active, Provider identity is present, and Frecency is enabled, `fuzzy.filter` calls `frecency.reorder()` after sorting. The reorder function receives the sorted items with their fuzzy scores, resolves keys, fetches Frecency scores, and reorders within score neighborhoods. When conditions are not met (non-lua sorter, no provider identity, global disable), filter behaves exactly as before.

5. **Action recording hooks** — Wire accept actions to call `frecency.record()`:
   - `select_entry`, `edit_entry`, `split_entry`, `vsplit_entry`, `tab_entry` record the selected ReferItem.
   - `open_marked` records each marked ReferItem.
   - `select_input` resolves input against `current_matches`; records only if the input matches an existing ReferItem.
   - Navigation and UI actions do not record.
   - Recording uses the Picker's Provider identity and key strategy to resolve the Frecency key.

6. **Buffers provider wiring** — Pass `frecency = { provider = "buffers", key_strategy = "filepath" }` in the buffers Provider options. Ensure `data.filename` in buffer items contains the absolute file path (already the case in current code, but verify).

After this slice, a user can: open the buffers picker with the `lua` sorter active, select a buffer, reopen the picker, and see the selected buffer ranked higher. Selecting multiple times should rank it even higher. An empty query should show frecent buffers first. Switching the sorter away from `lua` should disable Frecency reordering. Note: the default sorter is `blink`, so all demos and tests must explicitly set `default_sorter = "lua"` or cycle to `lua` before testing Frecency behavior.

### Acceptance criteria

- [ ] Picker tracks the active sorter by name (`self.sorter_name`) on initialization and on `cycle_sorter`; resolves `default_sorter`, string opts, and registered custom sorters correctly
- [ ] The `lua` sorter path in `fuzzy.filter` preserves numeric fuzzy scores as a map (keyed by item text) when the `lua` sorter is active; other sorter paths return items without scores
- [ ] `ReferOptions` accepts a `frecency` option group with `provider`, `key_strategy`, and `enabled` fields
- [ ] `setup()` accepts a global `frecency` config with `enabled`, `db_path`, `buckets`, and `neighborhood_size`
- [ ] When `lua` sorter is active, Provider identity is present, and Frecency is enabled, `fuzzy.filter` applies Frecency reordering after sorting
- [ ] When any condition is not met (non-lua sorter including default `blink`, no Provider identity, global disable, per-provider disable), filter behaves exactly as before — no reordering
- [ ] `select_entry`, `edit_entry`, `split_entry`, `vsplit_entry`, `tab_entry` call `frecency.record()` with the Provider identity and resolved key **before** `picker:close()`
- [ ] `open_marked` calls `frecency.record()` for each marked ReferItem **before** `picker:close()`
- [ ] `select_input` records only when the input exactly matches a ReferItem's `text` field in `current_matches`; arbitrary typed text that doesn't match does not record
- [ ] Navigation and UI actions (`complete_selection`, `refresh`, `toggle_mark`, `close`, `select_all`, `deselect_all`, `toggle_all`, `send_to_qf`, `send_to_grep`, `cycle_sorter`, `toggle_preview`, `scroll_preview_up`, `scroll_preview_down`) do not record
- [ ] No recording happens when Provider identity is absent, `frecency.enabled` is false per-provider, or Frecency is in no-op/unavailable mode
- [ ] Buffers provider passes `frecency = { provider = "buffers", key_strategy = "filepath" }` and buffer items have absolute paths in `data.filename`
- [ ] Selecting a buffer, reopening the picker with the `lua` sorter active, and searching for it shows the selected buffer ranked higher
- [ ] An empty buffers picker query with the `lua` sorter active shows frecent buffers first
- [ ] Cycling the sorter away from `lua` disables Frecency reordering; cycling back to `lua` re-enables it
- [ ] Two ReferItems with the same `text` but different `data.filename` remain distinct through Lua filtering and Frecency reordering (filepath strategy resolves different keys)
- [ ] When Frecency is in no-op mode (persistence failure), the buffers picker still selects and reorders normally with no crashes or errors
- [ ] Existing tests for fuzzy sorting, picker behavior, and actions still pass
- [ ] New tests cover: sorter name tracking (initial name, cycling, custom sorter names), score exposure (lua path returns scores, non-luapaths omit them), reorder activation/deactivation, action recording (including recording before close), buffers Provider Frecency wiring, no-op mode integration

### Blocked by

- Issue 1 (Frecency deep module)
