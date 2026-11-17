BiblioFlow — Library Management System

BiblioFlow is an information system designed to manage library operations. It enables members to browse the catalogue, reserve books, and manage loans, while providing library staff with tools to handle desk checkouts, returns, and collection management.

🏗 System Architecture

The project uses a Serverless Multi-Client Unified-Backend Architecture. All three client platforms connect directly to a single Supabase (PostgreSQL) backend via native SDKs. Security and automated rules are handled at the database level using Row Level Security (RLS) and PostgreSQL functions.

Unified Backend: Supabase (PostgreSQL Database, Supabase Auth, RLS Policies, and pg_cron automation).

Mobile App: Native Kotlin app built with Jetpack Compose (MVVM architecture) for library Members.

Desktop App: Native .NET 8 (C# / WPF) application with DirectX rendering for Librarians at the front desk.

Web App: Lightweight React.js (Vite) web application for general catalogue access and Administrator reporting.

👥 Roles & Features

Member (Mobile / Web): Search the catalogue, view active loans, renew loans, place reservations on unavailable books, and view sanction history.

Librarian (Desktop): Record loans and returns at the front desk, manage physical copies, and monitor overdue items.

Administrator (Web / Desktop): Manage user roles, configure system parameters, cancel sanctions, and view system reports.
