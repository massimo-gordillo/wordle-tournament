select cron.unschedule(jobid)
from cron.job
where jobname = 'edge-run-daily-cron-03utc';
select cron.schedule(
  'edge-run-daily-cron-03utc',
  '0 3 * * *',
  $sql$
  select public.run_daily_cron_if_eastern_cutoff();
  $sql$
);