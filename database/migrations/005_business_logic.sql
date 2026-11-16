CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS public.profile_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT role
  FROM public.profiles
  WHERE id = auth.uid();
$$;

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
SET search_path = public, pg_temp
AS $$
DECLARE
    v_updated_loans INTEGER := 0;
    v_expired_reservations INTEGER := 0;
    v_released_copies INTEGER := 0;
    v_expired_sanctions INTEGER := 0;
    v_reactivated_profiles INTEGER := 0;
BEGIN
    UPDATE public.loans
    SET status = 'overdue', updated_at = NOW()
    WHERE status = 'active'
      AND return_date IS NULL
      AND due_date < NOW();

    GET DIAGNOSTICS v_updated_loans = ROW_COUNT;

    WITH expired_res AS (
        UPDATE public.reservations
        SET status = 'expired', updated_at = NOW()
        WHERE status = 'ready_for_pickup'
          AND pickup_deadline < NOW()
        RETURNING copy_id
    )
    UPDATE public.copies c
    SET status = 'available', updated_at = NOW()
    FROM expired_res er
    WHERE c.id = er.copy_id;

    GET DIAGNOSTICS v_expired_reservations = ROW_COUNT;

    WITH fifo AS (
        SELECT DISTINCT ON (r.book_id)
            r.id,
            r.book_id,
            c.id AS copy_id
        FROM public.reservations r
        JOIN public.copies c
          ON c.book_id = r.book_id
        WHERE r.status = 'pending'
          AND c.status = 'available'
        ORDER BY r.book_id, r.requested_at ASC, r.id ASC
    )
    UPDATE public.reservations r
    SET status = 'ready_for_pickup',
        pickup_deadline = NOW() + INTERVAL '3 days',
        updated_at = NOW()
    FROM fifo
    WHERE r.id = fifo.id;

    WITH fifo AS (
        SELECT DISTINCT ON (r.book_id)
            r.id,
            c.id AS copy_id,
            r.book_id
        FROM public.reservations r
        JOIN public.copies c
          ON c.book_id = r.book_id
        WHERE r.status = 'ready_for_pickup'
          AND c.status = 'available'
        ORDER BY r.book_id, r.requested_at ASC, r.id ASC
    )
    UPDATE public.copies c
    SET status = 'reserved', updated_at = NOW()
    FROM fifo
    WHERE c.id = fifo.copy_id;

    UPDATE public.sanctions
    SET status = 'expired', updated_at = NOW()
    WHERE status = 'active'
      AND end_date < NOW();

    GET DIAGNOSTICS v_expired_sanctions = ROW_COUNT;

    WITH cleared AS (
        UPDATE public.profiles p
        SET status = 'active', updated_at = NOW()
        WHERE p.status = 'sanctioned'
          AND NOT EXISTS (
            SELECT 1 FROM public.sanctions s
            WHERE s.user_id = p.id
              AND s.status = 'active'
          )
        RETURNING p.id
    )
    SELECT COUNT(*) INTO v_reactivated_profiles FROM cleared;

    RETURN QUERY
    SELECT v_updated_loans, v_expired_reservations, v_released_copies, v_expired_sanctions, v_reactivated_profiles;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_loan(p_copy_id UUID, p_user_id UUID DEFAULT NULL)
RETURNS public.loans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_copy RECORD;
    v_user_id UUID;
    v_loan public.loans;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT public.is_librarian_or_admin() THEN
        RAISE EXCEPTION 'Only librarians and admins can create loans';
    END IF;

    v_user_id := COALESCE(p_user_id, auth.uid());

    SELECT * INTO v_copy
    FROM public.copies c
    WHERE c.id = p_copy_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Copy not found';
    END IF;

    IF v_copy.status <> 'available' THEN
        RAISE EXCEPTION 'Copy is not available for loan';
    END IF;

    INSERT INTO public.loans (user_id, copy_id, due_date, status)
    VALUES (v_user_id, p_copy_id, NOW() + INTERVAL '14 days', 'active')
    RETURNING * INTO v_loan;

    UPDATE public.copies
    SET status = 'on_loan', updated_at = NOW()
    WHERE id = p_copy_id;

    RETURN v_loan;
END;
$$;

CREATE OR REPLACE FUNCTION public.return_loan(p_loan_id UUID)
RETURNS public.loans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_loan public.loans;
    v_delay_days INTEGER;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT public.is_librarian_or_admin() THEN
        RAISE EXCEPTION 'Only librarians and admins can process returns';
    END IF;

    SELECT * INTO v_loan
    FROM public.loans
    WHERE id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan not found';
    END IF;

    IF v_loan.status = 'returned' THEN
        RAISE EXCEPTION 'Loan already returned';
    END IF;

    UPDATE public.loans
    SET return_date = NOW(), status = 'returned', updated_at = NOW()
    WHERE id = p_loan_id;

    UPDATE public.copies
    SET status = 'available', updated_at = NOW()
    WHERE id = v_loan.copy_id;

    v_delay_days := GREATEST(0, DATE_PART('day', NOW() - v_loan.due_date)::INTEGER);
    IF v_delay_days > 0 THEN
        INSERT INTO public.sanctions (user_id, loan_id, start_date, end_date, reason, status)
        SELECT v_loan.user_id,
               v_loan.id,
               NOW(),
               NOW() + (v_delay_days || ' days')::interval,
               'Late return penalty',
               'active'
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.sanctions s
            WHERE s.loan_id = v_loan.id
              AND s.status = 'active'
        );

        UPDATE public.profiles
        SET status = 'sanctioned', updated_at = NOW()
        WHERE id = v_loan.user_id;
    END IF;

    SELECT * INTO v_loan FROM public.loans WHERE id = p_loan_id;
    RETURN v_loan;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_reservation(p_book_id UUID, p_copy_id UUID DEFAULT NULL)
RETURNS public.reservations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_reservation public.reservations;
    v_profile public.profiles;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_profile.status <> 'active' THEN
        RAISE EXCEPTION 'User is not active';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.reservations r
        WHERE r.user_id = auth.uid()
          AND r.book_id = p_book_id
          AND r.status IN ('pending', 'ready_for_pickup')
    ) THEN
        RAISE EXCEPTION 'There is already an active reservation for this book';
    END IF;

    INSERT INTO public.reservations (user_id, book_id, copy_id, status)
    VALUES (auth.uid(), p_book_id, p_copy_id, 'pending')
    RETURNING * INTO v_reservation;

    RETURN v_reservation;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_reservation(p_reservation_id UUID)
RETURNS public.reservations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_reservation public.reservations;
BEGIN
    SELECT * INTO v_reservation
    FROM public.reservations
    WHERE id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation not found';
    END IF;

    IF v_reservation.user_id <> auth.uid() AND NOT public.is_librarian_or_admin() THEN
        RAISE EXCEPTION 'You cannot cancel this reservation';
    END IF;

    UPDATE public.reservations
    SET status = 'cancelled', updated_at = NOW()
    WHERE id = p_reservation_id;

    SELECT * INTO v_reservation FROM public.reservations WHERE id = p_reservation_id;
    RETURN v_reservation;
END;
$$;

CREATE OR REPLACE FUNCTION public.pickup_reservation(p_reservation_id UUID)
RETURNS public.reservations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_reservation public.reservations;
BEGIN
    IF NOT public.is_librarian_or_admin() THEN
        RAISE EXCEPTION 'Only librarians and admins can mark pickups';
    END IF;

    SELECT * INTO v_reservation
    FROM public.reservations
    WHERE id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation not found';
    END IF;

    IF v_reservation.status <> 'ready_for_pickup' THEN
        RAISE EXCEPTION 'Reservation is not ready for pickup';
    END IF;

    UPDATE public.reservations
    SET status = 'completed', updated_at = NOW()
    WHERE id = p_reservation_id;

    UPDATE public.copies
    SET status = 'on_loan', updated_at = NOW()
    WHERE id = v_reservation.copy_id;

    SELECT * INTO v_reservation FROM public.reservations WHERE id = p_reservation_id;
    RETURN v_reservation;
END;
$$;

CREATE OR REPLACE FUNCTION public.renew_loan(p_loan_id UUID)
RETURNS public.loans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_loan public.loans;
    v_max_renewals INTEGER := 2;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_loan
    FROM public.loans
    WHERE id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan not found';
    END IF;

    IF v_loan.status <> 'active' THEN
        RAISE EXCEPTION 'Only active loans can be renewed';
    END IF;

    IF v_loan.renewals_count >= v_max_renewals THEN
        RAISE EXCEPTION 'Loan renewal limit reached';
    END IF;

    UPDATE public.loans
    SET due_date = due_date + INTERVAL '14 days',
        renewals_count = renewals_count + 1,
        updated_at = NOW()
    WHERE id = p_loan_id;

    SELECT * INTO v_loan FROM public.loans WHERE id = p_loan_id;
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
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.id, c.inventory_code, c.location, c.status
  FROM public.copies c
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
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID := COALESCE(p_user_id, auth.uid());
BEGIN
    RETURN QUERY
    SELECT
        (SELECT COUNT(*) FROM public.loans WHERE user_id = v_user_id AND status = 'active')::INTEGER,
        (SELECT COUNT(*) FROM public.loans WHERE user_id = v_user_id AND status = 'overdue')::INTEGER,
        (SELECT COUNT(*) FROM public.reservations WHERE user_id = v_user_id AND status = 'pending')::INTEGER,
        (SELECT COUNT(*) FROM public.reservations WHERE user_id = v_user_id AND status = 'ready_for_pickup')::INTEGER,
        (SELECT COUNT(*) FROM public.sanctions WHERE user_id = v_user_id AND status = 'active')::INTEGER;
END;
$$;
