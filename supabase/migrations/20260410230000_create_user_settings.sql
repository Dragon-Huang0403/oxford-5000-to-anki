-- User settings sync (review config, audio preferences, etc.)
-- Key-value pairs per user, last-write-wins.
create table if not exists user_settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  value text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

alter table user_settings enable row level security;

create policy "Users can manage own settings"
  on user_settings for all
  using (auth.uid() = user_id);
