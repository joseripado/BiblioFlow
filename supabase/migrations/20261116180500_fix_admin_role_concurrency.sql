
-- ============================================================
-- BiblioFlow
-- Migration: Protect last active administrator against races
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_profile_role(
    p_user_id UUID,
    p_role public.profile_role
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $function$
DECLARE
    v_old_role public.profile_role;
    v_target_status public.profile_status;
    v_other_active_admins BIGINT;
BEGIN
    -- Serialize all administrator role changes.
    -- The transaction-level lock is released automatically
    -- when the transaction commits or rolls back.
    PERFORM pg_catalog.pg_advisory_xact_lock(20261116, 1);

    -- Verify the caller after acquiring the lock.
    IF auth.uid() IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only an active admin can change profile roles'
            USING ERRCODE = '42501';
    END IF;

    -- Lock the target profile.
    SELECT p.role, p.status
    INTO v_old_role, v_target_status
    FROM public.profiles AS p
    WHERE p.id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    -- Staff roles can only be assigned to active profiles.
    IF p_role IN ('librarian', 'admin')
       AND v_target_status <> 'active' THEN
        RAISE EXCEPTION 'Only active profiles can be assigned a staff role';
    END IF;

    -- Never allow the last active administrator to be demoted.
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
$function$;
