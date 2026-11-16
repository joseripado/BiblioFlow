CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
    'daily-library-maintenance',
    '0 0 * * *',
    $$SELECT public.daily_library_maintenance();$$
);
