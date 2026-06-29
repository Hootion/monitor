insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'app-releases',
  'app-releases',
  true,
  209715200,
  array[
    'application/vnd.android.package-archive',
    'application/octet-stream'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists mutual_watch.app_release_admin_tokens (
  id uuid primary key default extensions.gen_random_uuid(),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  label text not null default 'local-publisher',
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);

alter table mutual_watch.app_release_admin_tokens enable row level security;

drop policy if exists app_release_admin_tokens_deny_all on mutual_watch.app_release_admin_tokens;
create policy app_release_admin_tokens_deny_all
  on mutual_watch.app_release_admin_tokens
  for all
  using (false)
  with check (false);

revoke all on table mutual_watch.app_release_admin_tokens from anon, authenticated;
