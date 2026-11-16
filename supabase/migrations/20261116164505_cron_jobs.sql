CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
DECLARE
    v_timezone TEXT := current_setting('cron.timezone', true);
    v_job_id BIGINT;
BEGIN
    IF v_timezone IS NULL
       OR upper(trim(v_timezone)) NOT IN ('UTC', 'GMT', 'ETC/UTC', 'ETC/GMT') THEN
        RAISE EXCEPTION
            'BiblioFlow requires pg_cron cron.timezone to be UTC (or an equivalent GMT setting); found %',
            COALESCE(v_timezone, '<unset>');
    END IF;

    FOR v_job_id IN
        SELECT jobid
        FROM cron.job
        WHERE jobname = 'biblioflow-daily-maintenance'
    LOOP
        PERFORM cron.unschedule(v_job_id);
    END LOOP;

    PERFORM cron.schedule(
        'biblioflow-daily-maintenance',
        '0 0 * * *',
        'SELECT public.daily_library_maintenance();'
    );
END;
$$;
