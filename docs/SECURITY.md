# Security model

This project relies on PostgreSQL as the enforcement point for all critical access rules. Client applications are assumed to be thin consumers of Supabase Auth and the Data API.

## Principles

- Do not create a custom backend service.
- Keep all business validation in SQL and RLS.
- Allow clients only the minimum necessary CRUD operations.
- Protect role and status transitions in the database.
- Never rely on a frontend UI alone to prevent abuse.

## Roles

- `member`: regular library user
- `librarian`: operational staff with circulation and catalog management permissions
- `admin`: full administrative control, with explicit safeguards against privileged changes

## Primary controls

### RLS

Each table exposed to clients uses `ENABLE ROW LEVEL SECURITY`. Policies are separated by operation type whenever possible.

- Members can read the catalog and their own records.
- Members cannot alter `role`, `status`, or copy state.
- Librarians can manage circulation and catalog content but cannot promote users to `admin`.
- Admins manage administrative data and role transitions in a controlled manner.

### Secure role checks

Database helper functions determine the current user's role from the `profiles` table. They use a controlled `search_path` and `SECURITY DEFINER` only where needed for validation.

### Restriction on profile mutation

The profile table separates read, update, and delete operations. The policy set prevents unintended changes to privileged fields while allowing ordinary members to update only their non-sensitive profile data.

## Business rules in PostgreSQL

The SQL layer enforces the circulation rules, including:

- one active loan per copy
- duplicate active reservation protections
- sanction lifecycle tracking
- reservation FIFO assignment logic
- automatic overdue and pickup expiry maintenance

## Important guardrails

- Service-role credentials must never be used by applications.
- The `auth.uid()` context must be checked before performing operations.
- Users must not be able to elevate their own privileges.
- Administrative changes must be treated as privileged operations and documented.
