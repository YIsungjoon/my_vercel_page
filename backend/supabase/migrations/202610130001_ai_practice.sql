-- Independent service schema. No farm tables or farm_memberships are reused.
begin;
create schema if not exists ai_practice;
grant usage on schema ai_practice to anon, authenticated, service_role;

create table ai_practice.staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'editor' check (role in ('editor','admin')),
  created_at timestamptz not null default now()
);
create function ai_practice.is_staff() returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from ai_practice.staff where user_id = auth.uid());
$$;

-- Content JSON is the versioned delivery contract; relational keys enforce taxonomy.
create table ai_practice.courses (
  id text primary key check (length(id) between 1 and 80),
  content jsonb not null check (jsonb_typeof(content) = 'object' and content ?& array['id','title','category','description','exams'] and content->>'id' = id and length(content->>'title') > 0 and jsonb_typeof(content->'exams') = 'array'),
  published boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table ai_practice.subjects (
  id text primary key, course_id text not null references ai_practice.courses(id) on delete cascade,
  content jsonb not null check (jsonb_typeof(content)='object' and content ?& array['id','courseId','label'] and content->>'id' = id and content->>'courseId' = course_id and length(content->>'label') > 0),
  unique(id,course_id)
);
create table ai_practice.topics (
  id text primary key, subject_id text not null references ai_practice.subjects(id) on delete cascade,
  content jsonb not null check (jsonb_typeof(content)='object' and content ?& array['id','subjectId','label','icon'] and content->>'id' = id and content->>'subjectId' = subject_id and length(content->>'label') > 0),
  unique(id,subject_id)
);
create table ai_practice.question_types (
  id text primary key, label text not null, grading_method text not null,
  config jsonb not null default '{}'::jsonb
);
insert into ai_practice.question_types(id,label,grading_method) values
 ('choice','단일 선택','exact'),('short','단답형','exact'),
 ('multiple','복수 선택','set'),('essay','서술형','rubric');
create table ai_practice.cases (
  id text primary key, course_id text not null references ai_practice.courses(id) on delete cascade,
  published boolean not null default false,
  content jsonb not null check (jsonb_typeof(content)='object' and content ?& array['id','courseId','title','summary','columns','rows','notes'] and content->>'id' = id and content->>'courseId' = course_id and jsonb_typeof(content->'rows') = 'array'),
  unique(id,course_id)
);
create table ai_practice.questions (
  id text primary key, course_id text not null,
  subject_id text not null, topic_id text not null, case_id text,
  question_type text not null references ai_practice.question_types(id),
  published boolean not null default false, revision integer not null default 1 check (revision>0),
  content jsonb not null check (
    jsonb_typeof(content)='object' and content ?& array['id','courseId','subjectId','topic','title','level','section','kind','prompt','answers','explanation','takeaway'] and content->>'id'=id and content->>'courseId'=course_id
    and content->>'subjectId'=subject_id and content->>'topic'=topic_id and content->>'kind'=question_type
    and length(content->>'prompt')>0 and jsonb_typeof(content->'answers')='array'
    and jsonb_array_length(content->'answers')>0 and length(content->>'explanation')>0
    and (case_id is null and not(content ? 'caseId') or content->>'caseId'=case_id)
    and (question_type<>'choice' or (content ? 'choices' and jsonb_typeof(content->'choices')='array' and jsonb_array_length(content->'choices') between 2 and 6))
  ),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  foreign key(subject_id,course_id) references ai_practice.subjects(id,course_id),
  foreign key(topic_id,subject_id) references ai_practice.topics(id,subject_id),
  foreign key(case_id,course_id) references ai_practice.cases(id,course_id)
);
create index questions_catalog_idx on ai_practice.questions(course_id,subject_id,topic_id) where published;
create table ai_practice.question_revisions (
  question_id text not null references ai_practice.questions(id) on delete cascade,
  revision integer not null, content jsonb not null, changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(), primary key(question_id,revision)
);
-- AFTER trigger ensures the referenced question exists. Revisions are assigned in BEFORE.
create function ai_practice.bump_revision() returns trigger language plpgsql set search_path='' as $$
begin new.revision := old.revision+1; new.updated_at:=now(); return new; end;
$$;
create trigger question_revision_number before update on ai_practice.questions for each row execute function ai_practice.bump_revision();
create function ai_practice.store_revision() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into ai_practice.question_revisions(question_id,revision,content,changed_by) values(new.id,new.revision,new.content,auth.uid());
 return new;
end;
$$;
create trigger question_revision_snapshot after insert or update on ai_practice.questions for each row execute function ai_practice.store_revision();

create table ai_practice.learner_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 0 check (revision>=0),
  custom_bank jsonb not null default '{"version":1,"courses":[],"subjects":[],"topics":[],"cases":[],"questions":[]}'::jsonb,
  updated_at timestamptz not null default now()
);
create table ai_practice.runs (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check(length(title) between 1 and 200), mode text not null check(mode in ('practice','exam')),
  questions jsonb not null check(jsonb_typeof(questions)='array' and jsonb_array_length(questions) between 1 and 100),
  cases jsonb not null default '[]'::jsonb check(jsonb_typeof(cases)='array'),
  current_index integer not null default 0 check(current_index>=0),
  checked text[] not null default '{}', marked text[] not null default '{}',
  started_at timestamptz not null, deadline timestamptz,
  finished_at timestamptz, finish_reason text check(finish_reason in ('manual','timeout')),
  correct_count integer not null default 0 check(correct_count>=0),
  check ((finished_at is null)=(finish_reason is null)),
  check (current_index<jsonb_array_length(questions)),
  check (mode<>'exam' or deadline is not null),
  check (deadline is null or deadline>started_at),
  check (finished_at is null or finished_at>=started_at)
);
create index runs_user_finished_idx on ai_practice.runs(user_id,finished_at desc);
create unique index runs_one_active_per_user on ai_practice.runs(user_id) where finished_at is null;
create table ai_practice.answers (
  run_id uuid not null references ai_practice.runs(id) on delete cascade,
  question_id text not null check(length(question_id) between 1 and 80),
  value text not null check(length(value)<=20000), is_correct boolean not null default false,
  primary key(run_id,question_id)
);
create table ai_practice.bookmarks (
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id text not null check(length(question_id) between 1 and 80),
  created_at timestamptz not null default now(), primary key(user_id,question_id)
);
create table ai_practice.notes (
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id text not null check(length(question_id) between 1 and 80),
  body text not null check(length(body)<=20000), updated_at timestamptz not null default now(),
  primary key(user_id,question_id)
);

alter table ai_practice.staff enable row level security;
alter table ai_practice.courses enable row level security;
alter table ai_practice.subjects enable row level security;
alter table ai_practice.topics enable row level security;
alter table ai_practice.question_types enable row level security;
alter table ai_practice.cases enable row level security;
alter table ai_practice.questions enable row level security;
alter table ai_practice.question_revisions enable row level security;
alter table ai_practice.learner_profiles enable row level security;
alter table ai_practice.runs enable row level security;
alter table ai_practice.answers enable row level security;
alter table ai_practice.bookmarks enable row level security;
alter table ai_practice.notes enable row level security;

create policy staff_self on ai_practice.staff for select to authenticated using(user_id=auth.uid());
create policy course_read on ai_practice.courses for select using(published or ai_practice.is_staff());
create policy subject_read on ai_practice.subjects for select using(exists(select 1 from ai_practice.courses c where c.id=course_id and c.published) or ai_practice.is_staff());
create policy topic_read on ai_practice.topics for select using(exists(select 1 from ai_practice.subjects s join ai_practice.courses c on c.id=s.course_id where s.id=subject_id and c.published) or ai_practice.is_staff());
create policy type_read on ai_practice.question_types for select using(true);
create policy case_read on ai_practice.cases for select using((published and exists(select 1 from ai_practice.courses c where c.id=course_id and c.published)) or ai_practice.is_staff());
create policy question_read on ai_practice.questions for select using((published and exists(select 1 from ai_practice.courses c where c.id=course_id and c.published) and (case_id is null or exists(select 1 from ai_practice.cases c where c.id=case_id and c.published))) or ai_practice.is_staff());
create policy revisions_staff on ai_practice.question_revisions for select to authenticated using(ai_practice.is_staff());
create policy profile_self on ai_practice.learner_profiles for select to authenticated using(user_id=auth.uid());
create policy run_self on ai_practice.runs for select to authenticated using(user_id=auth.uid());
create policy answer_self on ai_practice.answers for select to authenticated using(exists(select 1 from ai_practice.runs r where r.id=run_id and r.user_id=auth.uid()));
create policy bookmark_self on ai_practice.bookmarks for select to authenticated using(user_id=auth.uid());
create policy note_self on ai_practice.notes for select to authenticated using(user_id=auth.uid());

-- Catalog edits require explicitly provisioned staff membership. A signup cannot become staff.
do $$ declare t text; begin
  foreach t in array array['courses','subjects','topics','cases','questions'] loop
    execute format('create policy catalog_staff_write on ai_practice.%I for all to authenticated using(ai_practice.is_staff()) with check(ai_practice.is_staff())',t);
    execute format('grant select on ai_practice.%I to anon,authenticated',t);
    execute format('grant insert,update,delete on ai_practice.%I to authenticated',t);
  end loop;
end $$;
grant select on ai_practice.question_types to anon,authenticated;
grant select on ai_practice.staff,ai_practice.question_revisions,ai_practice.learner_profiles,ai_practice.runs,ai_practice.answers,ai_practice.bookmarks,ai_practice.notes to authenticated;
grant all on all tables in schema ai_practice to service_role;

create function ai_practice.answer_matches(expected jsonb, actual text) returns boolean language sql immutable set search_path='' as $$
  select coalesce(length(btrim(actual))>0 and exists(
    select 1 from jsonb_array_elements_text(expected) e
    where upper(regexp_replace(normalize(e,NFKC),'\s','','g'))=upper(regexp_replace(normalize(actual,NFKC),'\s','','g'))
  ),false);
$$;

-- Explicit snapshot synchronization for a personal study app (not a proctored exam).
-- Imported question answers belong to the learner; scores are not authoritative rankings.
-- Revision CAS prevents silent overwrites from another device. All writes are atomic.
create function ai_practice.save_learning_state(p_state jsonb,p_revision bigint) returns bigint
language plpgsql security definer set search_path='' as $$
declare
  uid uuid:=auth.uid(); rev bigint; r jsonb; q jsonb; n record; a record;
  rid uuid; ids uuid[]:='{}'; active_count integer:=0; correct integer; val text;
begin
  if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_revision is null or p_revision<0 or p_state is null or octet_length(p_state::text)>4000000 or p_state->>'version' is distinct from '1'
    or jsonb_typeof(p_state->'attempts') is distinct from 'array' or jsonb_array_length(p_state->'attempts')>50
    or jsonb_typeof(p_state->'bookmarks') is distinct from 'array' or jsonb_array_length(p_state->'bookmarks')>1000
    or jsonb_typeof(p_state->'notes') is distinct from 'object'
    or jsonb_typeof(p_state->'customBank') is distinct from 'object'
    or p_state->'customBank'->>'version' is distinct from '1'
    or jsonb_typeof(p_state->'customBank'->'courses') is distinct from 'array'
    or jsonb_typeof(p_state->'customBank'->'subjects') is distinct from 'array'
    or jsonb_typeof(p_state->'customBank'->'topics') is distinct from 'array'
    or jsonb_typeof(p_state->'customBank'->'cases') is distinct from 'array'
    or jsonb_typeof(p_state->'customBank'->'questions') is distinct from 'array'
    or (jsonb_typeof(p_state->'active') is distinct from 'object' and p_state->'active' is distinct from 'null'::jsonb)
    then raise exception 'Invalid learning state'; end if;
  if exists(select 1 from jsonb_array_elements(p_state->'attempts') v where not(v ? 'finishedAt') or not(v ? 'reason'))
    or (jsonb_typeof(p_state->'active')='object' and (p_state->'active') ? 'finishedAt') then raise exception 'Invalid completion state'; end if;
  insert into ai_practice.learner_profiles(user_id) values(uid) on conflict do nothing;
  select revision into rev from ai_practice.learner_profiles where user_id=uid for update;
  if rev<>p_revision then raise exception 'Cloud data changed. Load the latest record before saving.' using errcode='40001'; end if;

  -- UUID ownership is checked before any deletion. A forged run ID cannot target another user.
  for r in select value from jsonb_array_elements((p_state->'attempts') ||
    case when jsonb_typeof(p_state->'active')='object' then jsonb_build_array(p_state->'active') else '[]'::jsonb end) loop
    rid:=(r->>'id')::uuid;
    if rid=any(ids) or exists(select 1 from ai_practice.runs where id=rid and user_id<>uid) then raise exception 'Invalid run ownership' using errcode='42501'; end if;
    ids:=array_append(ids,rid);
  end loop;
  delete from ai_practice.runs where user_id=uid;
  for r in select value from jsonb_array_elements((p_state->'attempts') ||
    case when jsonb_typeof(p_state->'active')='object' then jsonb_build_array(p_state->'active') else '[]'::jsonb end) loop
    rid:=(r->>'id')::uuid;
    if jsonb_typeof(r->'questions') is distinct from 'array' or jsonb_typeof(r->'cases') is distinct from 'array'
      or jsonb_typeof(r->'answers') is distinct from 'object' or jsonb_typeof(r->'checked') is distinct from 'array'
      or jsonb_typeof(r->'marked') is distinct from 'array' then raise exception 'Invalid run'; end if;
    if not(r ? 'finishedAt') then active_count:=active_count+1; end if;
    if active_count>1 then raise exception 'Only one active run is allowed'; end if;
    insert into ai_practice.runs(id,user_id,title,mode,questions,cases,current_index,checked,marked,started_at,deadline,finished_at,finish_reason)
    values(rid,uid,r->>'title',r->>'mode',r->'questions',r->'cases',(r->>'current')::integer,
      array(select jsonb_array_elements_text(r->'checked')),array(select jsonb_array_elements_text(r->'marked')),
      to_timestamp((r->>'startedAt')::double precision/1000),to_timestamp((r->>'deadline')::double precision/1000),
      to_timestamp((r->>'finishedAt')::double precision/1000),r->>'reason');
    correct:=0;
    if (select count(distinct v->>'id') from jsonb_array_elements(r->'questions') v)<>jsonb_array_length(r->'questions') then raise exception 'Duplicate question ID'; end if;
    for q in select value from jsonb_array_elements(r->'questions') loop
      if length(q->>'id') not between 1 and 80 or jsonb_typeof(q->'answers') is distinct from 'array' or jsonb_array_length(q->'answers')=0 then raise exception 'Invalid question snapshot'; end if;
      val:=coalesce(r->'answers'->>(q->>'id'),'');
      insert into ai_practice.answers(run_id,question_id,value,is_correct)
      values(rid,q->>'id',val,ai_practice.answer_matches(q->'answers',val));
      if ai_practice.answer_matches(q->'answers',val) then correct:=correct+1; end if;
    end loop;
    update ai_practice.runs set correct_count=correct where id=rid;
  end loop;
  delete from ai_practice.bookmarks where user_id=uid;
  insert into ai_practice.bookmarks(user_id,question_id) select uid,value from jsonb_array_elements_text(p_state->'bookmarks') on conflict do nothing;
  delete from ai_practice.notes where user_id=uid;
  for n in select * from jsonb_each(p_state->'notes') loop
    if jsonb_typeof(n.value)<>'string' then raise exception 'Invalid note'; end if;
    insert into ai_practice.notes(user_id,question_id,body) values(uid,n.key,n.value#>>'{}');
  end loop;
  update ai_practice.learner_profiles set revision=revision+1,custom_bank=p_state->'customBank',updated_at=now() where user_id=uid;
  return rev+1;
end;
$$;

create function ai_practice.load_learning_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); result jsonb; all_runs jsonb; active jsonb; attempts jsonb;
begin
  if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select coalesce(jsonb_agg(x.payload order by x.finished_at desc nulls first),'[]'::jsonb) into all_runs from (
    select r.finished_at,jsonb_build_object('id',r.id,'title',r.title,'mode',r.mode,'questions',r.questions,'cases',r.cases,
      'answers',coalesce((select jsonb_object_agg(a.question_id,a.value) from ai_practice.answers a where a.run_id=r.id),'{}'::jsonb),
      'checked',r.checked,'marked',r.marked,'current',r.current_index,
      'startedAt',floor(extract(epoch from r.started_at)*1000),'deadline',floor(extract(epoch from r.deadline)*1000)) ||
      case when r.finished_at is null then '{}'::jsonb else jsonb_build_object('finishedAt',floor(extract(epoch from r.finished_at)*1000),'reason',r.finish_reason) end as payload
    from ai_practice.runs r where r.user_id=uid order by r.finished_at desc nulls first limit 51
  ) x;
  select coalesce(jsonb_agg(v),'[]'::jsonb) into attempts from jsonb_array_elements(all_runs) v where v ? 'finishedAt';
  select v into active from jsonb_array_elements(all_runs) v where not(v ? 'finishedAt') limit 1;
  select jsonb_build_object('revision',coalesce(p.revision,0),'state',jsonb_build_object(
    'version',1,'attempts',attempts,'active',active,
    'bookmarks',coalesce((select jsonb_agg(question_id order by question_id) from ai_practice.bookmarks where user_id=uid),'[]'::jsonb),
    'notes',coalesce((select jsonb_object_agg(question_id,body) from ai_practice.notes where user_id=uid),'{}'::jsonb),
    'customBank',coalesce(p.custom_bank,'{"version":1,"courses":[],"subjects":[],"topics":[],"cases":[],"questions":[]}'::jsonb)))
    into result from (select 1) dummy left join ai_practice.learner_profiles p on p.user_id=uid;
  return result;
end;
$$;

create function ai_practice.publish_bank(p_bank jsonb) returns void language plpgsql security definer set search_path='' as $$
declare item jsonb;
begin
  if not ai_practice.is_staff() then raise exception 'Editor permission required' using errcode='42501'; end if;
  if p_bank is null or p_bank->>'version' is distinct from '1' or octet_length(p_bank::text)>4000000
    or jsonb_typeof(p_bank->'courses') is distinct from 'array'
    or jsonb_typeof(p_bank->'subjects') is distinct from 'array'
    or jsonb_typeof(p_bank->'topics') is distinct from 'array'
    or jsonb_typeof(p_bank->'cases') is distinct from 'array'
    or jsonb_typeof(p_bank->'questions') is distinct from 'array'
    or jsonb_array_length(p_bank->'questions')>500 then raise exception 'Invalid question bank'; end if;
  for item in select value from jsonb_array_elements(p_bank->'courses') loop
    insert into ai_practice.courses(id,content,published) values(item->>'id',item,true)
    on conflict(id) do update set content=excluded.content,published=true,updated_at=now();
  end loop;
  for item in select value from jsonb_array_elements(p_bank->'subjects') loop
    insert into ai_practice.subjects(id,course_id,content) values(item->>'id',item->>'courseId',item)
    on conflict(id) do update set course_id=excluded.course_id,content=excluded.content;
  end loop;
  for item in select value from jsonb_array_elements(p_bank->'topics') loop
    insert into ai_practice.topics(id,subject_id,content) values(item->>'id',item->>'subjectId',item)
    on conflict(id) do update set subject_id=excluded.subject_id,content=excluded.content;
  end loop;
  for item in select value from jsonb_array_elements(p_bank->'cases') loop
    insert into ai_practice.cases(id,course_id,content,published) values(item->>'id',item->>'courseId',item,true)
    on conflict(id) do update set course_id=excluded.course_id,content=excluded.content,published=true;
  end loop;
  for item in select value from jsonb_array_elements(p_bank->'questions') loop
    insert into ai_practice.questions(id,course_id,subject_id,topic_id,case_id,question_type,published,content)
    values(item->>'id',item->>'courseId',item->>'subjectId',item->>'topic',item->>'caseId',item->>'kind',true,item)
    on conflict(id) do update set course_id=excluded.course_id,subject_id=excluded.subject_id,topic_id=excluded.topic_id,
      case_id=excluded.case_id,question_type=excluded.question_type,published=true,content=excluded.content;
  end loop;
end;
$$;

revoke all on all functions in schema ai_practice from public;
grant execute on function ai_practice.is_staff() to anon,authenticated;
grant execute on function ai_practice.load_learning_state(),ai_practice.save_learning_state(jsonb,bigint) to authenticated;
grant execute on function ai_practice.publish_bank(jsonb) to authenticated;
grant all on all functions in schema ai_practice to service_role;
comment on schema ai_practice is 'Extensible courses/subjects/topics question bank and private personal study records. Public solutions are intentional; not a secure examination system.';
commit;
