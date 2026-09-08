begin;
-- The platform's DDL trigger does not need to be callable by API clients.
revoke execute on function public.rls_auto_enable() from public,anon,authenticated;
create schema if not exists afterglow_private;
revoke all on schema afterglow_private from public, anon;
grant usage on schema afterglow_private to authenticated;

create table public.ag_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(trim(display_name)) between 1 and 40)
);
create table public.ag_rooms (
  id uuid primary key default gen_random_uuid(),
  invite_code text unique not null default upper(substr(replace(gen_random_uuid()::text,'-',''),1,16)),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'Our watch party' check (length(title) between 1 and 80),
  source_url text not null default '' check (length(source_url) <= 4000),
  playing boolean not null default false,
  position_seconds double precision not null default 0 check (position_seconds >= 0 and position_seconds < 1e8),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  shared_controls boolean not null default true,
  created_at timestamptz not null default now()
);
create index ag_rooms_owner on public.ag_rooms(owner_id);
create table public.ag_members (
  room_id uuid not null references public.ag_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (length(display_name) between 1 and 40),
  last_seen timestamptz not null default now(),
  call_session uuid,
  muted boolean not null default false,
  camera boolean not null default false,
  primary key (room_id,user_id)
);
create index ag_members_user on public.ag_members(user_id);
create table public.ag_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.ag_rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  body text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index ag_messages_room_time on public.ag_messages(room_id,created_at desc);
create index ag_messages_sender on public.ag_messages(sender_id);
create table public.ag_signals (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.ag_rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  sender_session uuid not null,
  recipient_session uuid not null,
  kind text not null check(kind in ('offer','answer','ice')),
  payload jsonb not null check(octet_length(payload::text) < 100000),
  created_at timestamptz not null default now()
);
create index ag_signals_recipient on public.ag_signals(recipient_id,room_id,created_at);
create index ag_signals_sender on public.ag_signals(sender_id);
create index ag_signals_room on public.ag_signals(room_id);
create table public.ag_history (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.ag_rooms(id) on delete cascade,
  source_url text not null,
  created_at timestamptz not null default now()
);
create index ag_history_room on public.ag_history(room_id,created_at desc);

alter table public.ag_profiles enable row level security;
alter table public.ag_rooms enable row level security;
alter table public.ag_members enable row level security;
alter table public.ag_messages enable row level security;
alter table public.ag_signals enable row level security;
alter table public.ag_history enable row level security;
revoke all on public.ag_profiles,public.ag_rooms,public.ag_members,public.ag_messages,public.ag_signals,public.ag_history from anon,authenticated;
grant select,insert,update on public.ag_profiles to authenticated;
grant select on public.ag_rooms,public.ag_members,public.ag_messages,public.ag_history to authenticated;
grant select,delete on public.ag_signals to authenticated;

-- Membership checks avoid recursive member-table policies. No caller-supplied identity.
create function afterglow_private.is_member(p_room uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.ag_members where room_id=p_room and user_id=(select auth.uid()));
$$;
create policy profile_read on public.ag_profiles for select to authenticated using (user_id=(select auth.uid()));
create policy profile_insert on public.ag_profiles for insert to authenticated with check(user_id=(select auth.uid()));
create policy profile_update on public.ag_profiles for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy room_read on public.ag_rooms for select to authenticated using(afterglow_private.is_member(id));
create policy member_read on public.ag_members for select to authenticated using(afterglow_private.is_member(room_id));
create policy message_read on public.ag_messages for select to authenticated using(afterglow_private.is_member(room_id));
create policy history_read on public.ag_history for select to authenticated using(afterglow_private.is_member(room_id));
create policy signal_read on public.ag_signals for select to authenticated using(recipient_id=(select auth.uid()) and afterglow_private.is_member(room_id));
create policy signal_delete on public.ag_signals for delete to authenticated using(recipient_id=(select auth.uid()));

-- A single authenticated, audited command boundary owns all room mutations.
-- Definer code is in a non-exposed schema; the public RPC is an invoker wrapper.
create function afterglow_private.command(action text, args jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid(); r public.ag_rooms; m public.ag_members;
  rid uuid := nullif(args->>'room_id','')::uuid;
  nickname text; result jsonb; target public.ag_members;
begin
  if uid is null then raise exception 'Sign in to continue'; end if;
  select display_name into nickname from public.ag_profiles where user_id=uid;
  if action='clock' then return to_jsonb(clock_timestamp()); end if;
  if action='create' then
    if nickname is null then raise exception 'Set your display name first'; end if;
    if (select count(*) from public.ag_rooms where owner_id=uid) >= 10 then raise exception 'Close an old room before creating another'; end if;
    insert into public.ag_rooms(owner_id,title) values(uid,coalesce(nullif(trim(args->>'title'),''),'Our watch party')) returning * into r;
    insert into public.ag_members(room_id,user_id,display_name) values(r.id,uid,nickname);
    return to_jsonb(r);
  end if;
  if action='join' then
    select * into r from public.ag_rooms where invite_code=upper(trim(args->>'code')) for update;
    if r.id is null then raise exception 'Room not found. Check the invitation code'; end if;
    if nickname is null then raise exception 'Set your display name first'; end if;
    if not exists(select 1 from public.ag_members where room_id=r.id and user_id=uid) and (select count(*) from public.ag_members where room_id=r.id) >= 8 then raise exception 'This room is full'; end if;
    insert into public.ag_members(room_id,user_id,display_name) values(r.id,uid,nickname)
    on conflict(room_id,user_id) do update set last_seen=now(),display_name=excluded.display_name;
    return to_jsonb(r);
  end if;
  select * into r from public.ag_rooms where id=rid for update;
  select * into m from public.ag_members where room_id=rid and user_id=uid;
  if r.id is null or m.user_id is null then raise exception 'You are no longer in this room'; end if;
  if action='heartbeat' then
    update public.ag_members set last_seen=now() where room_id=rid and user_id=uid;
    delete from public.ag_signals where room_id=rid and created_at<now()-interval '2 minutes';
    return to_jsonb(clock_timestamp());
  elsif action='playback' then
    if r.owner_id<>uid and not r.shared_controls then raise exception 'Only the host can control playback'; end if;
    if r.revision<>(args->>'revision')::bigint then return to_jsonb(r); end if;
    if args ? 'source_url' and r.owner_id<>uid then raise exception 'Only the host can choose a video'; end if;
    if args ? 'source_url' and (args->>'source_url') !~ '^https://' then raise exception 'Use a secure video URL'; end if;
    update public.ag_rooms set source_url=coalesce(args->>'source_url',source_url),
      playing=(args->>'playing')::boolean, position_seconds=(args->>'position')::double precision,
      updated_at=clock_timestamp(),revision=revision+1 where id=rid returning * into r;
    if args ? 'source_url' then
      insert into public.ag_history(room_id,source_url) values(rid,r.source_url);
      delete from public.ag_history where room_id=rid and id not in (select id from public.ag_history where room_id=rid order by created_at desc limit 20);
    end if;
    return to_jsonb(r);
  elsif action='settings' then
    if r.owner_id<>uid then raise exception 'Only the host can change room settings'; end if;
    update public.ag_rooms set shared_controls=(args->>'shared_controls')::boolean,revision=revision+1 where id=rid returning * into r;
    return to_jsonb(r);
  elsif action='message' then
    if exists(select 1 from public.ag_messages where sender_id=uid and created_at>now()-interval '500 milliseconds') then raise exception 'Wait a moment before sending another message'; end if;
    insert into public.ag_messages(room_id,sender_id,display_name,body) values(rid,uid,m.display_name,trim(args->>'body'));
    delete from public.ag_messages where room_id=rid and id not in (select id from public.ag_messages where room_id=rid order by created_at desc limit 500);
    return '{}'::jsonb;
  elsif action='call_join' then
    if (select count(*) from public.ag_members where room_id=rid and user_id<>uid and call_session is not null and last_seen>now()-interval '50 seconds')>=4 then raise exception 'The call is full (four people)'; end if;
    update public.ag_members set call_session=gen_random_uuid(),camera=(args->>'camera')::boolean,muted=false,last_seen=now() where room_id=rid and user_id=uid returning * into m;
    return to_jsonb(m);
  elsif action='call_update' then
    update public.ag_members set camera=(args->>'camera')::boolean,muted=(args->>'muted')::boolean where room_id=rid and user_id=uid and call_session=(args->>'session')::uuid;
    return '{}'::jsonb;
  elsif action='call_leave' then
    update public.ag_members set call_session=null,camera=false,muted=false where room_id=rid and user_id=uid and call_session=(args->>'session')::uuid;
    delete from public.ag_signals where room_id=rid and (sender_id=uid or recipient_id=uid);
    return '{}'::jsonb;
  elsif action='signal' then
    select * into target from public.ag_members where room_id=rid and user_id=(args->>'recipient_id')::uuid;
    if m.call_session is null or target.call_session is null or m.call_session<>(args->>'sender_session')::uuid or target.call_session<>(args->>'recipient_session')::uuid or target.last_seen<now()-interval '50 seconds' then raise exception 'Call session has ended'; end if;
    if (select count(*) from public.ag_signals where sender_id=uid and created_at>now()-interval '10 seconds')>=150 then raise exception 'Too many call messages'; end if;
    insert into public.ag_signals(room_id,sender_id,recipient_id,sender_session,recipient_session,kind,payload)
    values(rid,uid,target.user_id,m.call_session,target.call_session,args->>'kind',args->'payload');
    return '{}'::jsonb;
  elsif action='remove' then
    if r.owner_id<>uid or (args->>'user_id')::uuid=uid then raise exception 'Only the host can remove another member'; end if;
    delete from public.ag_members where room_id=rid and user_id=(args->>'user_id')::uuid;
    delete from public.ag_signals where room_id=rid and (sender_id=(args->>'user_id')::uuid or recipient_id=(args->>'user_id')::uuid);
    return '{}'::jsonb;
  elsif action='leave' then
    if r.owner_id=uid then delete from public.ag_rooms where id=rid;
    else delete from public.ag_members where room_id=rid and user_id=uid; end if;
    return '{}'::jsonb;
  end if;
  raise exception 'Unknown room action';
end;
$$;
revoke all on all functions in schema afterglow_private from public,anon;
grant execute on all functions in schema afterglow_private to authenticated;
create function public.ag_command(action text,args jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select afterglow_private.command(action,args); $$;
revoke all on function public.ag_command(text,jsonb) from public,anon;
grant execute on function public.ag_command(text,jsonb) to authenticated;

alter publication supabase_realtime add table public.ag_rooms,public.ag_members,public.ag_messages,public.ag_signals,public.ag_history;
commit;
