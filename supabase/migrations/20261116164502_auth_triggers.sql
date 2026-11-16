CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, email, role, status)
    VALUES (
        NEW.id,
        COALESCE(NULLIF(NEW.raw_user_meta_data->>'full_name', ''), NULLIF(NEW.email, ''), 'Member'),
        NEW.email,
        'member',
        'active'
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER profiles_set_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER books_set_updated_at
BEFORE UPDATE ON public.books
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER copies_set_updated_at
BEFORE UPDATE ON public.copies
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER loans_set_updated_at
BEFORE UPDATE ON public.loans
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER reservations_set_updated_at
BEFORE UPDATE ON public.reservations
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER sanctions_set_updated_at
BEFORE UPDATE ON public.sanctions
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
