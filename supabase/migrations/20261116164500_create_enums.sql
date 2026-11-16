-- Versioned migrations are applied once by Supabase CLI; enum creation is intentionally not rerunnable.
CREATE TYPE public.profile_role AS ENUM ('member', 'librarian', 'admin');
CREATE TYPE public.profile_status AS ENUM ('active', 'sanctioned', 'deregistered');
CREATE TYPE public.copy_status AS ENUM ('available', 'on_loan', 'reserved', 'under_repair', 'withdrawn');
CREATE TYPE public.loan_status AS ENUM ('active', 'overdue', 'returned');
CREATE TYPE public.reservation_status AS ENUM ('pending', 'ready_for_pickup', 'completed', 'expired', 'cancelled');
CREATE TYPE public.sanction_status AS ENUM ('active', 'expired', 'cancelled');
