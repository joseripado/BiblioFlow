CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = extensions, public;

BEGIN;

SELECT plan(40);

INSERT INTO auth.users (id, email) VALUES
    ('10000000-0000-0000-0000-000000000001', 'staff@example.test'),
    ('10000000-0000-0000-0000-000000000002', 'borrower@example.test'),
    ('10000000-0000-0000-0000-000000000003', 'first-member@example.test'),
    ('10000000-0000-0000-0000-000000000004', 'second-member@example.test');

UPDATE public.profiles
SET role = 'librarian'
WHERE id = '10000000-0000-0000-0000-000000000001';

INSERT INTO public.books (id, title, authors, isbn)
VALUES (
    '20000000-0000-0000-0000-000000000001',
    'Database test fixture',
    'BiblioFlow test',
    '0000000000001'
);

INSERT INTO public.copies (id, book_id, inventory_code)
VALUES (
    '30000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    'BF-TEST-1'
);

SELECT has_table('profiles', 'public');
SELECT has_table('categories', 'public');
SELECT has_table('books', 'public');
SELECT has_table('copies', 'public');
SELECT has_table('loans', 'public');
SELECT has_table('reservations', 'public');
SELECT has_table('sanctions', 'public');

SELECT ok(
    (SELECT bool_and(c.relrowsecurity)
     FROM pg_catalog.pg_class AS c
     JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname IN ('profiles', 'categories', 'books', 'copies', 'loans', 'reservations', 'sanctions')),
    'RLS is enabled on each application table'
);

SELECT ok(has_column_privilege('authenticated', 'public.profiles', 'full_name', 'UPDATE'),
          'members may update their profile name');
SELECT ok(NOT has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE'),
          'clients cannot update profile roles directly');
SELECT ok(NOT has_column_privilege('authenticated', 'public.profiles', 'status', 'UPDATE'),
          'clients cannot update profile status directly');
SELECT ok(NOT has_table_privilege('authenticated', 'public.loans', 'INSERT'),
          'clients cannot insert loans directly');
SELECT ok(NOT has_table_privilege('authenticated', 'public.loans', 'UPDATE'),
          'clients cannot update loan state directly');
SELECT ok(NOT has_table_privilege('authenticated', 'public.reservations', 'INSERT'),
          'clients must use the reservation RPC');
SELECT ok(NOT has_table_privilege('authenticated', 'public.reservations', 'UPDATE'),
          'clients cannot update reservation state directly');
SELECT ok(NOT has_table_privilege('authenticated', 'public.sanctions', 'INSERT'),
          'clients cannot insert sanctions directly');
SELECT ok(NOT has_table_privilege('authenticated', 'public.sanctions', 'UPDATE'),
          'clients cannot update sanction state directly');

SELECT ok(
    to_regprocedure('public.create_loan(uuid,uuid)') IS NOT NULL
    AND to_regprocedure('public.return_loan(uuid)') IS NOT NULL
    AND to_regprocedure('public.create_reservation(uuid)') IS NOT NULL
    AND to_regprocedure('public.cancel_reservation(uuid)') IS NOT NULL
    AND to_regprocedure('public.pickup_reservation(uuid)') IS NOT NULL
    AND to_regprocedure('public.renew_loan(uuid)') IS NOT NULL
    AND to_regprocedure('public.get_available_copies(uuid)') IS NOT NULL
    AND to_regprocedure('public.get_user_dashboard(uuid)') IS NOT NULL
    AND to_regprocedure('public.set_profile_role(uuid,public.profile_role)') IS NOT NULL,
    'the client RPC surface is implemented'
);

SELECT ok(
    has_function_privilege('authenticated', 'public.create_reservation(uuid)', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.set_profile_role(uuid,public.profile_role)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.create_reservation(uuid)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.set_profile_role(uuid,public.profile_role)', 'EXECUTE'),
    'authenticated clients may call RPCs, while anonymous clients may not'
);

SELECT ok(
    NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS p
        WHERE p.oid IN (
            'public.handle_new_user()'::regprocedure,
            'public.is_admin()'::regprocedure,
            'public.is_librarian_or_admin()'::regprocedure,
            'public.dispatch_next_reservation(uuid)'::regprocedure,
            'public.daily_library_maintenance()'::regprocedure,
            'public.create_loan(uuid,uuid)'::regprocedure,
            'public.return_loan(uuid)'::regprocedure,
            'public.create_reservation(uuid)'::regprocedure,
            'public.cancel_reservation(uuid)'::regprocedure,
            'public.pickup_reservation(uuid)'::regprocedure,
            'public.renew_loan(uuid)'::regprocedure,
            'public.get_user_dashboard(uuid)'::regprocedure,
            'public.set_profile_role(uuid,public.profile_role)'::regprocedure
        )
        AND (
            NOT p.prosecdef
            OR NOT EXISTS (
                SELECT 1
                FROM unnest(p.proconfig) AS setting
                WHERE setting LIKE 'search_path=pg_catalog,%'
                  AND setting LIKE '%pg_temp'
            )
        )
    ),
    'privileged functions are SECURITY DEFINER with a fixed safe search_path'
);

SELECT ok(
    EXISTS (
        SELECT 1
        FROM cron.job
        WHERE jobname = 'biblioflow-daily-maintenance'
          AND schedule = '0 0 * * *'
    ),
    'daily maintenance is scheduled at midnight'
);

SELECT ok(
    upper(trim(current_setting('cron.timezone', true))) IN ('UTC', 'GMT', 'ETC/UTC', 'ETC/GMT'),
    'pg_cron uses the documented UTC-equivalent timezone'
);

SELECT ok(
    EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = '10000000-0000-0000-0000-000000000003'
          AND role = 'member'
          AND status = 'active'
    ),
    'the auth trigger creates a default active member profile'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    'SELECT public.set_profile_role(''10000000-0000-0000-0000-000000000003'', ''admin''::public.profile_role)',
    '42501',
    'Only an active admin can change profile roles',
    'a librarian cannot promote a user to admin'
);
SELECT is(
    (public.create_loan(
        '30000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000002'
    )).status,
    'active'::public.loan_status,
    'a librarian can create an active loan for a member'
);
RESET ROLE;

SELECT ok(
    (SELECT status = 'on_loan'
     FROM public.copies
     WHERE id = '30000000-0000-0000-0000-000000000001'),
    'creating a loan marks its copy on loan'
);

UPDATE public.loans
SET loan_date = NOW() - INTERVAL '3 days',
    due_date = NOW() - INTERVAL '1 day'
WHERE copy_id = '30000000-0000-0000-0000-000000000001';

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
SET LOCAL ROLE authenticated;
SELECT is(
    (public.create_reservation('20000000-0000-0000-0000-000000000001')).status,
    'pending'::public.reservation_status,
    'the first reservation joins the pending queue while the copy is loaned'
);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
SET LOCAL ROLE authenticated;
SELECT is(
    (public.create_reservation('20000000-0000-0000-0000-000000000001')).status,
    'pending'::public.reservation_status,
    'the second reservation joins the pending queue'
);
RESET ROLE;

SELECT ok(
    (SELECT count(*) = 2
     FROM public.reservations
     WHERE book_id = '20000000-0000-0000-0000-000000000001'
       AND status = 'pending'),
    'members can queue reservations while all copies are loaned'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT is(
    (public.return_loan(
        (SELECT id FROM public.loans WHERE copy_id = '30000000-0000-0000-0000-000000000001')
    )).status,
    'returned'::public.loan_status,
    'returning a loan records the returned state'
);
RESET ROLE;

SELECT ok(
    EXISTS (
        SELECT 1
        FROM public.sanctions
        WHERE user_id = '10000000-0000-0000-0000-000000000002'
          AND status = 'active'
          AND end_date - start_date = INTERVAL '1 day'
    )
    AND EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = '10000000-0000-0000-0000-000000000002'
          AND status = 'sanctioned'
    ),
    'a one-day late return creates a one-day sanction and sanctions its borrower'
);

SELECT ok(
    EXISTS (
        SELECT 1
        FROM public.reservations
        WHERE user_id = '10000000-0000-0000-0000-000000000003'
          AND status = 'ready_for_pickup'
          AND pickup_deadline > NOW()
          AND pickup_deadline <= NOW() + INTERVAL '3 days'
    ),
    'return dispatches the oldest reservation with a three-day pickup window'
);
SELECT ok(
    (SELECT status = 'reserved'
     FROM public.copies
     WHERE id = '30000000-0000-0000-0000-000000000001'),
    'the dispatched copy is marked reserved'
);
SELECT ok(
    EXISTS (
        SELECT 1
        FROM public.reservations
        WHERE user_id = '10000000-0000-0000-0000-000000000004'
          AND status = 'pending'
    ),
    'the later reservation remains pending when only one copy is available'
);

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT is(
    (public.pickup_reservation(
        (SELECT id FROM public.reservations
         WHERE user_id = '10000000-0000-0000-0000-000000000003')
    )).status,
    'completed'::public.reservation_status,
    'pickup completes the FIFO reservation'
);
RESET ROLE;
SELECT ok(
    (SELECT status = 'on_loan'
     FROM public.copies
     WHERE id = '30000000-0000-0000-0000-000000000001')
    AND EXISTS (
        SELECT 1
        FROM public.loans
        WHERE user_id = '10000000-0000-0000-0000-000000000003'
          AND copy_id = '30000000-0000-0000-0000-000000000001'
          AND status = 'active'
    ),
    'pickup creates a loan and marks the copy on loan'
);

INSERT INTO public.copies (id, book_id, inventory_code)
VALUES (
    '30000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000001',
    'BF-TEST-2'
);

UPDATE public.reservations
SET requested_at = NOW() - INTERVAL '2 days',
    copy_id = '30000000-0000-0000-0000-000000000002',
    status = 'ready_for_pickup',
    pickup_deadline = NOW() - INTERVAL '1 minute'
WHERE user_id = '10000000-0000-0000-0000-000000000004'
  AND book_id = '20000000-0000-0000-0000-000000000001';

UPDATE public.copies
SET status = 'reserved'
WHERE id = '30000000-0000-0000-0000-000000000002';

INSERT INTO public.reservations (user_id, book_id, requested_at)
VALUES (
    '10000000-0000-0000-0000-000000000003',
    '20000000-0000-0000-0000-000000000001',
    NOW() - INTERVAL '1 minute'
);

UPDATE public.loans
SET loan_date = NOW() - INTERVAL '3 days',
    due_date = NOW() - INTERVAL '1 hour'
WHERE user_id = '10000000-0000-0000-0000-000000000003'
  AND copy_id = '30000000-0000-0000-0000-000000000001'
  AND status = 'active';

UPDATE public.sanctions
SET start_date = NOW() - INTERVAL '2 days',
    end_date = NOW() - INTERVAL '1 minute'
WHERE user_id = '10000000-0000-0000-0000-000000000002'
  AND status = 'active';

SELECT ok(
    (SELECT updated_loans = 1
            AND expired_reservations = 1
            AND released_copies = 1
            AND expired_sanctions = 1
            AND reactivated_profiles = 1
     FROM public.daily_library_maintenance()),
    'daily maintenance reports and processes overdue, expired, and released records'
);
SELECT ok(
    EXISTS (
        SELECT 1
        FROM public.loans
        WHERE user_id = '10000000-0000-0000-0000-000000000003'
          AND copy_id = '30000000-0000-0000-0000-000000000001'
          AND status = 'overdue'
    ),
    'daily maintenance marks unpaid loans overdue'
);
SELECT ok(
    EXISTS (
        SELECT 1
        FROM public.reservations
        WHERE user_id = '10000000-0000-0000-0000-000000000004'
          AND status = 'expired'
    )
    AND EXISTS (
        SELECT 1
        FROM public.reservations
        WHERE user_id = '10000000-0000-0000-0000-000000000003'
          AND copy_id = '30000000-0000-0000-0000-000000000002'
          AND status = 'ready_for_pickup'
    )
    AND (SELECT status = 'reserved'
         FROM public.copies
         WHERE id = '30000000-0000-0000-0000-000000000002'),
    'expired pickup copies are released and reassigned FIFO'
);
SELECT ok(
    EXISTS (
        SELECT 1
        FROM public.sanctions
        WHERE user_id = '10000000-0000-0000-0000-000000000002'
          AND status = 'expired'
    )
    AND EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = '10000000-0000-0000-0000-000000000002'
          AND status = 'active'
    ),
    'maintenance expires sanctions and reactivates eligible profiles'
);

SELECT * FROM finish();
ROLLBACK;
