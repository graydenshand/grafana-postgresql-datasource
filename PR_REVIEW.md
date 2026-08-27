# Multi-Database Feature: PR Readiness Review

**Branch:** `feat/multi-db-datasource`
**Date:** 2026-08-27

## Repos

| Repo | Commits | Summary |
|------|---------|---------|
| `grafana-postgresql-datasource` | 3 | Backend pool routing, frontend datasource methods, config editor, query editor overhaul |
| `grafana/packages/grafana-sql` | 1 | DB interface changes, DatabaseSelector component, QueryHeader integration |

Existing tests pass in both repos (26 frontend tests in plugin, 8 in grafana-sql).

---

## P0: Must Fix Before PR

### 1. Local tarball dependency in `package.json`

**File:** `package.json:83`
```json
"@grafana/sql": "file:/tmp/grafana-sql-fixed.tgz",
```
This is a local dev artifact. The PR needs either:
- A published pre-release version of `@grafana/sql`, or
- A documented coordinated release strategy (grafana-sql merges first, then plugin updates the version)

### 2. Spurious `@grafana/assistant` devDependency

**File:** `package.json:20`
```json
"@grafana/assistant": "0.1.34",
```
Not present on `main`, not used anywhere in the diff. Remove it.

### 3. `rebuild-sql.sh` (untracked)

Local dev workflow helper visible in `git status`. Either `.gitignore` it or delete it before submitting.

---

## P1: Should Fix Before PR

### 4. No unit tests for `getPool()` backend logic

**File:** `pkg/postgresql/sqleng/sql_engine.go:177-210`

The pool cache, database name validation, race handling (LoadOrStore), and maxPoolCacheSize enforcement are all untested. Recommended tests:
- Returns default pool when database is empty or matches configured DB
- Returns error for invalid database names (null bytes, semicolons, quotes)
- Returns error when poolFactory is nil
- Returns error when cache is full
- Validates the LoadOrStore race-condition path (concurrent calls for same DB)

### 5. No tests for new frontend datasource methods

**Files:** `src/datasource.ts`, `src/postgresMetaQuery.ts`

| Function | File | Notes |
|----------|------|-------|
| `runSqlWithDatabase()` | `datasource.ts:100-122` | New query routing logic |
| `fetchDatabases()` | `datasource.ts:124-127` | DB listing |
| `fetchSchemas()` | `datasource.ts:129-136` | Schema listing with database param |
| `applyTemplateVariables()` | `datasource.ts:44-54` | Template variable substitution |
| `showDatabases()` | `postgresMetaQuery.ts:1-3` | SQL generation |
| `showSchemas()` | `postgresMetaQuery.ts:5-12` | SQL generation |
| `showTables(schema)` | `postgresMetaQuery.ts:23-28` | Updated SQL generation |

At minimum, add tests for:
- `applyTemplateVariables` — verify database/dataset fields are template-replaced
- `showDatabases`, `showSchemas`, `showTables(schema)` — snapshot tests for generated SQL
- `fetchDatabases`/`fetchSchemas` — mock backend response and verify parsing

### 6. No tests for `DatabaseSelector` component (grafana-sql)

**File:** `packages/grafana-sql/src/components/DatabaseSelector.tsx`

New component with no tests. Recommended coverage:
- Renders and calls `db.databases()` on mount
- Does not error when `db.databases` is undefined (early return)
- Passes loading/disabled state correctly

### 7. Verify `DatasetSelector` behavioral change doesn't break MSSQL/MySQL

**File:** `packages/grafana-sql/src/components/DatasetSelector.tsx`

The old code called `onChange(toOption(preconfiguredDataset))` inside `useAsync` when preconfigured. This was removed. If any consumer relied on that side-effect to initialize query state, this could be a regression for MSSQL/MySQL datasources.

---

## P2: Nice to Fix

### 8. `docker-compose.yaml` local dev volume mounts

**File:** `docker-compose.yaml:31-36`

The volume mounts override the bundled plugin with a local build. Decide whether this should be the default `docker-compose.yaml` or belong in a `docker-compose.override.yaml`.

### 9. Unused `dialect` prop in `DatasetSelector` (grafana-sql)

**File:** `packages/grafana-sql/src/components/DatasetSelector.tsx:14`

Still declared in `DatasetSelectorProps` interface but no longer used in the component body. Should be removed (or marked deprecated if it's a public API concern).

### 10. Duplicated `DatabaseSelector` rendering in `QueryHeader`

**File:** `packages/grafana-sql/src/components/QueryHeader.tsx` (lines 352-366 and 372-381)

The `DatabaseSelector` is rendered identically in both Code mode and Builder mode blocks. Could be extracted above the mode conditional.

### 11. Hard-to-read operator precedence in ternary

**File:** `packages/grafana-sql/src/components/QueryHeader.tsx:390`
```tsx
preconfiguredDataset={db.databases || dialect === 'postgres' ? '' : preconfiguredDataset}
```
Works correctly but benefits from explicit parentheses:
```tsx
preconfiguredDataset={(db.databases || dialect === 'postgres') ? '' : preconfiguredDataset}
```
Same pattern at line 399.

### 12. `as DB` type assertion in `datasource.ts`

**File:** `src/datasource.ts:220`

The cast suggests the return object doesn't fully satisfy the `DB` interface (because `databases` is conditionally spread). Consider making the type explicit or restructuring to avoid the cast.

### 13. `package-lock.json` — lockfile format drift

The diff removes `libc` fields from many optional native dependencies. Verify this was generated by the same npm version used in CI, not just a format difference.

---

## P3: Minor / Informational

### 14. Pool cache counter not decremented

**File:** `pkg/postgresql/sqleng/sql_engine.go:101`

`poolCacheCount` is incremented on add but never decremented. Fine for now (Dispose closes all), but worth a comment if eviction is ever added.

### 15. Database name validation scope

**File:** `pkg/postgresql/sqleng/sql_engine.go:182`

Validates against `\x00`, `;`, `'` — sufficient for connection string safety, but a comment explaining the rationale would help future maintainers.

### 16. Config editor label change

**File:** `src/configuration/ConfigurationEditor.tsx:144`

Changed from "Database name" to "Default database name" with placeholder "postgres". Minor UX consideration — the placeholder suggests a default value when the field was previously empty.

### 17. DB interface changes should be noted in PR description

**File:** `packages/grafana-sql/src/types.ts`

Changes are backward-compatible (new optional fields/params) but plugin authors implementing `DB` should be informed:
- Added optional `databases?: () => Promise<string[]>`
- Changed `datasets()` to `datasets(database?: string)`
- Changed `tables(dataset?)` to `tables(dataset?, database?)`
- Added optional `labels?: Map<string, string>`
- Added `database?: string` to `SQLQuery`

---

## Action Summary

| Priority | # | Item | Status |
|----------|---|------|--------|
| P0 | 1 | Replace `file:/tmp/grafana-sql-fixed.tgz` with proper dep | **TODO** — needs coordinated release |
| P0 | 2 | Remove `@grafana/assistant` devDependency | **DONE** |
| P0 | 3 | Handle `rebuild-sql.sh` | **SKIP** — leaving untracked for dev use |
| P1 | 4 | Add unit tests for `getPool()` (Go) | **DONE** — 10 tests in sql_engine_test.go |
| P1 | 5 | Add tests for new frontend methods | **DONE** — 11 new tests (meta queries + datasource) |
| P1 | 6 | Add `DatabaseSelector` component test (grafana-sql) | **TODO** — requires monorepo test infra |
| P1 | 7 | Verify DatasetSelector change doesn't break MSSQL/MySQL | **TODO** — manual testing needed |
| P2 | 8 | Decide on docker-compose volumes approach | **TODO** — strip from PR branch before submission |
| P2 | 9 | Remove unused `dialect` prop (grafana-sql) | **DONE** |
| P2 | 10 | Deduplicate DatabaseSelector render | **SKIP** — intentional (different placement per mode) |
| P2 | 11 | Add explicit parens in ternary (grafana-sql) | **DONE** |
| P2 | 12 | Fix `as DB` type cast | **DONE** |
| P2 | 13 | Verify lockfile npm version consistency | **NOTE** — benign `libc` field removal from npm version drift; regenerate lockfile with CI's npm version before submission |
| P3 | 14 | Add comment re: poolCacheCount not decremented | **DONE** |
| P3 | 15 | Add comment explaining database name validation | **DONE** |
| P3 | 16 | Config editor label/placeholder change | **SKIP** — current behavior is fine |
| P3 | 17 | Note DB interface changes in PR description | **TODO** — add when writing PR |
| P2 | 13 | Verify lockfile npm version consistency | Investigation |
| P3 | 14-17 | Minor comments/docs | Trivial |
