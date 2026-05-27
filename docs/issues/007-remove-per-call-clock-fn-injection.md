# Issue 7: Remove per-call `clock_fn` injection

### Parent

PRD: `docs/prd/frecency-cache-and-clock-cleanup.md`

### What to build

Remove the undocumented `[TEST-ONLY]` `opts.clock_fn` parameter from `db.record()` and `db.read_scores()`. This parameter permanently mutates the module-level `clock_fn` variable on each call, creating a production code path that mutates module state. All clock injection should go through `configure({ clock_fn = ... })` exclusively.

In `db.lua`, remove the `if opts and opts.clock_fn then clock_fn = opts.clock_fn end` blocks from both `record()` and `read_scores()`. Also remove the `[TEST-ONLY]` comments documenting this mechanism. Remove `clock_fn` from the `opts` parameter type annotations for both functions.

In `init.lua`, remove the `clock_fn` field from the `@param opts` annotations on `record()` and `score()`. Remove `clock_fn` from the `opts` table constructed inside `reorder()` that is passed to `db.read_scores()` — the clock should come from the module-level `clock_fn` set via `configure()`, not from per-call opts. Keep the `clock_fn` field in `FrecencyConfig` and the pass-through to `db.configure()` inside `M.configure()` — that path remains the correct way to inject a clock.

Refactor all tests that currently pass `clock_fn` via per-call `opts` to use the `configure()` pattern with mutable closures instead. The standard pattern becomes:

```lua
local t = 1000000
db.configure({ db_path = path, clock_fn = function() return t end })
db.record("provider", "key")
t = t + 3600
local scores = db.read_scores("provider", { "key" })
```

For tests that need different timestamps between record and score, advance the mutable `t` variable between calls rather than passing a different `clock_fn` per call. Tests that already use `setup_frecency()` helpers with `configure()` need only minor adjustments.

The four affected test files are: `frecency_db_spec.lua`, `frecency_init_spec.lua`, `frecency_cleanup_spec.lua`, and `regression_frecency_e2e_spec.lua`. The `frecency_score_spec.lua` file does not use `clock_fn` and needs no changes.

This slice delivers a cleaner API surface: `record()` and `read_scores()` no longer accept `clock_fn` in their `opts`, removing a state-mutation path from production code while preserving deterministic test control through `configure()`.

### Acceptance criteria

- [x] `db.record()` no longer reads or mutates `clock_fn` from its `opts` parameter
- [x] `db.read_scores()` no longer reads or mutates `clock_fn` from its `opts` parameter
- [x] `init.lua` `record()` no longer passes `clock_fn` through to `db.record()`
- [x] `init.lua` `score()` no longer passes `clock_fn` through to `db.read_scores()`
- [x] `init.lua` `reorder()` no longer includes `clock_fn` in the opts table passed to `db.read_scores()`
- [x] `FrecencyConfig` type annotation still includes `clock_fn` as optional; `configure()` still passes it through to `db.configure()`
- [x] All tests that previously passed `clock_fn` via per-call `opts` now use the mutable-closure `configure()` pattern
- [x] `frecency_db_spec.lua` tests pass with `configure({ clock_fn = ... })` pattern
- [x] `frecency_init_spec.lua` tests pass with `configure({ clock_fn = ... })` pattern
- [x] `frecency_cleanup_spec.lua` tests pass with `configure({ clock_fn = ... })` pattern
- [x] `regression_frecency_e2e_spec.lua` tests pass with `configure({ clock_fn = ... })` pattern
- [x] `frecency_score_spec.lua` requires no changes (no `clock_fn` usage)
- [x] All existing test assertions pass unchanged — only the clock injection mechanism changes, not behavior

### Blocked by

None — can start immediately.
