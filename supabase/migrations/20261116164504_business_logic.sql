CREATE OR REPLACE FUNCTION public.dispatch_next_reservation(p_book_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
    v_copy_id UUID;
    v_reservation_id UUID;
BEGIN
    PERFORM 1
    FROM public.books AS b
    WHERE b.id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT c.id
    INTO v_copy_id
    FROM public.copies AS c
    WHERE c.book_id = p_book_id
      AND c.status = 'available'
    ORDER BY c.inventory_code
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF v_copy_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT r.id
    INTO v_reservation_id
    FROM public.reservations AS r
    WHERE r.book_id = p_book_id
      AND r.status = 'pending'
    ORDER BY r.requested_at, r.queue_sequence
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF v_reservation_id IS NULL THEN
        RETURN NULL;
    END IF;

    UPDATE public.copies
    SET status = 'reserved'
    WHERE id = v_copy_id;

    UPDATE public.reservations
    SET copy_id = v_copy_id,
        status = 'ready_for_pickup',
        pickup_deadline = NOW() + INTERVAL '3 days'
    WHERE id = v_reservation_id;

    RETURN v_reservation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_next_reservation(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.daily_library_maintenance()
RETURNS TABLE (
    updated_loans INTEGER,
    expired_reservations INTEGER,
    released_copies INTEGER,
    expired_sanctions INTEGER,
    reactivated_profiles INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
    v_updated_loans INTEGER := 0;
    v_expired_reservations INTEGER := 0;
    v_released_copies INTEGER := 0;
    v_expired_sanctions INTEGER := 0;
    v_reactivated_profiles INTEGER := 0;
    v_book_id UUID;
    v_dispatched UUID;
BEGIN
    UPDATE public.loans
    SET status = 'overdue'
    WHERE status = 'active'
      AND return_date IS NULL
      AND due_date < NOW();
    GET DIAGNOSTICS v_updated_loans = ROW_COUNT;

    WITH expired AS (
        UPDATE public.reservations
        SET status = 'expired'
        WHERE status = 'ready_for_pickup'
          AND pickup_deadline <= NOW()
        RETURNING copy_id
    ),
    released AS (
        UPDATE public.copies AS c
        SET status = 'available'
        FROM expired AS e
        WHERE c.id = e.copy_id
          AND c.status = 'reserved'
        RETURNING c.id
    )
    SELECT
        (SELECT COUNT(*) FROM expired)::INTEGER,
        (SELECT COUNT(*) FROM released)::INTEGER
    INTO v_expired_reservations, v_released_copies;

    FOR v_book_id IN
        SELECT DISTINCT c.book_id
        FROM public.copies AS c
        JOIN public.reservations AS r
          ON r.book_id = c.book_id
         AND r.status = 'pending'
        WHERE c.status = 'available'
        ORDER BY c.book_id
    LOOP
        LOOP
            v_dispatched := public.dispatch_next_reservation(v_book_id);
            EXIT WHEN v_dispatched IS NULL;
        END LOOP;
    END LOOP;

    UPDATE public.sanctions
    SET status = 'expired'
    WHERE status = 'active'
      AND end_date <= NOW();
    GET DIAGNOSTICS v_expired_sanctions = ROW_COUNT;

    WITH reactivated AS (
        UPDATE public.profiles AS p
        SET status = 'active'
        WHERE p.status = 'sanctioned'
          AND NOT EXISTS (
              SELECT 1
              FROM public.sanctions AS s
              WHERE s.user_id = p.id
                AND s.status = 'active'
                AND s.end_date > NOW()
          )
        RETURNING p.id
    )
    SELECT COUNT(*)::INTEGER
    INTO v_reactivated_profiles
    FROM reactivated;

    RETURN QUERY
    SELECT v_updated_loans, v_expired_reservations, v_released_copies,
           v_expired_sanctions, v_reactivated_profiles;
END;
$$;

REVOKE ALL ON FUNCTION public.daily_library_maintenance() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_loan(
    p_copy_id UUID,
    p_user_id UUID DEFAULT NULL
)
RETURNS public.loans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
    v_user_id UUID := COALESCE(p_user_id, auth.uid());
    v_user_status public.profile_status;
    v_copy_status public.copy_status;
    v_book_id UUID;
    v_loan public.loans;
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_librarian_or_admin() THEN
        RAISE EXCEPTION 'Only authenticated librarians or admins can create loans'
            USING ERRCODE = '42501';
    END IF;

    SELECT c.book_id
    INTO v_book_id
    FROM public.copies AS c
    WHERE c.id = p_copy_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Copy not found';
    END IF;

    PERFORM 1
    FROM public.books AS b
    WHERE b.id = v_book_id
    FOR UPDATE;

    SELECT p.status
    INTO v_user_status
    FROM public.profiles AS p
    WHERE p.id = v_user_id
    FOR UPDATE;

    IF NOT FOUND OR v_user_status <> 'active' THEN
        RAISE EXCEPTION 'Borrower must have an active profile';
    END IF;

    SELECT c.status, c.book_id
    INTO v_copy_status, v_book_id
    FROM public.copies AS c
    WHERE c.id = p_copy_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Copy not found';
    END IF;

    IF v_copy_status <> 'available' THEN
        RAISE EXCEPTION 'Copy is not available for loan';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.reservations AS r
        WHERE r.book_id = v_book_id
          AND r.status IN ('pending', 'ready_for_pickup')
    ) THEN
        RAISE EXCEPTION 'Outstanding reservations have priority over a new loan';
    END IF;

    INSERT INTO public.loans (user_id, copy_id, due_date)
    VALUES (v_user_id, p_copy_id, NOW() + INTERVAL '14 days')
    RETURNING * INTO v_loan;

    UPDATE public.copies
    SET status = 'on_loan'
    WHERE id = p_copy_id;

    RETURN v_loan;
END;
$$;

CREATE OR REPLACE FUNCTION public.return_loan(p_loan_id UUID)
RETURNS public.loans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
    v_loan public.loans;
    v_book_id UUID;
    v_user_id UUID;
    v_late_days INTEGER;
    v_dispatched UUID;
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_librarian_or_admin() THEN
        RAISE EXCEPTION 'Only authenticated librarians or admins can process returns'
            USING ERRCODE = '42501';
    END IF;

    SELECT l.user_id, c.book_id
    INTO v_user_id, v_book_id
    FROM public.loans AS l
    JOIN public.copies AS c ON c.id = l.copy_id
    WHERE l.id = p_loan_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan not found';
    END IF;

    PERFORM 1
    FROM public.books AS b
    WHERE b.id = v_book_id
    FOR UPDATE;

    PERFORM 1
    FROM public.profiles AS p
    WHERE p.id = v_user_id
    FOR UPDATE;

    SELECT l.*
    INTO v_loan
    FROM public.loans AS l
    WHERE l.id = p_loan_id
    FOR UPDATE;

    IF v_loan.status = 'returned' THEN
        RETURN v_loan;
    END IF;

    PERFORM 1
    FROM public.copies AS c
    WHERE c.id = v_loan.copy_id
    FOR UPDATE;

    UPDATE public.loans
    SET return_date = NOW(),
        status = 'returned'
    WHERE id = p_loan_id
    RETURNING * INTO v_loan;

    UPDATE public.copies
    SET status = 'available'
    WHERE id = v_loan.copy_id
      AND status = 'on_loan';

    v_late_days := CASE
        WHEN v_loan.return_date > v_loan.due_date
        THEN CEIL(EXTRACT(EPOCH FROM (v_loan.return_date - v_loan.due_date)) / 86400)::INTEGER
        ELSE 0
    END;

    IF v_late_days > 0 THEN
        INSERT INTO public.sanctions (user_id, loan_id, start_date, end_date, reason)
        VALUES (
            v_loan.user_id,
            v_loan.id,
            v_loan.return_date,
            v_loan.return_date + make_interval(days => v_late_days),
            'Late return: ' || v_late_days || ' day(s)'
        )
        ON CONFLICT (loan_id) WHERE status = 'active' DO NOTHING;

        UPDATE public.profiles
        SET status = CASE
            WHEN status = 'deregistered' THEN status
            ELSE 'sanctioned'::public.profile_status
        END
        WHERE id = v_loan.user_id;
    END IF;

    LOOP
        v_dispatched := public.dispatch_next_reservation(v_book_id);
        EXIT WHEN v_dispatched IS NULL;
    END LOOP;

    RETURN v_loan;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_reservation(p_book_id UUID)
RETURNS public.reservations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
    v_profile public.profiles;
    v_reservation public.reservations;
    v_reservation_id UUID;
    v_dispatched UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    PERFORM 1
    FROM public.books AS b
    WHERE b.id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book not found';
    END IF;

    SELECT p.*
    INTO v_profile
    FROM public.profiles AS p
    WHERE p.id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND OR v_profile.role <> 'member' OR v_profile.status <> 'active' THEN
        RAISE EXCEPTION 'Only active members can create reservations'
            USING ERRCODE = '42501';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.reservations AS r
        WHERE r.user_id = auth.uid()
          AND r.book_id = p_book_id
          AND r.status IN ('pending', 'ready_for_pickup')
    ) THEN
        RAISE EXCEPTION 'There is already an active reservation for this book';
    END IF;

    INSERT INTO public.reservations (user_id, book_id)
    VALUES (auth.uid(), p_book_id)
    RETURNING id INTO v_reservation_id;

    LOOP
        v_dispatched := public.dispatch_next_reservation(p_book_id);
        EXIT WHEN v_dispatched IS NULL;
    END LOOP;

    SELECT r.*
    INTO v_reservation
    FROM public.reservations AS r
    WHERE r.id = v_reservation_id;

    RETURN v_reservation;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_reservation(p_reservation_id UUID)
RETURNS public.reservations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
    v_book_id UUID;
    v_reservation public.reservations;
    v_dispatched UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    SELECT r.book_id
    INTO v_book_id
    FROM public.reservations AS r
    WHERE r.id = p_reservation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation not found';
    END IF;

    PERFORM 1
    FROM public.books AS b
    WHERE b.id = v_book_id
    FOR UPDATE;

    SELECT r.*
    INTO v_reservation
    FROM public.reservations AS r
    WHERE r.id = p_reservation_id
    FOR UPDATE;

    IF v_reservation.user_id <> auth.uid()
       AND NOT public.is_librarian_or_admin() THEN
        RAISE EXCEPTION 'You cannot cancel this reservation'
            USING ERRCODE = '42501';
    END IF;

    IF v_reservation.status NOT IN ('pending', 'ready_for_pickup') THEN
        RAISE EXCEPTION 'Only pending or ready reservations can be cancelled';
    END IF;

    UPDATE public.reservations
    SET status = 'cancelled'
    WHERE id = p_reservation_id
    RETURNING * INTO v_reservation;

    IF v_reservation.copy_id IS NOT NULL THEN
        UPDATE public.copies
        SET status = 'available'
        WHERE id = v_reservation.copy_id
          AND status = 'reserved';
    END IF;

    LOOP
        v_dispatched := public.dispatch_next_reservation(v_book_id);
        EXIT WHEN v_dispatched IS NULL;
    END LOOP;

    RETURN v_reservation;
END;
$$;

CREATE OR REPLACE FUNCTION public.pickup_reservation(p_reservation_id UUID)
RETURNS public.reservations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
    v_book_id UUID;
    v_user_id UUID;
    v_reservation public.reservations;
    v_profile_status public.profile_status;
    v_copy_status public.copy_status;
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_librarian_or_admin() THEN
        RAISE EXCEPTION 'Only authenticated librarians or admins can process pickups'
            USING ERRCODE = '42501';
    END IF;

    SELECT r.book_id, r.user_id
    INTO v_book_id, v_user_id
    FROM public.reservations AS r
    WHERE r.id = p_reservation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation not found';
    END IF;

    PERFORM 1
    FROM public.books AS b
    WHERE b.id = v_book_id
    FOR UPDATE;

    SELECT p.status
    INTO v_profile_status
    FROM public.profiles AS p
    WHERE p.id = v_user_id
    FOR UPDATE;

    SELECT r.*
    INTO v_reservation
    FROM public.reservations AS r
    WHERE r.id = p_reservation_id
    FOR UPDATE;

    IF v_reservation.status <> 'ready_for_pickup'
       OR v_reservation.pickup_deadline <= NOW()
       OR v_reservation.copy_id IS NULL THEN
        RAISE EXCEPTION 'Reservation is not available for pickup';
    END IF;

    IF v_profile_status IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION 'Borrower must have an active profile';
    END IF;

    SELECT c.status
    INTO v_copy_status
    FROM public.copies AS c
    WHERE c.id = v_reservation.copy_id
    FOR UPDATE;

    IF v_copy_status <> 'reserved' THEN
        RAISE EXCEPTION 'Assigned copy is not reserved';
    END IF;

    UPDATE public.reservations
    SET status = 'completed'
    WHERE id = p_reservation_id
    RETURNING * INTO v_reservation;

    INSERT INTO public.loans (user_id, copy_id, due_date)
    VALUES (
        v_reservation.user_id,
        v_reservation.copy_id,
        NOW() + INTERVAL '14 days'
    );

    UPDATE public.copies
    SET status = 'on_loan'
    WHERE id = v_reservation.copy_id;

    RETURN v_reservation;
END;
$$;

CREATE OR REPLACE FUNCTION public.renew_loan(p_loan_id UUID)
RETURNS public.loans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
    v_loan public.loans;
    v_profile_status public.profile_status;
    v_is_staff BOOLEAN;
    v_book_id UUID;
    v_user_id UUID;
    v_max_renewals CONSTANT INTEGER := 2;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_is_staff := public.is_librarian_or_admin();

    SELECT l.user_id, c.book_id
    INTO v_user_id, v_book_id
    FROM public.loans AS l
    JOIN public.copies AS c ON c.id = l.copy_id
    WHERE l.id = p_loan_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan not found';
    END IF;

    PERFORM 1
    FROM public.books AS b
    WHERE b.id = v_book_id
    FOR UPDATE;

    SELECT p.status
    INTO v_profile_status
    FROM public.profiles AS p
    WHERE p.id = v_user_id
    FOR UPDATE;

    SELECT l.*
    INTO v_loan
    FROM public.loans AS l
    WHERE l.id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan not found';
    END IF;

    IF v_loan.user_id <> auth.uid() AND NOT v_is_staff THEN
        RAISE EXCEPTION 'You cannot renew this loan' USING ERRCODE = '42501';
    END IF;

    IF NOT v_is_staff THEN
        IF v_profile_status IS DISTINCT FROM 'active' THEN
            RAISE EXCEPTION 'Only members with an active profile can renew loans'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    IF v_loan.status <> 'active' OR v_loan.due_date <= NOW() THEN
        RAISE EXCEPTION 'Only current, non-overdue loans can be renewed';
    END IF;

    IF v_loan.renewals_count >= v_max_renewals THEN
        RAISE EXCEPTION 'Loan renewal limit reached';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.reservations AS r
        WHERE r.book_id = v_book_id
          AND r.status IN ('pending', 'ready_for_pickup')
    ) THEN
        RAISE EXCEPTION 'Loans cannot be renewed while the book has active reservations';
    END IF;

    UPDATE public.loans
    SET due_date = due_date + INTERVAL '14 days',
        renewals_count = renewals_count + 1
    WHERE id = p_loan_id
    RETURNING * INTO v_loan;

    RETURN v_loan;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_available_copies(p_book_id UUID)
RETURNS TABLE (
    id UUID,
    inventory_code TEXT,
    location TEXT,
    status public.copy_status
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT c.id, c.inventory_code, c.location, c.status
    FROM public.copies AS c
    WHERE c.book_id = p_book_id
      AND c.status = 'available'
    ORDER BY c.inventory_code;
$$;

CREATE OR REPLACE FUNCTION public.get_user_dashboard(p_user_id UUID DEFAULT NULL)
RETURNS TABLE (
    active_loans INTEGER,
    overdue_loans INTEGER,
    pending_reservations INTEGER,
    ready_pickups INTEGER,
    active_sanctions INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
    v_user_id UUID := COALESCE(p_user_id, auth.uid());
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF v_user_id <> auth.uid() AND NOT public.is_librarian_or_admin() THEN
        RAISE EXCEPTION 'You cannot view another user dashboard'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        (SELECT COUNT(*)::INTEGER FROM public.loans WHERE user_id = v_user_id AND status = 'active'),
        (SELECT COUNT(*)::INTEGER FROM public.loans WHERE user_id = v_user_id AND status = 'overdue'),
        (SELECT COUNT(*)::INTEGER FROM public.reservations WHERE user_id = v_user_id AND status = 'pending'),
        (SELECT COUNT(*)::INTEGER FROM public.reservations WHERE user_id = v_user_id AND status = 'ready_for_pickup'),
        (SELECT COUNT(*)::INTEGER FROM public.sanctions WHERE user_id = v_user_id AND status = 'active');
END;
$$;

CREATE OR REPLACE FUNCTION public.set_profile_role(
    p_user_id UUID,
    p_role public.profile_role
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
    v_old_role public.profile_role;
    v_target_status public.profile_status;
    v_other_active_admins BIGINT;
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only an active admin can change profile roles'
            USING ERRCODE = '42501';
    END IF;

    SELECT p.role, p.status
    INTO v_old_role, v_target_status
    FROM public.profiles AS p
    WHERE p.id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    IF p_role IN ('librarian', 'admin') AND v_target_status <> 'active' THEN
        RAISE EXCEPTION 'Only active profiles can be assigned a staff role';
    END IF;

    IF v_old_role = 'admin' AND p_role <> 'admin' THEN
        SELECT COUNT(*)
        INTO v_other_active_admins
        FROM public.profiles AS p
        WHERE p.role = 'admin'
          AND p.status = 'active'
          AND p.id <> p_user_id;

        IF v_other_active_admins = 0 THEN
            RAISE EXCEPTION 'At least one active admin must remain';
        END IF;
    END IF;

    UPDATE public.profiles
    SET role = p_role
    WHERE id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_loan(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.return_loan(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_reservation(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cancel_reservation(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pickup_reservation(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.renew_loan(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_available_copies(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_user_dashboard(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_profile_role(UUID, public.profile_role) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_loan(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.return_loan(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_reservation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_reservation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pickup_reservation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.renew_loan(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_available_copies(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_dashboard(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_profile_role(UUID, public.profile_role) TO authenticated;
