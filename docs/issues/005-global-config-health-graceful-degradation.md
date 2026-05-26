# Issue 5: Global config, health check, and graceful degradation

### Parent

PRD: `docs/prd/frecency-enhanced-lua-sorting.md`

### What to build

Add production hardening for Frecency: a global disable switch, a public status API for health reporting, and graceful handling of SQLite initialization and runtime failures.

**Global disable switch** — The `frecency.enabled` option in `setup()` acts as a global kill switch. When set to `false`, no Provider records or applies Frecency, regardless of individual Provider settings. When globally disabled, the Frecency module does not open the database, create the schema, read scores, or log SQLite availability notices. Normal picker behavior is completely unaffected.

**Per-provider opt-out** — A Provider with `frecency.enabled = false` retains normal sorting and does not write history, even when the global switch is on.

**Precedence** — Global `frecency.enabled = false` takes precedence. When globally disabled, no SQLite probing, logging, or DB initialization is attempted. Health reports "disabled by config" and may still show the configured path.

**Public status API** — `frecency.status()` returns a structured table that health checks use instead of duplicating private DB state logic. The shape is:

- `enabled` (boolean): globally enabled per config
- `sqlite_available` (boolean): `vim.sqlite` is present and functional
- `active` (boolean): Frecency is actually applying (enabled AND sqlite_available AND not in no-op mode)
- `no_op` (boolean): currently in session no-op mode due to init/write failure
- `reason` (string|nil): human-readable reason when not active (e.g., "disabled by config", "sqlite unavailable", "write failure")
- `db_path` (string): resolved database path (even when disabled)

**Health check** — Extend the existing health check at `lua/refer/health.lua` to report Frecency status using `frecency.status()`:
- SQLite available and Frecency active: report OK with the db_path
- SQLite unavailable (Neovim < 0.10 or no SQLite build): report that Frecency is disabled and explain why
- Frecency globally disabled via configuration: report that Frecency is disabled by user config; do not log SQLite notices
- Session no-op mode due to runtime failure: report WARN with the failure reason

Health language must be capability-based ("Frecency available: SQLite present, globally enabled; applies only to Providers using the `lua` sorter"), not implying it applies to all sorters.

**First-operation DB initialization** — Schema creation and directory setup are deferred until the first Frecency operation (record or score), not on plugin load. If initialization fails (directory creation failure, schema creation failure, connection failure), log a one-time WARN and enter session no-op mode. Subsequent record/read/reorder calls do not retry or crash — they are no-ops.

**SQLite runtime failure handling** — If a write fails (locked DB, permission error, corrupt file, schema mismatch), log a one-time WARN and enter session no-op mode for the rest of the session. If a read fails, return empty results without logging (avoid spamming on every query). After entering session no-op mode, subsequent operations do not call SQLite at all.

**Startup behavior** — On plugin load, check `vim.sqlite` availability once. If unavailable, enter no-op mode with a one-time DEBUG notice. Do not attempt to open the database or create the schema until the first Frecency operation.

**Database path behavior** — Health shows the resolved `db_path` in all states (available, unavailable, disabled, degraded). When `db_path` is overridden in config, health shows the override path.

### Acceptance criteria

- [ ] Setting `frecency.enabled = false` in `setup()` disables all Frecency recording, reordering, and database access across all Providers
- [ ] Globally disabling Frecency prevents SQLite probing, DB opening, schema creation, and SQLite availability logging — no DB operations at all
- [ ] Per-provider `frecency.enabled = false` disables Frecency for that Provider only, while other Providers continue normally
- [ ] When both global and per-provider settings conflict, global `false` takes precedence — no Frecency anywhere
- [ ] `frecency.status()` returns a table with `enabled`, `sqlite_available`, `active`, `no_op`, `reason`, and `db_path` fields
- [ ] Health check reports Frecency as available when SQLite is present and Frecency is enabled, using capability-based language ("applies only to Providers using the `lua` sorter")
- [ ] Health check reports Frecency as unavailable when SQLite is missing, with an explanation
- [ ] Health check reports Frecency as disabled when globally configured off, without logging SQLite notices
- [ ] Health check reports session no-op mode with the failure reason when a runtime failure has occurred
- [ ] Health check shows the resolved database path (default or override) in all states
- [ ] When `vim.sqlite` is unavailable, Frecency enters no-op mode with a one-time DEBUG notice
- [ ] Database schema initialization is deferred until first Frecency operation, not on plugin load
- [ ] If first-operation DB initialization fails (directory, connection, schema, preparation), Frecency logs one-time WARN, enters session no-op mode, and subsequent operations are no-ops without retrying
- [ ] If a SQLite write fails (locked DB, permission, corruption, schema mismatch), Frecency logs one-time WARN and enters session no-op mode; further operations do not call SQLite
- [ ] If a SQLite read fails, Frecency returns empty results without calling `vim.notify` — no logging on read failures
- [ ] After entering no-op mode (from init failure or write failure), subsequent `record`, `score`, and `reorder` calls are no-ops that do not call SQLite
- [ ] The picker remains functional and responsive regardless of Frecency or SQLite state; after a write failure, subsequent picker refreshes do not call SQLite
- [ ] Existing tests still pass; new tests cover: global disable (no DB access), per-provider opt-out, `status()` return shape in each state, health check output for available/unavailable/disabled/degraded, first-use init failure, write failure and session no-op, read failure (empty results, no log), precedence (global disabled + SQLite missing), db_path display in all states

### Blocked by

- Issue 2 (End-to-end tracer — buffers with Frecency)
