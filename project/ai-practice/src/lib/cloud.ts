import { env } from '$env/dynamic/public';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { parseState, validateBank, type LearningState } from './engine';
import type { Bank } from './bank';

let client: SupabaseClient<any, 'ai_practice'> | null = null;
export function cloudClient(): SupabaseClient<any, 'ai_practice'> | null {
  if (client) return client;
  if (!env.PUBLIC_SUPABASE_URL || !env.PUBLIC_SUPABASE_PUBLISHABLE_KEY) return null;
  client = createClient(env.PUBLIC_SUPABASE_URL, env.PUBLIC_SUPABASE_PUBLISHABLE_KEY, {
    db: { schema: 'ai_practice' },
    auth: { storageKey: 'ai-practice.auth', persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });
  return client;
}
export async function loadCatalog(): Promise<Bank> {
  const c = cloudClient();
  if (!c) throw new Error('Supabase 연결 정보가 없습니다.');
  const names = ['courses','subjects','topics','questions','cases'] as const;
  const results = await Promise.all(names.map(async name=>{
    const rows: {content:unknown}[]=[];
    for(let offset=0;offset<10000;offset+=500){
      let query=c.from(name).select('content').order('id').range(offset,offset+499);
      if(['courses','cases','questions'].includes(name))query=query.eq('published',true);
      if(name==='questions')query=query.in('question_type',['choice','short']);
      const {data,error}=await query;if(error)throw error;
      rows.push(...(data??[]));if(!data||data.length<500)break;
    }
    return rows;
  }));
  const bank: Record<string,unknown> = {version:1};
  for (let i=0;i<names.length;i++) bank[names[i]]=results[i].map(row=>row.content);
  // Editors can read drafts through RLS; the learner catalog still shows published courses only.
  const candidate=bank as unknown as Bank;
  candidate.subjects=candidate.subjects.filter(s=>candidate.courses.some(c=>c.id===s.courseId));
  candidate.topics=candidate.topics.filter(t=>candidate.subjects.some(s=>s.id===t.subjectId));
  candidate.cases=candidate.cases.filter(c=>candidate.courses.some(course=>course.id===c.courseId));
  candidate.questions=candidate.questions.filter(q=>candidate.courses.some(c=>c.id===q.courseId)&&(!q.caseId||candidate.cases.some(c=>c.id===q.caseId)));
  return validateBank(candidate);
}
export async function loadCloud(): Promise<{revision: number; state: LearningState}> {
  const c = cloudClient();
  if (!c) throw new Error('Supabase 연결 정보가 없습니다.');
  const {data,error} = await c.rpc('load_learning_state');
  if (error) throw error;
  return { revision: Number(data.revision), state: parseState(JSON.stringify(data.state)) };
}
export async function saveCloud(state: LearningState, revision: number): Promise<number> {
  const c = cloudClient();
  if (!c) throw new Error('Supabase 연결 정보가 없습니다.');
  const {data,error} = await c.rpc('save_learning_state', {p_state:state,p_revision:revision});
  if (error) throw error;
  return Number(data);
}
