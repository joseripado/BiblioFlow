
-- ============================================================
-- BiblioFlow
-- Migration: Public catalog and copy information protection
-- ============================================================

-- 1. Allow anonymous users to access the public schema.
GRANT USAGE ON SCHEMA public TO anon;

-- 2. Allow anonymous users to read books and categories.
GRANT SELECT ON TABLE
    public.books,
    public.categories
TO anon;

-- 3. Replace authenticated-only catalog policies.

DROP POLICY IF EXISTS categories_read_authenticated
    ON public.categories;

CREATE POLICY categories_read_public
    ON public.categories
    FOR SELECT
    TO anon, authenticated
    USING (true);

DROP POLICY IF EXISTS books_read_authenticated
    ON public.books;

CREATE POLICY books_read_public
    ON public.books
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- 4. Restrict copies to librarians and administrators.

DROP POLICY IF EXISTS copies_read_authenticated
    ON public.copies;

CREATE POLICY copies_read_staff
    ON public.copies
    FOR SELECT
    TO authenticated
    USING (public.is_librarian_or_admin());

-- 5. Create a safe public availability function.
-- It exposes only the number of available copies.

CREATE OR REPLACE FUNCTION public.get_book_availability(
    p_book_id UUID
)
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
    SELECT COUNT(*)::BIGINT
    FROM public.copies AS c
    WHERE c.book_id = p_book_id
      AND c.status = 'available';
$$;

-- 6. Restrict execution permissions explicitly.

REVOKE ALL ON FUNCTION public.get_book_availability(UUID)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.get_book_availability(UUID)
TO anon, authenticated;

-- 7. Document the intended behavior.

COMMENT ON FUNCTION public.get_book_availability(UUID)
IS 'Returns only the number of available copies for a book. Does not expose inventory codes or physical locations.';

COMMENT ON FUNCTION public.get_available_copies(UUID)
IS 'Returns available copy details for authorized library staff. Member access is restricted by copies RLS.';
