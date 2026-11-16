ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.copies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sanctions ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles AS p
        WHERE p.id = auth.uid()
          AND p.role = 'admin'
          AND p.status = 'active'
    );
$$;

CREATE OR REPLACE FUNCTION public.is_librarian_or_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles AS p
        WHERE p.id = auth.uid()
          AND p.status = 'active'
          AND p.role IN ('librarian', 'admin')
    );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_librarian_or_admin() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_librarian_or_admin() TO authenticated;

REVOKE ALL ON TABLE
    public.profiles,
    public.categories,
    public.books,
    public.copies,
    public.loans,
    public.reservations,
    public.sanctions
FROM PUBLIC, anon, authenticated;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON public.categories, public.books, public.copies TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.categories, public.books, public.copies TO authenticated;
GRANT SELECT ON public.profiles, public.loans, public.reservations, public.sanctions TO authenticated;
GRANT UPDATE (full_name) ON public.profiles TO authenticated;

CREATE POLICY profiles_select_own_or_staff
    ON public.profiles FOR SELECT TO authenticated
    USING (id = auth.uid() OR public.is_librarian_or_admin());

CREATE POLICY profiles_update_own_name
    ON public.profiles FOR UPDATE TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

CREATE POLICY categories_read_authenticated
    ON public.categories FOR SELECT TO authenticated
    USING (auth.uid() IS NOT NULL);

CREATE POLICY categories_insert_staff
    ON public.categories FOR INSERT TO authenticated
    WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY categories_update_staff
    ON public.categories FOR UPDATE TO authenticated
    USING (public.is_librarian_or_admin())
    WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY categories_delete_staff
    ON public.categories FOR DELETE TO authenticated
    USING (public.is_librarian_or_admin());

CREATE POLICY books_read_authenticated
    ON public.books FOR SELECT TO authenticated
    USING (auth.uid() IS NOT NULL);

CREATE POLICY books_insert_staff
    ON public.books FOR INSERT TO authenticated
    WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY books_update_staff
    ON public.books FOR UPDATE TO authenticated
    USING (public.is_librarian_or_admin())
    WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY books_delete_staff
    ON public.books FOR DELETE TO authenticated
    USING (public.is_librarian_or_admin());

CREATE POLICY copies_read_authenticated
    ON public.copies FOR SELECT TO authenticated
    USING (auth.uid() IS NOT NULL);

CREATE POLICY copies_insert_staff
    ON public.copies FOR INSERT TO authenticated
    WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY copies_update_staff
    ON public.copies FOR UPDATE TO authenticated
    USING (public.is_librarian_or_admin())
    WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY copies_delete_staff
    ON public.copies FOR DELETE TO authenticated
    USING (public.is_librarian_or_admin());

CREATE POLICY loans_select_own_or_staff
    ON public.loans FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.is_librarian_or_admin());

CREATE POLICY reservations_select_own_or_staff
    ON public.reservations FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.is_librarian_or_admin());

CREATE POLICY sanctions_select_own_or_staff
    ON public.sanctions FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.is_librarian_or_admin());
