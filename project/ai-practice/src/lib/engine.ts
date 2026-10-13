import { emptyBank } from './bank.ts';
import type { Bank, Question, CaseStudy } from './bank.ts';

export interface Session {
  id: string;
  title: string;
  mode: 'practice' | 'exam';
  questions: Question[];
  cases: CaseStudy[];
  answers: Record<string, string>;
  checked: string[];
  marked: string[];
  current: number;
  startedAt: number;
  deadline: number | null;
}
export interface Attempt extends Session { finishedAt: number; reason: 'manual' | 'timeout' }
export interface LearningState {
  version: 1;
  attempts: Attempt[];
  bookmarks: string[];
  notes: Record<string, string>;
  customBank: Bank;
  active: Session | null;
}
export const STORAGE_KEY = 'ai-practice.v1';
// Content and records use a JSON contract. JSON cloning also accepts Svelte's reactive proxies.
const cloneJson = <T>(value:T): T => JSON.parse(JSON.stringify(value)) as T;
export const emptyState = (): LearningState => ({ version: 1, attempts: [], bookmarks: [], notes: {}, customBank: emptyBank(), active: null });

// Whitespace and ASCII case are formatting only. Commas and units remain significant.
export const normalizeAnswer = (answer: string) => answer.normalize('NFKC').replace(/\s+/g, '').toLocaleUpperCase();
export function isCorrect(question: Question, answer: string | undefined): boolean {
  if (!answer?.trim()) return false;
  return question.answers.some(expected => normalizeAnswer(expected) === normalizeAnswer(answer));
}
export function grade(session: Session) {
  const correct = session.questions.filter(q => isCorrect(q, session.answers[q.id])).length;
  const answered = session.questions.filter(q => Boolean(session.answers[q.id]?.trim())).length;
  return { correct, answered, total: session.questions.length, score: session.questions.length ? Math.round(correct / session.questions.length * 100) : 0 };
}
export function latestResults(attempts: Attempt[]): Map<string, boolean> {
  const latest = new Map<string, boolean>();
  for (const attempt of [...attempts].sort((a,b) => a.finishedAt - b.finishedAt)) {
    for (const question of attempt.questions) latest.set(question.id, isCorrect(question, attempt.answers[question.id]));
  }
  return latest;
}
export function makeSession(questions: Question[], cases: CaseStudy[], title: string, minutes?: number, now = Date.now()): Session {
  if (!questions.length) throw new Error('풀 수 있는 문제가 없습니다.');
  return { id: globalThis.crypto.randomUUID(), title, mode: minutes ? 'exam' : 'practice', questions: cloneJson(questions), cases: cloneJson(cases.filter(c => questions.some(q => q.caseId === c.id))), answers: {}, checked: [], marked: [], current: 0, startedAt: now, deadline: minutes ? now + minutes * 60000 : null };
}
export function remainingSeconds(session: Session, now = Date.now()): number | null {
  return session.deadline === null ? null : Math.max(0, Math.ceil((session.deadline - now) / 1000));
}
export const shuffled = <T>(values: T[]): T[] => {
  const copy = [...values];
  for (let i = copy.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [copy[i],copy[j]] = [copy[j],copy[i]]; }
  return copy;
};
export const displayAnswer = (q: Question, answer: string | undefined) => !answer?.trim() ? '미응답' : q.kind === 'choice' ? `${Number(answer) + 1}. ${q.choices?.[Number(answer)] ?? '유효하지 않은 답변'}` : answer;

const object = (v: unknown): v is Record<string, unknown> => Boolean(v) && typeof v === 'object' && !Array.isArray(v);
const text = (v: unknown, max = 20000): v is string => typeof v === 'string' && Boolean(v.trim()) && v.length <= max;
const stringArray = (v: unknown, max = 100): v is string[] => Array.isArray(v) && v.length <= max && v.every(x => typeof x === 'string' && x.length <= 20000);
export function validateBank(input: unknown): Bank {
  if (!object(input) || input.version !== 1 || !Array.isArray(input.questions) || !Array.isArray(input.cases) || !Array.isArray(input.courses) || !Array.isArray(input.subjects) || !Array.isArray(input.topics)) throw new Error('version: 1과 courses·subjects·topics·questions·cases 배열이 필요합니다.');
  if (input.questions.length > 5000 || input.cases.length > 1000) throw new Error('문제은행은 최대 5,000문항, 사례 1,000개까지 지원합니다.');
  const courseIds = new Set<string>(), subjectIds = new Map<string,string>(), topicIds = new Map<string,string>();
  for (const c of input.courses) {
    if (!object(c) || !text(c.id,80) || courseIds.has(c.id) || !text(c.title,200) || !text(c.description) || !text(c.category,80) || !Array.isArray(c.exams) || c.exams.length > 20 || !c.exams.every(e => object(e) && text(e.id,80) && text(e.title,200) && text(e.section,80) && Number.isInteger(e.count) && Number(e.count)>0 && Number(e.count)<=100 && Number.isInteger(e.minutes) && Number(e.minutes)>0 && Number(e.minutes)<=300 && text(e.description))) throw new Error('과정 정보와 모의고사 설정을 확인하세요.');
    courseIds.add(c.id);
  }
  for (const s of input.subjects) {
    if (!object(s) || !text(s.id,80) || subjectIds.has(s.id) || typeof s.courseId !== 'string' || !courseIds.has(s.courseId) || !text(s.label,200)) throw new Error('과목과 과정 연결을 확인하세요.');
    subjectIds.set(s.id,s.courseId);
  }
  for (const t of input.topics) {
    if (!object(t) || !text(t.id,80) || topicIds.has(t.id) || typeof t.subjectId !== 'string' || !subjectIds.has(t.subjectId) || !text(t.label,200) || !text(t.icon,80)) throw new Error('단원과 과목 연결을 확인하세요.');
    topicIds.set(t.id,t.subjectId);
  }
  const caseIds = new Map<string,string>();
  for (const c of input.cases) {
    if (!object(c) || !text(c.id, 80) || !/^[a-zA-Z0-9_-]+$/.test(c.id) || caseIds.has(c.id) || typeof c.courseId !== 'string' || !courseIds.has(c.courseId) || !text(c.title, 200) || !text(c.summary) || !stringArray(c.columns, 20) || !c.columns.length || !Array.isArray(c.rows) || c.rows.length > 500 || !c.rows.every(row => stringArray(row, 20) && row.length === (c.columns as string[]).length) || !stringArray(c.notes, 30)) throw new Error('사례의 ID·제목·표·안내 형식을 확인하세요.');
    caseIds.set(c.id,c.courseId);
  }
  const ids = new Set<string>();
  for (const q of input.questions) {
    if (!object(q) || !text(q.id, 80) || !/^[a-zA-Z0-9_-]+$/.test(q.id) || ids.has(q.id) || !text(q.title, 200) || typeof q.courseId !== 'string' || typeof q.subjectId !== 'string' || typeof q.topic !== 'string' || subjectIds.get(q.subjectId) !== q.courseId || topicIds.get(q.topic) !== q.subjectId || !['기본','응용','심화'].includes(String(q.level)) || !text(q.section,80) || !['choice','short'].includes(String(q.kind)) || !text(q.prompt) || !text(q.explanation) || !text(q.takeaway) || !stringArray(q.answers, 20) || !q.answers.length || q.answers.some(a => !a.trim())) throw new Error('문제의 ID·과정·과목·단원·정답·해설 형식을 확인하세요.');
    if (q.caseId !== undefined && (typeof q.caseId !== 'string' || caseIds.get(q.caseId)!==q.courseId)) throw new Error(`${q.id}: 같은 과정에 연결한 사례가 없습니다.`);
    if (q.kind === 'choice' && (!stringArray(q.choices, 6) || q.choices.length < 2 || q.choices.some(c => !c.trim()) || q.answers.some(a => !/^\d$/.test(a) || Number(a) >= (q.choices as string[]).length))) throw new Error(`${q.id}: 선택지와 0부터 시작하는 정답 번호를 확인하세요.`);
    ids.add(q.id);
  }
  return cloneJson(input) as unknown as Bank;
}

function validSession(value: unknown, finished: boolean): boolean {
  try {
    if (!object(value) || !text(value.id, 80) || !text(value.title, 200) || !['practice','exam'].includes(String(value.mode)) || !Array.isArray(value.questions) || !value.questions.length || !Array.isArray(value.cases) || !object(value.answers) || !Object.entries(value.answers).every(([k,v]) => text(k,80) && typeof v === 'string' && v.length <= 20000) || !stringArray(value.checked,500) || !stringArray(value.marked,500) || !Number.isInteger(value.current) || Number(value.current) < 0 || Number(value.current) >= value.questions.length || !Number.isFinite(value.startedAt) || (value.deadline !== null && !Number.isFinite(value.deadline)) || (value.mode === 'exam' && value.deadline === null)) return false;
    if (!value.questions.every(q => object(q) && text(q.id,80) && text(q.courseId,80) && text(q.subjectId,80) && text(q.topic,80))) return false;
    const questions=value.questions as unknown as Question[];
    validateBank({version:1,questions,cases:value.cases,
      courses:[...new Set(questions.map(q=>q.courseId))].map(id=>({id,title:id,category:'snapshot',description:'snapshot',exams:[]})),
      subjects:[...new Map(questions.map(q=>[q.subjectId,{id:q.subjectId,courseId:q.courseId,label:q.subjectId}])).values()],
      topics:[...new Map(questions.map(q=>[q.topic,{id:q.topic,subjectId:q.subjectId,label:q.topic,icon:'book'}])).values()]
    });
    const ids=new Set(questions.map(q=>q.id));
    if ([...value.checked,...value.marked,...Object.keys(value.answers)].some(id=>!ids.has(id))) return false;
    if(Number(value.startedAt)<0 || (value.deadline!==null && Number(value.deadline)<=Number(value.startedAt)))return false;
    if (finished && (!Number.isFinite(value.finishedAt) || !['manual','timeout'].includes(String(value.reason)))) return false;
    if(finished && Number(value.finishedAt)<Number(value.startedAt))return false;
    return true;
  } catch { return false; }
}
export function parseState(raw: string): LearningState {
  const data: unknown = JSON.parse(raw);
  if (!object(data) || data.version !== 1 || !Array.isArray(data.attempts) || data.attempts.length > 50 || !data.attempts.every(a => validSession(a,true)) || !stringArray(data.bookmarks,1000) || !object(data.notes) || !Object.entries(data.notes).every(([k,v]) => text(k,80) && typeof v === 'string' && v.length <= 20000) || (data.active !== null && !validSession(data.active,false))) throw new Error('학습 기록 파일 형식을 확인하세요.');
  validateBank(data.customBank);
  return data as unknown as LearningState;
}
