import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { defaultBank } from '../src/lib/bank.ts';
import { emptyState, grade, isCorrect, latestResults, makeSession, parseState, remainingSeconds, validateBank } from '../src/lib/engine.ts';

test('initial bank covers both timed templates and validates all taxonomy references',()=>{
  assert.equal(validateBank(defaultBank).questions.length,36);
  for(const exam of defaultBank.courses[0].exams)assert.equal(defaultBank.questions.filter(q=>q.section===exam.section).length,exam.count);
});
test('grading distinguishes unanswered, incorrect and correct; preserves comma/order instructions',()=>{
  const q=defaultBank.questions.find(q=>q.id==='A03')!;
  assert.ok(isCorrect(q,' e05, e06 '));assert.ok(!isCorrect(q,'E06,E05'));assert.ok(!isCorrect(q,''));
  const session=makeSession(defaultBank.questions.slice(0,3),[], 'test');
  session.answers={K01:'1',K02:'0'};
  assert.deepEqual(grade(session),{correct:1,answered:2,total:3,score:33});
});
test('deadline uses elapsed wall clock and remains valid after reload',()=>{
  const session=makeSession(defaultBank.questions.slice(0,1),[],'exam',30,1000);
  assert.equal(remainingSeconds(session,1000),1800);assert.equal(remainingSeconds(session,1801000),0);
  const state=emptyState();state.active=session;
  assert.equal(remainingSeconds(parseState(JSON.stringify(state)).active!,1800999),1);
});
test('most recent result replaces a previous wrong answer without duplicating mastery',()=>{
  const session=makeSession(defaultBank.questions.slice(0,1),[],'test');
  const wrong={...session,answers:{K01:'0'},finishedAt:10,reason:'manual' as const};
  const correct={...session,answers:{K01:'1'},finishedAt:20,reason:'manual' as const};
  const results=latestResults([correct,wrong]);assert.equal(results.size,1);assert.equal(results.get('K01'),true);
});
test('imports reject dangling taxonomy, bad answer indices and malformed cases',()=>{
  const a=structuredClone(defaultBank);a.questions[0].subjectId='missing';assert.throws(()=>validateBank(a));
  const b=structuredClone(defaultBank);b.questions[0].answers=['99'];assert.throws(()=>validateBank(b));
  const c=structuredClone(defaultBank);c.cases[0].rows[0].pop();assert.throws(()=>validateBank(c));
});
test('unrelated certification course can be added without modifying application code',async()=>{
  const example=validateBank(JSON.parse(await readFile(new URL('../static/example-course.json',import.meta.url),'utf8')));
  assert.equal(example.courses[0].category,'자격증');assert.equal(example.questions.length,2);
  const q=example.questions[0];assert.ok(isCorrect(q,'2'));
  const reactive=new Proxy(q,{});
  assert.equal(makeSession([reactive],[],'imported course').questions[0].id,'SQL01');
});
test('backup roundtrip keeps active answers, memo, bookmarks and question snapshots',()=>{
  const state=emptyState();state.notes.K01='유창함과 사실성';state.bookmarks=['K01'];state.active=makeSession(defaultBank.questions.slice(0,1),[],'test');state.active.answers.K01='1';
  assert.deepEqual(parseState(JSON.stringify(state)),state);
  assert.throws(()=>parseState('{"version":99}'));
});
