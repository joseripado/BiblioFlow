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
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
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
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.status = 'active'
      AND p.role IN ('librarian', 'admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_member()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.status = 'active'
      AND p.role = 'member'
  );
$$;

CREATE POLICY "profiles_select_own_and_staff" ON public.profiles
  FOR SELECT
  USING (id = auth.uid() OR public.is_librarian_or_admin());

CREATE POLICY "profiles_update_own_non_privileged_fields" ON public.profiles
  FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (
    id = auth.uid() AND
    NEW.role = OLD.role AND
    NEW.status = OLD.status
  );

CREATE POLICY "profiles_update_by_admin" ON public.profiles
  FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "profiles_delete_by_admin" ON public.profiles
  FOR DELETE
  USING (public.is_admin());

CREATE POLICY "categories_read_all" ON public.categories
  FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "categories_manage_staff" ON public.categories
  FOR ALL
  USING (public.is_librarian_or_admin())
  WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY "books_read_all" ON public.books
  FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "books_manage_staff" ON public.books
  FOR ALL
  USING (public.is_librarian_or_admin())
  WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY "copies_read_all" ON public.copies
  FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "copies_manage_staff" ON public.copies
  FOR ALL
  USING (public.is_librarian_or_admin())
  WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY "loans_member_select_own" ON public.loans
  FOR SELECT
  USING (user_id = auth.uid() OR public.is_librarian_or_admin());

CREATE POLICY "loans_staff_manage" ON public.loans
  FOR INSERT
  WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY "loans_staff_update" ON public.loans
  FOR UPDATE
  USING (public.is_librarian_or_admin())
  WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY "reservations_member_insert_own" ON public.reservations
  FOR INSERT
  WITH CHECK (user_id = auth.uid() AND auth.role() = 'authenticated');

CREATE POLICY "reservations_select_own_or_staff" ON public.reservations
  FOR SELECT
  USING (user_id = auth.uid() OR public.is_librarian_or_admin());

CREATE POLICY "reservations_update_own_only_safe_fields" ON public.reservations
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid() AND
    NEW.status IN ('pending', 'cancelled')
  );

CREATE POLICY "reservations_staff_manage" ON public.reservations
  FOR UPDATE
  USING (public.is_librarian_or_admin())
  WITH CHECK (public.is_librarian_or_admin());

CREATE POLICY "sanctions_member_select_own" ON public.sanctions
  FOR SELECT
  USING (user_id = auth.uid() OR public.is_librarian_or_admin());

CREATE POLICY "sanctions_staff_manage" ON public.sanctions
  FOR ALL
  USING (public.is_librarian_or_admin())
  WITH CHECK (public.is_librarian_or_admin());
