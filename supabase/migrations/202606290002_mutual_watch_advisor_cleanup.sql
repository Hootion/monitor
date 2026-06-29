create index if not exists refresh_tokens_user_id_idx on mutual_watch.refresh_tokens(user_id);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'users',
    'refresh_tokens',
    'pairing_invites',
    'pairings',
    'consent_logs',
    'device_snapshots',
    'device_locations',
    'app_usage_sessions',
    'daily_usage_reports',
    'operation_events'
  ]
  loop
    if not exists (
      select 1
      from pg_policies
      where schemaname = 'mutual_watch'
        and tablename = table_name
        and policyname = 'deny_all'
    ) then
      execute format(
        'create policy deny_all on mutual_watch.%I for all using (false) with check (false)',
        table_name
      );
    end if;
  end loop;
end $$;
