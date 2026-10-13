import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { defaultBank } from '../src/lib/bank.ts';
import { emptyState, makeSession, parseState } from '../src/lib/engine.ts';

// PostgreSQL engine with a minimal Supabase Auth contract. No production connection.
test('Supabase schema, RPC transactions and row-level security',async t=>{
  const db=await PGlite.create();
  t.after(()=>db.close());
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to anon,authenticated,service_role;
    grant execute on function auth.uid() to anon,authenticated,service_role;
    insert into auth.users values('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');`);
  const migrations=['202610130001_ai_practice.sql','202610130002_ai_practice_seed.sql'];
  for(const name of migrations)await db.exec(await readFile(new URL(`../../../backend/supabase/migrations/${name}`,import.meta.url),'utf8'));
  async function user(id:string|null){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id??'']);await db.exec(`set role ${id?'authenticated':'anon'}`);}
  const userA='11111111-1111-4111-8111-111111111111',userB='22222222-2222-4222-8222-222222222222';
  const state=emptyState();
  const session=makeSession(defaultBank.questions.slice(0,2),[],'test');session.answers={K01:'1',K02:'0'};
  state.attempts=[{...session,finishedAt:session.startedAt+1000,reason:'manual'}];state.notes.K01='source check';state.bookmarks=['K01'];
  await t.test('anonymous reads published catalog but cannot read or save private records',async()=>{
    await user(null);
    const count=await db.query<{n:number}>('select count(*)::integer n from ai_practice.questions');assert.equal(count.rows[0].n,36);
    await assert.rejects(db.query('select * from ai_practice.runs'),/permission denied/);
    await assert.rejects(db.query('select ai_practice.save_learning_state($1,0)',[state]),/permission denied/);
  });
  await t.test('owner saves and roundtrips answers, snapshots, notes and bookmark',async()=>{
    await user(userA);
    const saved=await db.query<{rev:number}>('select ai_practice.save_learning_state($1,0) rev',[state]);assert.equal(Number(saved.rows[0].rev),1);
    const loaded=await db.query<{data:{revision:number;state:unknown}}>('select ai_practice.load_learning_state() data');
    const restored=parseState(JSON.stringify(loaded.rows[0].data.state));
    assert.equal(restored.notes.K01,'source check');assert.equal(restored.attempts[0].answers.K01,'1');assert.equal(restored.attempts[0].answers.K02,'0');
    const runs=await db.query<{correct_count:number}>('select correct_count from ai_practice.runs');assert.equal(runs.rows[0].correct_count,1);
  });
  await t.test('stale revision and invalid payload roll back without losing existing data',async()=>{
    await assert.rejects(db.query('select ai_practice.save_learning_state($1,0)',[emptyState()]),/Cloud data changed/);
    const invalid=structuredClone(state);invalid.attempts[0].current=999;
    await assert.rejects(db.query('select ai_practice.save_learning_state($1,1)',[invalid]));
    const count=await db.query<{n:number}>('select count(*)::integer n from ai_practice.runs');assert.equal(count.rows[0].n,1);
  });
  await t.test('active exam and a private imported course roundtrip independently of the public catalog',async()=>{
    state.active=makeSession(defaultBank.questions.slice(20,21),defaultBank.cases,'active exam',30);
    state.active.answers.A01='3';
    state.customBank=JSON.parse(await readFile(new URL('../static/example-course.json',import.meta.url),'utf8'));
    await db.query('select ai_practice.save_learning_state($1,1)',[state]);
    const loaded=await db.query<{data:{state:unknown}}>('select ai_practice.load_learning_state() data');
    const restored=parseState(JSON.stringify(loaded.rows[0].data.state));
    assert.equal(restored.active?.answers.A01,'3');assert.equal(restored.active?.deadline,state.active.deadline);
    assert.equal(restored.customBank.courses[0].id,'sql-practice');
    assert.equal((await db.query("select * from ai_practice.courses where id='sql-practice'")).rows.length,0);
  });
  await t.test('another user sees none of the owner records and cannot forge ownership',async()=>{
    await user(userB);
    for(const table of ['runs','answers','bookmarks','notes','learner_profiles']){const result=await db.query(`select * from ai_practice.${table}`);assert.equal(result.rows.length,0,table);}
    await assert.rejects(db.query('select ai_practice.save_learning_state($1,0)',[state]),/Invalid run ownership/);
    await assert.rejects(db.query('select ai_practice.publish_bank($1)',[defaultBank]),/Editor permission required/);
    await assert.rejects(db.query('insert into ai_practice.staff(user_id) values($1)',[userB]),/permission denied/);
    const updated=await db.query("update ai_practice.questions set content=jsonb_set(content,'{title}','\"forged\"') where id='K01' returning id");
    assert.equal(updated.rows.length,0);
  });
  await t.test('editor publishes a new independent course; question edits keep history',async()=>{
    await db.exec('reset role');await db.query('insert into ai_practice.staff(user_id) values($1)',[userB]);await user(userB);
    const example=JSON.parse(await readFile(new URL('../static/example-course.json',import.meta.url),'utf8'));
    await db.query('select ai_practice.publish_bank($1)',[example]);
    example.questions[0].title='개정된 집계 문제';await db.query('select ai_practice.publish_bank($1)',[example]);
    const history=await db.query<{n:number}>("select count(*)::integer n from ai_practice.question_revisions where question_id='SQL01'");assert.equal(history.rows[0].n,2);
    await user(null);const result=await db.query("select id from ai_practice.courses where id='sql-practice'");assert.equal(result.rows.length,1);
  });
  await t.test('draft courses and questions remain hidden from anonymous users',async()=>{
    await db.exec('reset role');await db.exec("update ai_practice.courses set published=false where id='sql-practice'");await user(null);
    assert.equal((await db.query("select id from ai_practice.questions where course_id='sql-practice'")).rows.length,0);
  });
});
