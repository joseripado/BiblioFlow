# BiblioFlow

BiblioFlow is a Supabase-first library-management project. Its clients are intended to connect directly to Supabase Auth and Postgres; security and circulation rules are enforced in the database, not in an intermediate application backend.

## Repository status

The database schema, RLS policies, circulation RPCs, and scheduled maintenance migrations are prepared for Supabase CLI. Web, Android, and desktop applications are not yet present in this repository.

## Database source of truth

`supabase/migrations/` is the only maintained and deployable migration source. The original files formerly under `database/migrations/` were moved into this timestamped directory so that there are no duplicate SQL copies to drift.

Migration order:

1. `20261116164500_create_enums.sql`
2. `20261116164501_create_tables.sql`
3. `20261116164502_auth_triggers.sql`
4. `20261116164503_rls_policies.sql`
5. `20261116164504_business_logic.sql`
6. `20261116164505_cron_jobs.sql`

`supabase/seed.sql` intentionally contains no sample users or catalog data. SQL contract tests are in `supabase/tests/`.

## Local development and validation

Requirements: Supabase CLI and Docker.

```sh
npx --yes supabase@3.1.0 start
npx --yes supabase@3.1.0 test db
npx --yes supabase@3.1.0 status
```

The local database is configured for PostgreSQL 17. Local validation does not deploy to or link to a hosted project.

## Remote deployment

Read [docs/DEPLOYMENT_AUDIT.md](docs/DEPLOYMENT_AUDIT.md) before deployment. Link and inspect the target first; do not push until any existing remote schema and migration history have been reconciled.

```sh
npx --yes supabase@3.1.0 login
npx --yes supabase@3.1.0 link --project-ref <PROJECT_REF>
npx --yes supabase@3.1.0 migration list --remote
npx --yes supabase@3.1.0 db push --remote --dry-run
```

Only after reviewing the target, migration diff, and backup/recovery plan:

```sh
npx --yes supabase@3.1.0 db push --remote
```

No hosted project is linked or modified by this repository setup.

## Security notes

- Never put a Supabase service-role key in a client app.
- The `.env.example` file contains names only; supply real client values outside Git.
- Members cannot directly mutate loans, reservation state, sanctions, or privileged profile fields.
- Role changes are handled by a database RPC restricted to active admins.

See [docs/SECURITY.md](docs/SECURITY.md) for the database security model and [docs/DEPLOYMENT_AUDIT.md](docs/DEPLOYMENT_AUDIT.md) for findings and deployment prerequisites.
