create table if not exists mutual_watch.app_releases (
  id uuid primary key default extensions.gen_random_uuid(),
  platform text not null check (platform in ('android', 'ios')),
  version_code integer not null check (version_code > 0),
  version_name text not null check (length(trim(version_name)) > 0),
  apk_url text not null check (apk_url ~ '^https://'),
  release_notes text not null default '',
  required boolean not null default false,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  unique (platform, version_code)
);

create index if not exists app_releases_lookup_idx
  on mutual_watch.app_releases (platform, version_code desc, published_at desc)
  where published_at is not null;

alter table mutual_watch.app_releases enable row level security;

drop policy if exists app_releases_deny_all on mutual_watch.app_releases;
create policy app_releases_deny_all
  on mutual_watch.app_releases
  for all
  using (false)
  with check (false);

revoke all on table mutual_watch.app_releases from anon, authenticated;
