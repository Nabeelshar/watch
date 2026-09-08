-- All users, rooms, and messages in this integration test are rolled back.
begin;
create temporary table ag_test_state(host uuid,guest uuid,outsider uuid,room uuid,code text);
insert into ag_test_state values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),null,null);
insert into auth.users(id,aud,role) select host,'authenticated','authenticated' from ag_test_state union all select guest,'authenticated','authenticated' from ag_test_state union all select outsider,'authenticated','authenticated' from ag_test_state;
grant select,update on ag_test_state to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select host::text from ag_test_state),true);
insert into public.ag_profiles select host,'Test host' from ag_test_state;
do $$ declare r jsonb; begin
  r:=public.ag_command('create','{"title":"Integration test"}');
  update ag_test_state set room=(r->>'id')::uuid,code=r->>'invite_code';
  perform public.ag_command('playback',jsonb_build_object('room_id',r->>'id','revision',0,'playing',true,'position',25,'source_url','https://example.com/video.mp4'));
  perform public.ag_command('message',jsonb_build_object('room_id',r->>'id','body','Hello, party'));
  perform public.ag_command('call_join',jsonb_build_object('room_id',r->>'id','camera',true));
  begin update public.ag_rooms set owner_id=gen_random_uuid(); raise exception 'FAIL direct room write'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub',(select guest::text from ag_test_state),true);
insert into public.ag_profiles select guest,'Test guest' from ag_test_state;
do $$ declare r jsonb; current_revision bigint; begin
  if (select count(*) from public.ag_rooms)<>0 then raise exception 'FAIL uninvited room visibility'; end if;
  r:=public.ag_command('join',jsonb_build_object('code',(select code from ag_test_state)));
  if (select count(*) from public.ag_messages)<>1 then raise exception 'FAIL joined message visibility'; end if;
  r:=public.ag_command('playback',jsonb_build_object('room_id',r->>'id','revision',0,'playing',false,'position',0));
  if (r->>'revision')::bigint<>1 or not (r->>'playing')::boolean then raise exception 'FAIL stale revision accepted'; end if;
  r:=public.ag_command('playback',jsonb_build_object('room_id',r->>'id','revision',1,'playing',false,'position',28));
  if (r->>'revision')::bigint<>2 or (r->>'playing')::boolean then raise exception 'FAIL shared pause'; end if;
  begin
    perform public.ag_command('playback',jsonb_build_object('room_id',r->>'id','revision',2,'playing',true,'position',0,'source_url','https://example.com/other.mp4'));
    raise exception 'FAIL guest changed source';
  exception when raise_exception then if sqlerrm='FAIL guest changed source' then raise; end if; end;
  perform public.ag_command('call_join',jsonb_build_object('room_id',r->>'id','camera',false));
  perform public.ag_command('signal',jsonb_build_object('room_id',r->>'id','recipient_id',(select host from ag_test_state),'sender_session',(select call_session from public.ag_members where user_id=(select guest from ag_test_state)),'recipient_session',(select call_session from public.ag_members where user_id=(select host from ag_test_state)),'kind','offer','payload','{"sdp":"test","type":"offer"}'::jsonb));
  if (select count(*) from public.ag_signals)<>0 then raise exception 'FAIL sender read another recipient signals'; end if;
end $$;
select set_config('request.jwt.claim.sub',(select host::text from ag_test_state),true);
do $$ begin
  if (select count(*) from public.ag_signals)<>1 then raise exception 'FAIL recipient cannot read signal'; end if;
  perform public.ag_command('settings',jsonb_build_object('room_id',(select room from ag_test_state),'shared_controls',false));
end $$;
select set_config('request.jwt.claim.sub',(select guest::text from ag_test_state),true);
do $$ begin
  begin
    perform public.ag_command('playback',jsonb_build_object('room_id',(select room from ag_test_state),'revision',3,'playing',true,'position',30));
    raise exception 'FAIL host-only control bypass';
  exception when raise_exception then if sqlerrm='FAIL host-only control bypass' then raise; end if; end;
  begin
    insert into public.ag_profiles(user_id,display_name) values((select outsider from ag_test_state),'Spoof');
    raise exception 'FAIL profile spoof';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub',(select outsider::text from ag_test_state),true);
do $$ begin
  if (select count(*) from public.ag_rooms)<>0 or (select count(*) from public.ag_members)<>0 or (select count(*) from public.ag_messages)<>0 or (select count(*) from public.ag_signals)<>0 then raise exception 'FAIL outsider read private data'; end if;
  begin
    perform public.ag_command('heartbeat',jsonb_build_object('room_id',(select room from ag_test_state)));
    raise exception 'FAIL outsider mutation';
  exception when raise_exception then if sqlerrm='FAIL outsider mutation' then raise; end if; end;
end $$;
reset role;
rollback;
select 'PASS: room isolation, profiles, host authorization, revision ordering, shared pause, private call signals; all test data rolled back' as result;
