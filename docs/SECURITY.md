# Database security model

Supabase Auth and PostgreSQL are the enforcement points for authorization. Client-side checks are only for presentation and must not replace RLS or RPC validation.

## Database grants and RLS

All seven application tables have RLS enabled. The migrations first revoke client table privileges and then grant only the needed operations:

- Authenticated users can read the catalog and their own profile/circulation records, subject to RLS.
- Members can update only `profiles.full_name`.
- Members have no direct write grants on loans, reservations, or sanctions.
- Catalog writes have table grants for authenticated users but are restricted by staff-only RLS policies.
- No direct client grant permits changes to `profiles.role` or `profiles.status`.

The client-facing functions `is_admin` and `is_librarian_or_admin` are `SECURITY DEFINER`, use a fixed `search_path`, and have execute grants only for authenticated users. All other privileged functions similarly revoke default `PUBLIC` execution.

## Privileged operations

- `create_loan`, `return_loan`, `pickup_reservation`, and staff catalog changes require an active librarian or admin.
- `create_reservation` is restricted to active member profiles.
- `renew_loan` checks ownership, active status, current loan state, renewal count, and active reservations.
- `set_profile_role` requires an active admin. It prevents removing the last active admin. A librarian cannot call it successfully, and direct profile role updates are not granted.
- The initial admin must be provisioned through a trusted Supabase SQL Editor/administrative process after a profile exists. Never expose a database-owner or service-role credential to an app.

## `SECURITY DEFINER` safeguards

Privileged functions use explicit schema-qualified object references and `SET search_path = pg_catalog, public, auth, pg_temp` (or a narrower fixed path for the timestamp trigger). Execute privileges are revoked from `PUBLIC` and `anon`; only the RPCs intended for clients are granted to `authenticated`. Trigger and scheduled-maintenance functions are not client-callable.

## Circulation invariants

- Partial unique indexes prevent concurrent active/overdue loans for the same copy, duplicate active user/book reservations, ready reservations on the same copy, and duplicate active sanctions per loan.
- Reservations receive an identity queue sequence to deterministically preserve FIFO order when timestamps tie.
- Sanctions have a composite foreign key to the same borrower/loan pair.
- Reservation assignment enforces book/copy consistency and reservation state/date checks.
- Return and reservation dispatch execute transactionally. Dispatch serializes on the book row and uses `FOR UPDATE SKIP LOCKED`.
- Daily maintenance is scheduled at 00:00 UTC. Migration 6 refuses to schedule unless `cron.timezone` is UTC or an equivalent GMT value.

## Operational cautions

- The Supabase `service_role` bypasses RLS and must never be embedded in client applications.
- The SQL migrations must be applied once and tracked by Supabase CLI. Do not manually rerun them against an existing project.
- Before pushing to a hosted database, inspect both the remote migration history and actual schema. A schema created manually without matching migration records needs a deliberate baseline/reconciliation step.
