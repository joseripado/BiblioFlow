# Progress

## Database deployment preparation

- Read and audited the six original SQL migrations.
- Moved the SQL into timestamped `supabase/migrations/` files; this is the single maintained source of truth.
- Added PostgreSQL 17 Supabase CLI configuration, an intentionally empty seed file, and pgTAP contract tests.
- Fixed invalid SQL and tightened table privileges, RLS, RPC authorization, circulation state transitions, and cron timezone checks.
- Added a deployment audit with findings, exact linking/push commands, and remote-state cautions.

## Validation

- Supabase CLI 3.1.0 is available through `npx`; Docker is installed and its daemon is reachable.
- Local Supabase 17.11 stack started, clean-replayed all six migrations, passed 40/40 pgTAP checks, and passed `db lint` without warnings.
- Verified local `cron.timezone` is `GMT` and the daily job is scheduled once at 00:00.
- No remote project has been linked or changed.

## Not yet implemented

- React web client.
- Kotlin/Android client.
- C# WPF client.
- Live Supabase project linkage and deployment.
- Initial admin provisioning on a hosted project.

## Decision

`supabase/migrations/` is the official and only migration source. `database/migrations/` is no longer a second, editable copy.
