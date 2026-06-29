alter table mutual_watch.app_usage_sessions
  add column if not exists client_session_id text;

create unique index if not exists app_usage_sessions_user_client_session_uidx
  on mutual_watch.app_usage_sessions(user_id, client_session_id)
  where client_session_id is not null;
