# BiblioFlow deployment audit

## Scope and status

Audited the six SQL files that were under `database/migrations/` and moved them, without discarding their implementation, into timestamped `supabase/migrations/` files. The timestamped Supabase directory is the single source of truth; `database/migrations/` is no longer a duplicate SQL source.

This work prepares the repository for the Supabase CLI. It does **not** link or modify a hosted project. The hosted database state cannot be inferred from local files.

## Migration order and objects

| Timestamped migration | Depends on | Main contents |
| --- | --- | --- |
| `20261116164500_create_enums.sql` | Supabase `public` schema | Six domain enums |
| `20261116164501_create_tables.sql` | Enums; Supabase `auth.users` | Seven tables, foreign keys, checks, and indexes |
| `20261116164502_auth_triggers.sql` | `profiles`; `auth.users` | Profile-on-signup trigger and `updated_at` triggers |
| `20261116164503_rls_policies.sql` | All tables and auth helpers | RLS, explicit grants/revokes, role helper functions and policies |
| `20261116164504_business_logic.sql` | Tables, RLS helpers | Eight requested RPCs, role administration, reservation dispatcher, daily maintenance |
| `20261116164505_cron_jobs.sql` | Maintenance function; `pg_cron` | UTC-checked daily schedule at 00:00 |

PostgreSQL 17 supports the UUID, partial-index, composite-FK, row-locking, and `ON DELETE SET NULL (copy_id)` features used here. The local Supabase config targets PostgreSQL major version 17.

## Audit findings and changes

1. **Non-CLI layout:** the SQL was outside `supabase/migrations/` and had non-timestamp names. The files have been moved, in their original dependency order, to the timestamped paths above. There is now one maintained SQL copy.
2. **Invalid `CHECK`:** the old loans migration included a subquery in a `CHECK`, which PostgreSQL disallows. That constraint was removed. Active/overdue copy exclusivity is now enforced by a partial unique index.
3. **Invalid policy references:** the old RLS policies used `NEW`/`OLD`, which are trigger transition records, not policy variables. Those policies were replaced with valid row predicates and column-level grants.
4. **Missing direct-write protections:** explicit revokes and narrow grants now prevent authenticated clients from directly inserting/updating loans, inserting/updating reservations, inserting/updating sanctions, or changing profile role/status. Members cancel reservations only through an authorized RPC.
5. **Role escalation:** direct role changes are not granted. `set_profile_role` is an authenticated RPC that checks for an active admin, so a librarian cannot promote themselves or another user. It also prevents removing the last active admin. Initial admin provisioning remains a trusted operator action.
6. **RPCs absent or unsafe:** all eight required RPCs are now implemented: `create_loan`, `return_loan`, `create_reservation`, `cancel_reservation`, `pickup_reservation`, `renew_loan`, `get_available_copies`, and `get_user_dashboard`. Execute is revoked from `PUBLIC`/`anon`, then granted to `authenticated`; each function validates its caller and role/ownership as applicable.
7. **Foreign-key integrity:** sanctions now reference the matching `(loan_id, user_id)` pair. Reservations use a composite FK so an assigned copy must belong to the reserved book. Checks constrain loan return state and reservation assignment state.
8. **Indexes and concurrency:** active and overdue loans share a partial unique index; active reservations, ready-copy assignments, and active sanctions have their own partial unique indexes. Foreign keys have supporting indexes. Reservations have an identity queue sequence so equal transaction timestamps still preserve insertion order. The dispatcher serializes by book and uses `FOR UPDATE SKIP LOCKED`.
9. **Return/FIFO behavior:** return is idempotent for already-returned loans, sets the loan to returned and the copy available, records a late-return sanction, then dispatches waiting reservations transactionally. The oldest pending reservation receives an available copy with a three-day pickup deadline. A local integration test exposed that transaction timestamps can tie; the identity queue sequence now makes FIFO order deterministic. Pickup creates the associated loan and marks the copy on loan.
10. **Sanction rounding:** partial overdue days round up to a full day using `CEIL(seconds / 86400)`. A one-day sanction starts at return time; profile reactivation occurs when no active sanctions remain.
11. **Daily maintenance and timezone:** maintenance marks overdue loans, expires ready reservations, releases and redispatches copies, expires sanctions, and reactivates eligible profiles. Migration 6 checks `cron.timezone` and stops unless it is UTC/GMT-equivalent; it then idempotently replaces the named job at 00:00. The target environment must have `pg_cron` installed and the migration role must be allowed to schedule jobs.
12. **`SECURITY DEFINER`:** privileged routines use a fixed `search_path` with `pg_temp` last, schema-qualified objects, and restricted execute grants. The signup trigger always assigns `member`; it does not trust user metadata for role.

Versioned schema migrations are intended to run once and be tracked; most DDL is intentionally not rerunnable. The cron job creation is idempotent by replacing only the job with the BiblioFlow-specific name.

## Local checks

The repository includes `supabase/tests/database_contract.test.sql`, covering table presence, RLS activation, direct mutation privileges, required RPCs, function grants/search paths, and cron timezone/schedule. Validation commands:

```sh
npx --yes supabase@3.1.0 start
npx --yes supabase@3.1.0 test db
npx --yes supabase@3.1.0 status
```

Executed locally using Supabase CLI 3.1.0 and Docker:

- `npx --yes supabase@3.1.0 start`: local stack started; all six migrations applied successfully.
- `npx --yes supabase@3.1.0 db reset --no-seed`: clean local database recreated and all six migrations replayed successfully.
- `npx --yes supabase@3.1.0 test db`: **40/40 tests passed**, including librarian promotion denial, late-return sanctions, FIFO dispatch, copy state transitions, pickup, overdue marking, reservation expiry/reassignment, sanction expiry, and profile reactivation.
- `npx --yes supabase@3.1.0 db lint --schema public --fail-on warning`: **no schema errors or warnings**.
- `npx --yes supabase@3.1.0 migration list`: six local migration versions match the local database history.
- Local catalog inspection confirmed PostgreSQL 17.11, `cron.timezone = GMT`, and exactly one BiblioFlow maintenance job at `0 0 * * *`.

The local Supabase image used PostgreSQL 17.11.0.018. This checks PostgreSQL 17 compatibility but is not a connection to the stated hosted PostgreSQL 17.12 project. All commands above targeted the local Docker stack; they did not link or push to a remote project.

## Remote deployment commands

Obtain the project reference from the intended Supabase project dashboard; do not put credentials in the repository. Then:

```sh
npx --yes supabase@3.1.0 login
npx --yes supabase@3.1.0 link --project-ref <PROJECT_REF>
npx --yes supabase@3.1.0 migration list --remote
npx --yes supabase@3.1.0 db push --remote --dry-run
```

Review the linked project, pending migration list, and dry-run output. If the hosted schema contains objects from earlier manual SQL execution but migration history does not record them, stop and reconcile/baseline that state before pushing. Do not blindly mark migrations applied or push duplicate `CREATE` statements.

Only after explicit approval and a recovery/backup plan:

```sh
npx --yes supabase@3.1.0 db push --remote
```

No remote login, link, migration listing, dry run, or push was performed during this preparation task.
