# BiblioFlow

BiblioFlow is a library-management MVP designed around the Supabase-first architecture described in the project brief: three independent clients (web, Android, desktop) share the same PostgreSQL database and auth layer, with the security model enforced in the database via Row Level Security, triggers, and transactional SQL functions.

## Repository status

This repository currently contains the database migration scaffold and documentation required to start the Supabase implementation. The project is intentionally structured so the database schema, access control, and business rules are defined in versioned SQL migrations instead of application-specific backends.

## Architecture

- Web: React + TypeScript + Vite
- Android: Kotlin + Jetpack Compose
- Desktop: .NET 8 + WPF
- Shared services: Supabase Auth + Postgres + Row Level Security
- Direct client-to-Supabase communication only

## Database migration sequence

- `001_create_enums.sql`: database enums for role, status, and domain values
- `002_create_tables.sql`: core tables for profiles, books, copies, loans, reservations, sanctions, and metadata
- `003_auth_triggers.sql`: profile creation trigger for `auth.users`
- `004_rls_policies.sql`: row-level security for authenticated clients
- `005_business_logic.sql`: transactional rules, RPCs, and maintenance functions
- `006_cron_jobs.sql`: daily maintenance scheduling via `pg_cron`

## Quick start

1. Create or connect a Supabase project.
2. Apply migrations in order using the Supabase CLI or SQL runner:
   - `supabase db push`
   - or run each migration file in the listed sequence.
3. Configure the relevant client environment variables.
4. Use the security documentation and migration specs as the source of truth for access rules.

## Operational notes

- No secrets or service-role credentials are stored in this repository.
- Client apps must never be trusted to enforce business rules.
- The database is the source of truth for permissions, validation, and daily maintenance tasks.

## Documentation

- `docs/SECURITY.md`: RLS model and policy overview
- `PROGRESS.md`: project status and next steps

## Current MVP goal

The project is positioned to move from architecture/design into a serviceable implementation once a Supabase instance is available. The database layer is organized to support the required roles, catalog, circulation, reservations, and sanctions flow without creating a separate application backend.
