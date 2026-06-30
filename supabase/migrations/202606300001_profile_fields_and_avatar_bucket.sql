alter table mutual_watch.users
  add column if not exists avatar_url text,
  add column if not exists mood_status text check (mood_status is null or char_length(mood_status) <= 20),
  add column if not exists gender text not null default 'unspecified'
    check (gender in ('male', 'female', 'other', 'unspecified'));

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'profile-avatars',
  'profile-avatars',
  true,
  3145728,
  array[
    'image/jpeg',
    'image/png',
    'image/webp'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
