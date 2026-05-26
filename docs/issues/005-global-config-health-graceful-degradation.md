# Issue 5: Global config, health check, and graceful degradation

### Parent

PRD: `docs/prd/frecency-enhanced-lua-sorting.md`

### What to build

Add production hardening for Frecency: a global disable switch, a public status API for health reporting, and graceful handling of JSON store initialization and runtime failures.

**Global disable switch** — The `frecency.enabled` option in `setup()` acts as a global kill switch. When set to `false`, no Provider records or applies Frecency, regardless of individual Provider settings. When globally disabled, the Frecency module does not create directories, read the JSON store, write the JSON store, or log persistence notices. Normal picker behavior is completely unaffected.

**Per-provider opt-out** — A Provider with `frecency.enabled = false` retains normal sorting and does not write history, even when the global switch is on.

**Precedence** — Global `frecency.enabled = false` takes precedence. When globally disabled, no persistence access or logging is attempted. Health reports "disabled by config" and may still show the configured path.

**Public status API** — `frecency.status()` returns a structured table that health checks use instead of duplicating private persistence state logic. The shape is:

- `enabled` (boolean): globally enabled per config
- `store_available` (boolean): the JSON store is currently readable/writable, or has not failed this session
- `active` (boolean): Frecency is actually applying (enabled AND store_available AND not in no-op mode)
- `no_op` (boolean): currently in session no-op mode due to read/decode/write failure
- `reason` (string|nil): human-readable reason when not active (e.g., "disabled by config", "corrupt store", "write failure")
- `db_path` (string): resolved JSON store path (even when disabled)

**Health check** — Extend the existing health check at `lua/refer/health.lua` to report Frecency status using `frecency.status()`:
- JSON store available and Frecency active: report OK with the `db_path`
- JSON store failure/corruption: report WARN that Frecency is disabled for the session and explain why
- Frecency globally disabled via configuration: report that Frecency is disabled by user config; do not log persistence notices
- Session no-op mode due to runtime failure: report WARN with the failure reason

Health language must be capability-based ("Frecency available: JSON store usable, globally enabled; applies only to Providers using the `lua` sorter"), not implying it applies to all sorters.

**First-operation store initialization** — Directory setup and initial store creation are deferred until the first Frecency write operation. If initialization fails (directory creation failure, invalid path, permission error), log a one-time WARN and enter session no-op mode. Subsequent record/read/reorder calls do not retry or crash — they are no-ops.

**JSON runtime failure handling** — If the store cannot be read or decoded, log a one-time WARN, leave the existing file untouched, and enter session no-op mode for the rest of the session. If a write or atomic rename fails, log a one-time WARN and enter session no-op mode. After entering session no-op mode, subsequent operations do not touch the store.

**Startup behavior** — On plugin load, do not touch the JSON store. Frecency does not create directories, read files, or write files until the first Frecency operation that needs persistence.

**Database path behavior** — Health shows the resolved `db_path` in all states (available, disabled, degraded). When `db_path` is overridden in config, health shows the override path. Despite the option name, `db_path` points to the JSON store path.

### Acceptance criteria

- [ ] Setting `frecency.enabled = false` in `setup()` disables all Frecency recording, reordering, and store access across all Providers
- [ ] Globally disabling Frecency prevents directory creation, JSON reads, JSON writes, and persistence logging — no store operations at all
- [ ] Per-provider `frecency.enabled = false` disables Frecency for that Provider only, while other Providers continue normally
- [ ] When both global and per-provider settings conflict, global `false` takes precedence — no Frecency anywhere
- [ ] `frecency.status()` returns a table with `enabled`, `store_available`, `active`, `no_op`, `reason`, and `db_path` fields
- [ ] Health check reports Frecency as available when the JSON store is usable and Frecency is enabled, using capability-based language ("applies only to Providers using the `lua` sorter")
- [ ] Health check reports Frecency as degraded/unavailable when JSON persistence has failed, with an explanation
- [ ] Health check reports Frecency as disabled when globally configured off, without logging persistence notices
- [ ] Health check reports session no-op mode with the failure reason when a runtime failure has occurred
- [ ] Health check shows the resolved store path (default or override) in all states
- [ ] JSON store initialization is deferred until first Frecency operation, not on plugin load
- [ ] If first-operation store initialization fails (directory creation, file creation, permission), Frecency logs one-time WARN, enters session no-op mode, and subsequent operations are no-ops without retrying
- [ ] If the JSON store is corrupt or unreadable, Frecency logs one-time WARN, leaves the file untouched, and enters session no-op mode
- [ ] If a JSON write or atomic rename fails, Frecency logs one-time WARN and enters session no-op mode; further operations do not touch the store
- [ ] After entering no-op mode, subsequent `record`, `score`, and `reorder` calls are no-ops that do not touch the store
- [ ] The picker remains functional and responsive regardless of Frecency persistence state; after a write failure, subsequent picker refreshes do not touch the store
- [ ] Existing tests still pass; new tests cover: global disable (no store access), per-provider opt-out, `status()` return shape in each state, health check output for available/disabled/degraded, first-use init failure, corrupt store, write failure and session no-op, precedence (global disabled + corrupt store), db_path display in all states

### Blocked by

- Issue 2 (End-to-end tracer — buffers with Frecency)
