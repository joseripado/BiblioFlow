CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    role public.profile_role NOT NULL DEFAULT 'member',
    status public.profile_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.books (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    authors TEXT NOT NULL,
    isbn TEXT NOT NULL UNIQUE,
    publisher TEXT,
    publication_year INTEGER CHECK (publication_year BETWEEN 0 AND 9999),
    category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    language TEXT NOT NULL DEFAULT 'es',
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.copies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id UUID NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
    inventory_code TEXT NOT NULL UNIQUE,
    location TEXT NOT NULL DEFAULT 'general',
    status public.copy_status NOT NULL DEFAULT 'available',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (location <> '')
);

CREATE TABLE public.loans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    copy_id UUID NOT NULL REFERENCES public.copies(id) ON DELETE RESTRICT,
    loan_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    due_date TIMESTAMPTZ NOT NULL,
    return_date TIMESTAMPTZ,
    renewals_count INTEGER NOT NULL DEFAULT 0 CHECK (renewals_count >= 0),
    status public.loan_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (due_date >= loan_date),
    CHECK (return_date IS NULL OR return_date >= loan_date)
);

CREATE TABLE public.reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    book_id UUID NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
    copy_id UUID REFERENCES public.copies(id) ON DELETE SET NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    pickup_deadline TIMESTAMPTZ,
    status public.reservation_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (pickup_deadline IS NULL OR pickup_deadline >= requested_at)
);

CREATE TABLE public.sanctions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    loan_id UUID NOT NULL REFERENCES public.loans(id) ON DELETE CASCADE,
    start_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_date TIMESTAMPTZ NOT NULL,
    reason TEXT NOT NULL,
    status public.sanction_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (end_date >= start_date)
);

CREATE INDEX idx_profiles_role_status ON public.profiles (role, status);
CREATE INDEX idx_profiles_email ON public.profiles (email);
CREATE INDEX idx_books_category_id ON public.books (category_id);
CREATE INDEX idx_books_title ON public.books (title);
CREATE INDEX idx_books_authors ON public.books (authors);
CREATE INDEX idx_books_isbn ON public.books (isbn);
CREATE INDEX idx_copies_book_id ON public.copies (book_id);
CREATE INDEX idx_copies_status ON public.copies (status);
CREATE INDEX idx_loans_user_id ON public.loans (user_id);
CREATE INDEX idx_loans_copy_id ON public.loans (copy_id);
CREATE INDEX idx_loans_status_due_date ON public.loans (status, due_date);
CREATE INDEX idx_reservations_user_id ON public.reservations (user_id);
CREATE INDEX idx_reservations_book_id_status ON public.reservations (book_id, status, requested_at);
CREATE INDEX idx_reservations_copy_id ON public.reservations (copy_id);
CREATE INDEX idx_sanctions_user_id_status ON public.sanctions (user_id, status);
CREATE INDEX idx_sanctions_loan_id ON public.sanctions (loan_id);

CREATE UNIQUE INDEX uq_active_loan_per_copy ON public.loans (copy_id) WHERE status = 'active';
CREATE UNIQUE INDEX uq_active_reservation_per_user_book ON public.reservations (user_id, book_id) WHERE status IN ('pending', 'ready_for_pickup');
CREATE UNIQUE INDEX uq_active_sanction_per_loan ON public.sanctions (loan_id) WHERE status = 'active';

ALTER TABLE public.loans
  ADD CONSTRAINT loans_copy_not_reserved_while_active CHECK (
    status <> 'active' OR NOT EXISTS (
      SELECT 1
      FROM public.reservations r
      WHERE r.copy_id = loans.copy_id
        AND r.status IN ('pending', 'ready_for_pickup')
    )
  );
