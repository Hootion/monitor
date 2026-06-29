create schema if not exists mutual_watch;

create extension if not exists pgcrypto with schema extensions;

create table if not exists mutual_watch.users (
  id uuid primary key default extensions.gen_random_uuid(),
  display_name text not null check (char_length(display_name) between 1 and 40),
  phone text not null unique check (char_length(phone) between 1 and 32),
  password_hash text not null,
  password_salt text not null,
  sharing_paused boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists mutual_watch.refresh_tokens (
  token_hash text primary key,
  user_id uuid not null references mutual_watch.users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists mutual_watch.pairing_invites (
  code text primary key,
  created_by_user_id uuid not null references mutual_watch.users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists mutual_watch.pairings (
  id uuid primary key default extensions.gen_random_uuid(),
  user_a_id uuid not null references mutual_watch.users(id) on delete cascade,
  user_b_id uuid not null references mutual_watch.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (user_a_id <> user_b_id)
);

create table if not exists mutual_watch.consent_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references mutual_watch.users(id) on delete cascade,
  action text not null,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create table if not exists mutual_watch.device_snapshots (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references mutual_watch.users(id) on delete cascade,
  platform text not null,
  captured_at timestamptz not null,
  wifi_bytes_today bigint,
  mobile_bytes_today bigint,
  network_speed_kbps integer,
  network_type text,
  network_name text,
  bluetooth_state text,
  volume_percent integer,
  battery_percent integer,
  battery_charging boolean,
  model text,
  os_version text,
  storage_used_bytes bigint,
  storage_total_bytes bigint,
  unsupported jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists mutual_watch.device_locations (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references mutual_watch.users(id) on delete cascade,
  platform text not null,
  captured_at timestamptz not null,
  status text not null,
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  created_at timestamptz not null default now()
);

create table if not exists mutual_watch.app_usage_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references mutual_watch.users(id) on delete cascade,
  package_name text not null,
  app_name text,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_ms bigint not null,
  open_count integer,
  platform text not null,
  created_at timestamptz not null default now()
);

create table if not exists mutual_watch.daily_usage_reports (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references mutual_watch.users(id) on delete cascade,
  report_date date not null,
  platform text not null,
  screen_time_ms bigint not null,
  pickup_count integer not null,
  first_use_at timestamptz,
  longest_continuous_ms bigint not null,
  unsupported jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, report_date)
);

create table if not exists mutual_watch.operation_events (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references mutual_watch.users(id) on delete cascade,
  client_event_id text,
  event_type text not null,
  occurred_at timestamptz not null,
  platform text not null,
  details jsonb,
  created_at timestamptz not null default now()
);

create index if not exists pairing_invites_creator_idx on mutual_watch.pairing_invites(created_by_user_id, expires_at);
create index if not exists pairings_user_a_idx on mutual_watch.pairings(user_a_id);
create index if not exists pairings_user_b_idx on mutual_watch.pairings(user_b_id);
create index if not exists consent_logs_user_created_idx on mutual_watch.consent_logs(user_id, created_at desc);
create index if not exists device_snapshots_user_captured_idx on mutual_watch.device_snapshots(user_id, captured_at desc);
create index if not exists device_locations_user_captured_idx on mutual_watch.device_locations(user_id, captured_at desc);
create index if not exists app_usage_user_started_idx on mutual_watch.app_usage_sessions(user_id, started_at desc);
create index if not exists daily_reports_user_date_idx on mutual_watch.daily_usage_reports(user_id, report_date desc);
create index if not exists operation_events_user_occurred_idx on mutual_watch.operation_events(user_id, occurred_at desc);
create unique index if not exists operation_events_client_unique_idx
  on mutual_watch.operation_events(user_id, client_event_id)
  where client_event_id is not null;
create unique index if not exists operation_events_fallback_unique_idx
  on mutual_watch.operation_events(user_id, event_type, occurred_at)
  where client_event_id is null;

alter table mutual_watch.users enable row level security;
alter table mutual_watch.refresh_tokens enable row level security;
alter table mutual_watch.pairing_invites enable row level security;
alter table mutual_watch.pairings enable row level security;
alter table mutual_watch.consent_logs enable row level security;
alter table mutual_watch.device_snapshots enable row level security;
alter table mutual_watch.device_locations enable row level security;
alter table mutual_watch.app_usage_sessions enable row level security;
alter table mutual_watch.daily_usage_reports enable row level security;
alter table mutual_watch.operation_events enable row level security;

revoke all on schema mutual_watch from anon, authenticated;
revoke all on all tables in schema mutual_watch from anon, authenticated;
revoke all on all sequences in schema mutual_watch from anon, authenticated;
