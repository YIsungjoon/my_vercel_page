<script lang="ts">
  import exampleCourseUrl from '../../static/example-course.json?url';
  import { onMount, tick } from 'svelte';
  import Icon from '$practice/Icon.svelte';
  import QuestionBody from '$practice/QuestionBody.svelte';
  import QuestionNavigator from '$practice/QuestionNavigator.svelte';
  import { defaultBank, emptyBank, type Bank, type Question, type Course, type ExamTemplate } from '$practice/bank';
  import { STORAGE_KEY, emptyState, parseState, validateBank, grade, isCorrect, latestResults, makeSession, shuffled, remainingSeconds, type LearningState, type Attempt } from '$practice/engine';
  import { cloudClient, loadCatalog, loadCloud, saveCloud } from '$practice/cloud';

  type View = 'home' | 'bank' | 'exam' | 'review' | 'manage' | 'quiz' | 'result';
  let view = $state<View>('home');
  let learning = $state<LearningState>(emptyState());
  let ready = $state(false);
  let courseId = $state('ai-first-round');
  let catalog = $state<Bank>(emptyBank());
  let catalogLoaded = $state(false);
  let query = $state('');
  let unit = $state('all');
  let subject = $state('all');
  let filter = $state('all');
  let result = $state<Attempt | null>(null);
  let resultIndex = $state(0);
  let now = $state(Date.now());
  let toast = $state('');
  let storageWarning = $state('');
  let storageBlocked = false;
  let confirm = $state<{title:string;description:string;label:string;action:()=>void} | null>(null);
  let accountOpen = $state(false);
  let questionsOpen = $state(false);
  let authMode = $state<'login'|'signup'>('login');
  let email = $state('');
  let password = $state('');
  let authMessage = $state('');
  let busy = $state(false);
  let userId = $state<string | null>(null);
  let userEmail = $state('');
  let cloudRevision = $state(0);
  let cloudMessage = $state('');
  let cloudConfigured = $state(false);
  let staff = $state(false);
  let fileInput: HTMLInputElement;
  let importMode: 'bank' | 'backup' = 'bank';

  function mergeBanks(...banks: Bank[]): Bank {
    const merged = emptyBank();
    for (const key of ['courses','subjects','topics','questions','cases'] as const) {
      const map = new Map<string,unknown>();
      for (const bank of banks) for (const item of bank[key]) map.set(item.id,item);
      // The five arrays retain their own validated shapes.
      (merged[key] as unknown[]) = [...map.values()];
    }
    return merged;
  }
  const bank = $derived(mergeBanks(catalogLoaded?catalog:defaultBank,learning.customBank));
  const course = $derived(bank.courses.find(c => c.id === courseId) ?? bank.courses[0] ?? {id:'none',title:'등록된 과정 없음',description:'과정 파일을 추가해 학습을 시작하세요.',category:'학습',exams:[],examDate:undefined});
  const questions = $derived(bank.questions.filter(q => q.courseId === course?.id));
  const subjects = $derived(bank.subjects.filter(s => s.courseId === course?.id));
  const units = $derived(bank.topics.filter(t => subjects.some(s => s.id === t.subjectId)));
  const latest = $derived(latestResults(learning.attempts));
  const mastered = $derived(questions.filter(q => latest.get(q.id) === true).length);
  const wrong = $derived(questions.filter(q => latest.get(q.id) === false));
  const attempted = $derived(questions.filter(q => latest.has(q.id)).length);
  const accuracy = $derived(attempted ? Math.round(mastered / attempted * 100) : 0);
  const courseAttempts = $derived(learning.attempts.filter(a => a.questions.some(q => q.courseId === course?.id)));
  const filtered = $derived(questions.filter(q =>
    (subject==='all' || q.subjectId===subject) && (unit==='all' || q.topic===unit)
    && `${q.id} ${q.title} ${q.prompt}`.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())
    && (view==='review' ? filter==='saved' ? learning.bookmarks.includes(q.id) : latest.get(q.id)===false
      : filter==='new' ? !latest.has(q.id) : filter==='saved' ? learning.bookmarks.includes(q.id) : filter==='wrong' ? latest.get(q.id)===false : true)
  ));
  const active = $derived(learning.active);
  const currentQuestion = $derived(active?.questions[active.current]);
  const seconds = $derived(active ? remainingSeconds(active,now) : null);
  const currentResultQuestion = $derived(result?.questions[resultIndex]);
  const nav = [
    {id:'home',label:'학습 대시보드',short:'현황',icon:'home'}, {id:'bank',label:'문제은행',short:'문제',icon:'book'},
    {id:'exam',label:'모의고사',short:'모의고사',icon:'clock'}, {id:'review',label:'오답·북마크',short:'오답',icon:'bookmark'},
    {id:'manage',label:'과정·문제 관리',short:'관리',icon:'settings'}
  ] as const;
  const label = (id:string) => bank.topics.find(t => t.id===id)?.label ?? id;
  const formatTime = (s:number) => `${Math.floor(s/60).toString().padStart(2,'0')}:${(s%60).toString().padStart(2,'0')}`;
  const date = (time:number) => new Intl.DateTimeFormat('ko-KR',{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'}).format(time);
  const daysLeft = $derived(course?.examDate ? Math.ceil((new Date(`${course.examDate}T00:00:00+09:00`).getTime()-now)/86400000) : null);

  function key() { return `${STORAGE_KEY}.${userId ?? 'guest'}`; }
  function persist() {
    if (!ready||storageBlocked) return;
    try { localStorage.setItem(key(),JSON.stringify(learning)); storageWarning=''; }
    catch { storageWarning='브라우저 저장에 실패했습니다. 기록을 백업 파일로 내려받아 주세요.'; }
  }
  function readLocal() {
    storageBlocked=false;
    let raw:string|null=null;
    try { raw=localStorage.getItem(key()); learning=raw ? parseState(raw) : emptyState(); }
    catch {
      learning=emptyState();
      try{if(raw)localStorage.setItem(key()+'.recovery',raw);storageWarning='저장된 기록을 읽지 못해 복구용 사본을 보관했습니다. 백업 파일이 있다면 복원해 주세요.';}
      catch{storageBlocked=true;storageWarning='기존 기록을 보존하기 위해 브라우저 자동 저장을 중단했습니다. 기록을 파일로 백업해 주세요.';}
    }
  }
  function message(text:string) { toast=text; }
  function go(next:View) { questionsOpen=false;view=next; query='';unit='all';subject='all';filter='all'; }
  $effect(()=>{
    const page=view;
    const index=page==='quiz'?learning.active?.current:page==='result'?resultIndex:0;
    if(ready)void tick().then(()=>{window.scrollTo(0,0);document.getElementById('main')?.focus({preventScroll:true});});
    void index;
  });
  $effect(()=>{
    if(confirm||accountOpen||questionsOpen){
      const opener=document.activeElement instanceof HTMLElement?document.activeElement:null;
      void tick().then(()=>document.querySelector<HTMLElement>('[role=dialog] button, [role=dialog] input')?.focus());
      return()=>{void tick().then(()=>{if(opener?.isConnected&&!opener.closest('[inert]'))opener.focus({preventScroll:true});});};
    }
  });
  function modalKey(event:KeyboardEvent) {
    if(!confirm&&!accountOpen&&!questionsOpen)return;
    if(event.key==='Escape'){confirm=null;accountOpen=false;questionsOpen=false;return;}
    if(event.key!=='Tab')return;
    const elements=[...document.querySelectorAll<HTMLElement>('[role=dialog] button:not(:disabled), [role=dialog] input, [role=dialog] a[href]')];
    const first=elements[0],last=elements.at(-1);
    if(event.shiftKey&&document.activeElement===first){event.preventDefault();last?.focus();}
    else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first?.focus();}
  }
  function changeCourse(id:string) { courseId=id;go('home'); }
  function bookmark(id:string) { learning.bookmarks=learning.bookmarks.includes(id)?learning.bookmarks.filter(x=>x!==id):[...learning.bookmarks,id];persist(); }
  function note(id:string,value:string) { learning.notes={...learning.notes,[id]:value};persist(); }
  function launch(list:Question[],title:string,minutes?:number) {
    const start=()=>{learning.active=makeSession(list,bank.cases,title,minutes);now=Date.now();view='quiz';persist();};
    if (!list.length) {message('선택한 조건에 문제가 없습니다.');return;}
    if (active) confirm={title:'진행 중인 풀이가 있습니다',description:'새 풀이를 시작하면 현재 진행 중인 답안은 사라집니다. 완료한 기록과 메모는 유지됩니다.',label:'새 풀이 시작',action:start};
    else start();
  }
  function startExam(template:ExamTemplate) {
    const list=questions.filter(q=>q.section===template.section);
    if(list.length<template.count) {message(`${template.count}문항이 필요하지만 ${list.length}문항만 준비되어 있습니다.`);return;}
    const selection=template.section==='application' ? list.slice(0,template.count) : shuffled(list).slice(0,template.count);
    launch(selection,`${course.title} · ${template.title}`,template.minutes);
  }
  function answer(value:string) {if(!active||!currentQuestion)return;active.answers={...active.answers,[currentQuestion.id]:value};persist();}
  function checkAnswer() {if(!active||!currentQuestion)return;if(!active.answers[currentQuestion.id]?.trim()){message('답안을 먼저 입력해 주세요.');return;}active.checked=[...new Set([...active.checked,currentQuestion.id])];persist();
    if(window.matchMedia('(max-width:760px)').matches)void tick().then(()=>document.getElementById('feedback-'+currentQuestion!.id)?.scrollIntoView({block:'start'}));
  }
  function jump(index:number) {questionsOpen=false;if(active){active.current=index;persist();}}
  function mark() {if(!active||!currentQuestion)return;active.marked=active.marked.includes(currentQuestion.id)?active.marked.filter(x=>x!==currentQuestion.id):[...active.marked,currentQuestion.id];persist();}
  function finish(reason:'manual'|'timeout'='manual') {
    if(!active)return;
    const attempt:Attempt={...structuredClone($state.snapshot(active)),finishedAt:Date.now(),reason};
    learning.attempts=[attempt,...learning.attempts].slice(0,50);learning.active=null;result=attempt;resultIndex=0;view='result';confirm=null;persist();
    if(reason==='timeout')message('제한 시간이 종료되어 답안을 자동 제출했습니다.');
  }
  function requestFinish() {
    if(!active)return;
    questionsOpen=false;
    const missing=grade(active).total-grade(active).answered;
    confirm={title:'풀이를 제출할까요?',description:missing?`아직 ${missing}문항에 응답하지 않았습니다. 미응답은 오답으로 기록됩니다.`:'모든 문항에 응답했습니다. 제출 후 점수와 문항별 해설을 확인할 수 있습니다.',label:'제출하고 결과 보기',action:()=>finish()};
  }
  function download(value:unknown,name:string) {const url=URL.createObjectURL(new Blob([JSON.stringify(value,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
  function chooseImport(mode:'bank'|'backup') {importMode=mode;fileInput.value='';fileInput.click();}
  async function importFile(event:Event) {
    const file=(event.currentTarget as HTMLInputElement).files?.[0];if(!file)return;
    if(file.size>4000000){message('파일은 4MB 이하만 가져올 수 있습니다.');return;}
    try {
      const raw=await file.text();
      if(importMode==='backup') {
        const incoming=parseState(raw);
        confirm={title:'학습 기록을 복원할까요?',description:'이 브라우저의 현재 학습 기록을 백업 파일 내용으로 교체합니다. 필요하면 먼저 현재 기록을 백업하세요.',label:'기록 복원',action:()=>{learning=incoming;persist();go('home');message('학습 기록을 복원했습니다.');}};
      } else {
        const incoming=validateBank(JSON.parse(raw));
        if(incoming.questions.length>500)throw new Error('한 번에 최대 500문항까지 가져올 수 있습니다.');
        const merged=mergeBanks(learning.customBank,incoming);validateBank(mergeBanks(defaultBank,catalog,merged));
        const apply=()=>{learning.customBank=merged;persist();message(`${incoming.courses.length}개 과정, ${incoming.questions.length}개 문제를 가져왔습니다.`);};
        if(incoming.questions.some(q=>bank.questions.some(old=>old.id===q.id)))confirm={title:'기존 문제를 교체할까요?',description:'같은 ID의 과정·문제가 이미 있습니다. 가져온 내용으로 교체되며 기존 풀이 기록에는 당시 문제 사본이 유지됩니다.',label:'가져온 내용 적용',action:apply};
        else apply();
      }
    } catch(error) {message(error instanceof Error?error.message:'파일을 읽을 수 없습니다.');}
  }
  async function authenticate(event:SubmitEvent) {
    event.preventDefault();const client=cloudClient();if(!client)return;busy=true;authMessage='';
    try {
      const {error}=authMode==='login'?await client.auth.signInWithPassword({email,password}):await client.auth.signUp({email,password,options:{emailRedirectTo:window.location.origin+window.location.pathname}});
      if(error)throw error;
      password='';authMessage=authMode==='signup'?'가입 요청을 완료했습니다. 이메일 확인이 설정된 경우 받은 메일에서 인증해 주세요.':'로그인했습니다.';
    } catch(error) {authMessage=error instanceof Error?error.message:'인증에 실패했습니다.';} finally {busy=false;}
  }
  async function logout() {const {error}=await cloudClient()!.auth.signOut();if(error)message(error.message);else accountOpen=false;}
  async function refreshCloudInfo() {
    try {const data=await loadCloud();cloudRevision=data.revision;cloudMessage=data.revision?'클라우드 기록이 있습니다. 불러오거나 현재 기록을 저장하세요.':'아직 클라우드에 저장한 기록이 없습니다.';}catch(error){cloudMessage=error instanceof Error?error.message:'DB 연결을 확인해 주세요.';}
  }
  async function uploadCloud() {
    busy=true;
    try {cloudRevision=await saveCloud($state.snapshot(learning),cloudRevision);cloudMessage=`클라우드 저장 완료 · ${date(Date.now())}`;message('학습 기록을 Supabase에 저장했습니다.');}
    catch(error){cloudMessage=error instanceof Error?error.message:'저장에 실패했습니다.';message(cloudMessage);}finally{busy=false;}
  }
  function requestUpload() {confirm={title:'현재 기록을 클라우드에 저장할까요?',description:'이 계정의 클라우드 학습 기록을 현재 기기의 기록으로 교체합니다. 다른 기기의 최신 기록은 먼저 불러오세요.',label:'클라우드에 저장',action:()=>void uploadCloud()};}
  function requestLoad() {confirm={title:'클라우드 기록을 불러올까요?',description:'현재 기기의 기록을 이 계정의 클라우드 기록으로 교체합니다. 저장하지 않은 풀이가 있다면 먼저 백업하세요.',label:'불러오기',action:()=>void (async()=>{busy=true;try{const data=await loadCloud();learning=data.state;cloudRevision=data.revision;persist();go('home');cloudMessage='클라우드 기록을 불러왔습니다.';}catch(error){message(error instanceof Error?error.message:'불러오기에 실패했습니다.');}finally{busy=false;}})()};}
  async function publish() {
    const client=cloudClient();if(!client)return;busy=true;
    try{const {error}=await client.rpc('publish_bank',{p_bank:$state.snapshot(learning.customBank)});if(error)throw error;catalog=await loadCatalog();message('가져온 과정과 문제를 게시했습니다.');}catch(error){message(error instanceof Error?error.message:'게시에 실패했습니다.');}finally{busy=false;}
  }

  onMount(()=>{
    ready=true;readLocal();cloudConfigured=Boolean(cloudClient());
    const interval=setInterval(()=>{now=Date.now();if(learning.active?.deadline && remainingSeconds(learning.active,now)===0)finish('timeout');},1000);
    const unsubscribe=cloudClient()?.auth.onAuthStateChange((_event,session)=>{
      setTimeout(async()=>{
        const next=session?.user.id??null;
        if(next!==userId){persist();userId=next;userEmail=session?.user.email??'';learning=emptyState();readLocal();view='home';result=null;cloudRevision=0;staff=false;}
        if(next){accountOpen=false;await refreshCloudInfo();const response=await cloudClient()!.from('staff').select('role').eq('user_id',next).maybeSingle();staff=Boolean(response.data);}
      },0);
    }).data.subscription;
    if(cloudConfigured)void loadCatalog().then(data=>{catalog=data;catalogLoaded=true;}).catch(()=>{cloudMessage='공통 DB의 마이그레이션과 ai_practice 스키마 공개 설정을 확인해 주세요.';});
    return()=>{clearInterval(interval);unsubscribe?.unsubscribe();};
  });
</script>

<svelte:head><title>문제연습 · 과정별 문제은행</title><meta name="description" content="과정별 문제 연습, 시간 제한 모의고사, 오답 복습을 한 곳에서. AI 역량평가부터 자격증·공무원 시험까지 확장 가능한 학습 공간." /></svelte:head>
<a class="skip-link" href="#main">본문으로 바로가기</a>
<input class="sr-only" type="file" accept="application/json,.json" bind:this={fileInput} onchange={importFile} aria-label="문제은행 또는 학습 백업 파일" />

<svelte:window onkeydown={modalKey} />
<div class="app-shell" class:quiz-active={view==='quiz'&&Boolean(active)} inert={Boolean(confirm||accountOpen||questionsOpen)}>
  <aside class="sidebar" aria-label="학습 탐색">
    <a class="portal-return" href="/">← 전체 서비스</a>
    <button class="brand" onclick={()=>go('home')}><span class="brand-mark"><Icon name="book" size={22} /></span><span>문제연습<small>과목별 문제은행</small></span></button>
    <div class="course-selector"><label for="course-select">학습 과정</label><select aria-label="학습 과정" id="course-select" value={course?.id} onchange={event=>changeCourse(event.currentTarget.value)}>{#each bank.courses as item}<option value={item.id}>{item.title}</option>{/each}</select></div>
    <button class="mobile-account icon-button" aria-label="학습 계정 및 저장 설정" onclick={()=>accountOpen=true}><Icon name="user" size={21} /></button>
    <nav aria-label="주 메뉴">{#each nav as item}<button class:active={view===item.id || (view==='quiz'&&item.id==='bank') || (view==='result'&&item.id==='home')} aria-label={item.label} aria-current={view===item.id?'page':undefined} onclick={()=>go(item.id)}><Icon name={item.icon} /><span class="desktop-label">{item.label}</span><span class="mobile-label">{item.short}</span>{#if item.id==='review'&&wrong.length}<span class="nav-count">{wrong.length}</span>{/if}</button>{/each}</nav>
    <div class="sidebar-bottom"><button class="profile" onclick={()=>accountOpen=true}><span class="avatar"><Icon name="user" size={18} /></span><span>{userId?'나의 학습 계정':'게스트 학습자'}<small>{userId?'Supabase 연결':'이 브라우저에 기록 저장'}</small></span><Icon name="settings" size={17} /></button></div>
  </aside>

  <div class="workspace">
    <header class="topbar"><span>내 학습 공간 <span class="breadcrumb">/ {view==='quiz'?'문제 풀이':view==='result'?'풀이 결과':nav.find(n=>n.id===view)?.label}</span></span><div class="header-tools"><span class="save-indicator"><i></i>{userId?'계정 연결됨':'브라우저 저장'}</span><button class="icon-button" aria-label="학습 계정 및 저장 설정" onclick={()=>accountOpen=true}><Icon name="user" size={19} /></button></div></header>
    <main id="main" tabindex="-1">
      {#if storageWarning}<div class="alert" role="alert">{storageWarning}<button onclick={()=>download($state.snapshot(learning),'practice-lab-backup.json')}>기록 백업</button></div>{/if}
      {#if !ready}<div class="empty-state"><Icon name="clock" size={30} /><h1>학습 공간을 준비하고 있습니다.</h1></div>
      {:else if view==='home'}
        <div class="page-heading"><div><p class="eyebrow">학습 현황</p><h1>{course.title}</h1><p>{subjects.length}과목 · {questions.length}문항 · 선택형 {questions.filter(q=>q.kind==='choice').length} / 단답형 {questions.filter(q=>q.kind==='short').length}</p></div>{#if course.examDate}<span class="date-chip">목표 시험 {course.examDate}{#if daysLeft!==null&&daysLeft>=0}<b>{daysLeft===0?'오늘':daysLeft+'일 남음'}</b>{/if}</span>{/if}</div>
        {#if active}<div class="resume-banner"><div><Icon name="clock" /><span><strong>{active.title}</strong><small>{grade(active).answered}/{active.questions.length}문항 응답 · 진행 중인 풀이</small></span></div><button class="primary" onclick={()=>view='quiz'}>이어서 풀기 <Icon name="arrow" size={17} /></button></div>{/if}
        <div class="stats-grid"><article class="stat-card"><span>풀어 본 문제</span><strong>{attempted}<small> / {questions.length}</small></strong></article><article class="stat-card"><span>정답률</span><strong>{attempted?accuracy:'—'}<small>{attempted?'%':''}</small></strong></article><article class="stat-card"><span>오답 복습</span><strong>{wrong.length}<small>문제</small></strong></article><article class="stat-card"><span>완료한 풀이</span><strong>{courseAttempts.length}<small>회</small></strong></article></div>
        <div class="start-row"><div><h2>문제 연습</h2><p>아직 풀지 않은 문제부터 최대 10문항을 선택합니다.</p></div><div><button class="secondary" onclick={()=>go('bank')}>문제 직접 선택</button><button class="primary" onclick={()=>{const fresh=questions.filter(q=>!latest.has(q.id));launch(shuffled(fresh.length?fresh:questions).slice(0,10),'10문제 연습');}}>10문제 풀기 <Icon name="arrow" size={17} /></button></div></div>
        <div class="dashboard-columns"><section class="panel"><div class="section-heading"><h2>단원별 문제</h2><button class="text-button" onclick={()=>go('bank')}>전체 문제 보기 <Icon name="arrow" size={16} /></button></div><div class="unit-table-heading"><span>단원</span><span>풀이 / 전체</span><span>정답률</span></div><div class="unit-list">{#each units as item}{@const all=questions.filter(q=>q.topic===item.id)}{@const done=all.filter(q=>latest.has(q.id))}{@const right=done.filter(q=>latest.get(q.id)===true)}<button class="unit-row" onclick={()=>{go('bank');unit=item.id;}}><span class="unit-info"><strong>{item.label}</strong></span><span class="unit-count">{done.length} / {all.length}</span><span class="unit-accuracy">{done.length?Math.round(right.length/done.length*100)+'%':'—'}</span><Icon name="arrow" size={16} /></button>{/each}</div><p class="table-note">풀이·정답률은 문제별 마지막 제출을 기준으로 계산합니다.</p></section><section class="exam-callout"><div class="section-heading"><h2>모의고사</h2><Icon name="clock" size={19} /></div>{#each course.exams as template}<div class="exam-overview-row"><strong>{template.title}</strong><span>{template.count}문제 / {template.minutes}분</span></div>{/each}{#if !course.exams.length}<p>등록된 모의고사가 없습니다.</p>{/if}<p class="exam-overview-note">제한 시간 종료 시 자동 제출됩니다.<br />해설은 제출 후 확인할 수 있습니다.</p><button class="secondary" onclick={()=>go('exam')}>모의고사 선택 <Icon name="arrow" size={17} /></button></section></div>
        <section class="recent-panel"><div class="section-heading"><h2>최근 풀이 기록</h2><span>{courseAttempts.length}회</span></div>{#if courseAttempts.length}{#each courseAttempts.slice(0,5) as attempt}<button class="history-row" onclick={()=>{result=attempt;resultIndex=0;view='result';}}><span><strong>{attempt.title}</strong><small>{date(attempt.finishedAt)} · {attempt.questions.length}문항</small></span><b>{grade(attempt).score}<small>점</small></b><Icon name="arrow" size={17} /></button>{/each}{:else}<div class="history-empty">아직 완료한 풀이가 없습니다. 문제를 제출하면 이곳에 기록됩니다.</div>{/if}</section>
        {#if course.id==='ai-first-round'}<p class="source-note">AI 과정의 기본 문제는 자체 제작한 연습문제입니다. 모의고사 시간과 문항 수는 안내 일정에 맞췄으며, 실제 시험 유형·출제 범위는 별도 공지를 확인해야 합니다.</p>{/if}
      {:else if view==='bank'||view==='review'}
        <div class="page-heading"><div><p class="eyebrow">{view==='review'?'REVIEW & REMEMBER':'QUESTION BANK'}</p><h1>{view==='review'?'오답·북마크':'문제은행'}</h1><p>{view==='review'?'마지막 풀이에서 틀린 문제와 저장한 문제를 복습하세요.':`${course.title} · ${questions.length}개 자체 제작 문제`}</p></div><button class="primary" disabled={!filtered.length} onclick={()=>launch(shuffled(filtered).slice(0,10),view==='review'?'나의 복습':'선택 영역 연습')}>선택 영역 풀기 <Icon name="arrow" size={18} /></button></div>
        <div class="bank-toolbar"><div class="search-box"><Icon name="search" size={18} /><label class="sr-only" for="question-search">문제 검색</label><input id="question-search" type="search" enterkeyhint="search" autocomplete="off" bind:value={query} placeholder="문제 제목, 내용, 번호 검색" /></div><label class="sr-only" for="subject-filter">과목</label><select id="subject-filter" bind:value={subject} onchange={()=>unit='all'}><option value="all">전체 과목</option>{#each subjects as item}<option value={item.id}>{item.label}</option>{/each}</select><label class="sr-only" for="status-filter">학습 상태</label><select id="status-filter" bind:value={filter}>{#if view==='review'}<option value="all">오답 문제</option><option value="saved">북마크</option>{:else}<option value="all">전체 상태</option><option value="new">아직 안 푼 문제</option><option value="wrong">오답 문제</option><option value="saved">북마크</option>{/if}</select></div>
        <div class="topic-filters" role="group" aria-label="단원 선택"><button class:selected={unit==='all'} aria-pressed={unit==='all'} onclick={()=>unit='all'}>전체 단원</button>{#each units.filter(t=>subject==='all'||t.subjectId===subject) as item}<button class:selected={unit===item.id} aria-pressed={unit===item.id} onclick={()=>unit=item.id}>{item.label}</button>{/each}</div>
        <div class="list-heading"><span>총 <strong>{filtered.length}</strong>문제</span><span>단일 선택 · 단답형</span></div>
        {#if filtered.length}<div class="question-list">{#each filtered as question}<article class="question-row"><span class="question-number">{question.id}</span><div class="question-info"><div class="question-tags"><span>{label(question.topic)}</span><span>{question.level}</span><span>{question.kind==='choice'?'선택형':'단답형'}</span>{#if latest.has(question.id)}<span class:tag-correct={latest.get(question.id)} class:tag-wrong={!latest.get(question.id)}>{latest.get(question.id)?'정답':'복습 필요'}</span>{/if}</div><button class="question-title" onclick={()=>launch([question],question.title)}>{question.title}</button><p>{question.prompt}</p></div><div class="question-actions"><button class="icon-button" class:bookmarked={learning.bookmarks.includes(question.id)} aria-label={`${question.id} 북마크 ${learning.bookmarks.includes(question.id)?'해제':'추가'}`} aria-pressed={learning.bookmarks.includes(question.id)} onclick={()=>bookmark(question.id)}><Icon name="bookmark" size={19} /></button><button class="row-start" onclick={()=>launch([question],question.title)}>풀기 <Icon name="arrow" size={16} /></button></div></article>{/each}</div>{:else}<div class="empty-state"><Icon name={view==='review'?'check':'search'} size={35} /><h2>{view==='review'?'아직 복습할 문제가 없습니다.':'조건에 맞는 문제가 없습니다.'}</h2><p>{view==='review'?'문제를 제출하거나 북마크하면 여기에 모입니다.':'검색어나 단원·학습 상태를 바꿔 보세요.'}</p><button class="secondary" onclick={()=>{query='';unit='all';subject='all';filter='all';if(view==='review')go('bank');}}>문제은행 보기</button></div>{/if}
      {:else if view==='exam'}
        <div class="page-heading"><div><p class="eyebrow">MOCK EXAM</p><h1>모의고사</h1><p>제한 시간 안에 풀고, 제출 후 근거와 취약 영역을 확인하세요.</p></div></div>
        {#if course.id==='ai-first-round'}<div class="notice"><Icon name="info" /><p><strong>10월 17일 일정의 시간·문항 수를 반영했습니다.</strong><br />1교시 14:00–14:30 / 2교시 15:00–16:30. 아래 유형은 연습용 구성입니다. 실제 시험 유형·도구 허용 여부는 별도 안내를 확인하세요.</p></div>{/if}
        <div class="exam-grid">{#each course.exams as template,index}<article class="exam-card"><div class="exam-card-top"><span class="pill">MOCK {String(index+1).padStart(2,'0')}</span><Icon name={index%2?'layers':'clock'} size={32} /></div><h2>{template.title}</h2><p>{template.description}</p><div class="exam-numbers"><span><strong>{template.count}</strong>문항</span><span><strong>{template.minutes}</strong>분</span></div><ul><li>응답·검토 표시 자동 저장</li><li>시간 종료 시 자동 제출</li><li>제출 후 전체 해설 공개</li></ul><button class="primary" disabled={questions.filter(q=>q.section===template.section).length<template.count} onclick={()=>startExam(template)}>{questions.filter(q=>q.section===template.section).length<template.count?'문항 준비 중':'모의고사 시작'}<Icon name="arrow" size={18} /></button></article>{/each}</div>
        <section class="panel exam-history"><div class="section-heading"><h2>모의고사 기록</h2></div>{#each courseAttempts.filter(a=>a.mode==='exam') as attempt}<button class="history-row" onclick={()=>{result=attempt;resultIndex=0;view='result';}}><span><strong>{attempt.title}</strong><small>{date(attempt.finishedAt)} · {attempt.reason==='timeout'?'시간 종료':'직접 제출'}</small></span><b>{grade(attempt).score}<small>점</small></b><Icon name="arrow" size={17} /></button>{:else}<p class="muted">아직 완료한 모의고사가 없습니다.</p>{/each}</section>
      {:else if view==='quiz'&&active&&currentQuestion}
        <div class="quiz-heading"><button class="text-button" onclick={()=>go('home')}><Icon name="back" size={17} /> 나중에 계속</button><span class="quiz-mode">{active.mode==='exam'?'모의고사':'자유 연습'}</span><span class="timer" class:urgent={seconds!==null&&seconds<300}><Icon name="clock" size={18} />{#if seconds===null}<span class="desktop-label">시간 제한 없음</span><span class="mobile-label">제한 없음</span>{:else}{formatTime(seconds)}{/if}</span><div class="mobile-question-controls"><button class="secondary" aria-controls="mobile-question-sheet" aria-expanded={questionsOpen} onclick={()=>questionsOpen=true}><Icon name="list" size={18} /> 문항 목록 <span>{active.current+1}/{active.questions.length}</span></button><button class="secondary" aria-pressed={active.marked.includes(currentQuestion.id)} onclick={mark}><Icon name="flag" size={17} />{active.marked.includes(currentQuestion.id)?'검토 표시됨':'검토 표시'}</button></div></div>
        <div class="quiz-layout"><section class="question-panel"><div class="question-panel-header"><span class="eyebrow">QUESTION {String(active.current+1).padStart(2,'0')} <span>/ {active.questions.length}</span></span><button class="icon-button" class:bookmarked={learning.bookmarks.includes(currentQuestion.id)} aria-label="현재 문제 북마크" aria-pressed={learning.bookmarks.includes(currentQuestion.id)} onclick={()=>bookmark(currentQuestion.id)}><Icon name="bookmark" /></button></div><div class="question-tags"><span>{label(currentQuestion.topic)}</span><span>{currentQuestion.level}</span><span>{currentQuestion.id}</span></div><h1 class="quiz-title">{currentQuestion.title}</h1>
          {#key currentQuestion.id}<QuestionBody question={currentQuestion} caseStudy={active.cases.find(c=>c.id===currentQuestion.caseId)} answer={active.answers[currentQuestion.id]??''} revealed={active.mode==='practice'&&active.checked.includes(currentQuestion.id)} note={learning.notes[currentQuestion.id]??''} onAnswer={answer} onNote={value=>note(currentQuestion.id,value)} />{/key}
          <div class="question-footer"><button class="secondary" disabled={active.current===0} onclick={()=>jump(active.current-1)}><Icon name="back" size={17} /> 이전</button><div>{#if active.mode==='practice'&&!active.checked.includes(currentQuestion.id)}<button class="primary" onclick={checkAnswer}>정답 확인 <Icon name="check" size={17} /></button>{:else if active.current<active.questions.length-1}<button class="primary" onclick={()=>jump(active.current+1)}>다음 문제 <Icon name="arrow" size={17} /></button>{:else}<button class="primary" onclick={requestFinish}>풀이 제출 <Icon name="check" size={17} /></button>{/if}{#if active.mode==='exam'&&active.current<active.questions.length-1}<button class="text-button" onclick={requestFinish}>제출</button>{/if}</div></div>
        </section><div class="desktop-question-sheet"><QuestionNavigator session={active} onJump={jump} onMark={mark} onSubmit={requestFinish} /></div></div>
      {:else if view==='result'&&result&&currentResultQuestion}
        <div class="page-heading"><div><p class="eyebrow">LEARNING REPORT</p><h1>풀이 결과</h1><p>{result.title} · {date(result.finishedAt)}</p></div><button class="secondary" onclick={()=>go('bank')}>다음 학습으로 <Icon name="arrow" size={17} /></button></div>
        <div class="result-summary"><div class="score-circle"><strong>{grade(result).score}</strong><span>100점 만점</span></div><div><h2>{grade(result).score>=80?'정답과 해설을 확인하세요.':'오답의 해설을 확인하고 다시 풀어 보세요.'}</h2><div class="result-numbers"><span>정답 <b>{grade(result).correct}</b> / {result.questions.length}</span><span>미응답 <b>{result.questions.length-grade(result).answered}</b></span><span>소요 시간 <b>{formatTime(Math.max(0,Math.floor((result.finishedAt-result.startedAt)/1000)))}</b></span></div><p>문제별 마지막 제출 결과가 대시보드와 오답노트에 반영됩니다.</p></div></div>
        <div class="result-question-nav" role="group" aria-label="해설 볼 문항">{#each result.questions as question,index}<button class:correct={isCorrect(question,result.answers[question.id])} class:wrong={!isCorrect(question,result.answers[question.id])} class:current={resultIndex===index} aria-pressed={resultIndex===index} onclick={()=>resultIndex=index}>{index+1}<Icon name={isCorrect(question,result.answers[question.id])?'check':'close'} size={14} /></button>{/each}</div>
        <section class="question-panel result-detail"><div class="question-tags"><span>{label(currentResultQuestion.topic)}</span><span>{currentResultQuestion.id}</span></div><h2 class="quiz-title">{currentResultQuestion.title}</h2>{#key currentResultQuestion.id}<QuestionBody question={currentResultQuestion} caseStudy={result.cases.find(c=>c.id===currentResultQuestion.caseId)} answer={result.answers[currentResultQuestion.id]??''} revealed={true} note={learning.notes[currentResultQuestion.id]??''} onNote={value=>note(currentResultQuestion.id,value)} />{/key}<div class="question-footer"><button class="secondary" onclick={()=>bookmark(currentResultQuestion.id)}><Icon name="bookmark" size={17} />{learning.bookmarks.includes(currentResultQuestion.id)?'북마크 해제':'북마크에 저장'}</button><button class="primary" onclick={()=>launch([currentResultQuestion],`복습 · ${currentResultQuestion.title}`)}>다시 풀기 <Icon name="arrow" size={17} /></button></div></section>
      {:else if view==='manage'}
        <div class="page-heading"><div><p class="eyebrow">COURSES & CONTENT</p><h1>과정·문제 관리</h1><p>과정 파일을 추가해 자격증·공무원 시험 등 새로운 과목을 학습하세요.</p></div></div>
        <div class="manage-grid"><section class="panel"><div class="section-heading"><h2>과정과 문제은행</h2><Icon name="book" /></div><p class="muted">과정 → 과목 → 단원 → 문제로 구성됩니다. 파일을 가져오면 내 학습 공간에 추가됩니다.</p><div class="manage-actions"><button class="primary" onclick={()=>chooseImport('bank')}><Icon name="upload" size={17} /> 과정 파일 가져오기</button><button class="secondary" onclick={()=>download($state.snapshot(bank),'practice-lab-question-bank.json')}><Icon name="download" size={17} /> 전체 문제은행 내보내기</button><a class="text-button" href={exampleCourseUrl} download>새 과정 예시 파일 <Icon name="download" size={16} /></a></div><p class="small muted">현재 {bank.courses.length}개 과정 · {bank.subjects.length}개 과목 · {bank.questions.length}문항. 지원 유형: 단일 선택·단답형.</p>{#if staff&&learning.customBank.questions.length}<button class="secondary" disabled={busy} onclick={()=>{confirm={title:'가져온 과정을 게시할까요?',description:'게시하면 이 Supabase 서비스의 모든 학습자가 과정과 해설을 볼 수 있습니다. 같은 ID의 콘텐츠는 새 버전으로 수정됩니다.',label:'과정 게시',action:()=>void publish()};}}>편집자: 가져온 과정 게시</button>{/if}</section><section class="panel"><div class="section-heading"><h2>학습 기록 백업</h2><Icon name="shield" /></div><p class="muted">완료한 풀이 최대 50회, 진행 중인 답안, 북마크, 메모와 추가 문제를 백업합니다.</p><div class="manage-actions"><button class="secondary" onclick={()=>download($state.snapshot(learning),'practice-lab-backup.json')}><Icon name="download" size={17} /> 학습 기록 내려받기</button><button class="secondary" onclick={()=>chooseImport('backup')}><Icon name="upload" size={17} /> 백업 파일 복원</button></div><p class="small muted">파일에는 나의 답안과 메모가 포함됩니다. 공유 전에 내용을 확인하세요.</p></section></div>
        <section class="panel course-directory"><div class="section-heading"><h2>추가된 학습 과정</h2><span>{bank.courses.length}개</span></div>{#each bank.courses as item}<div class="course-row"><span class="unit-icon"><Icon name="book" /></span><div><span class="eyebrow">{item.category}</span><h3>{item.title}</h3><p>{bank.subjects.filter(s=>s.courseId===item.id).length}과목 · {bank.questions.filter(q=>q.courseId===item.id).length}문항 · 모의고사 {item.exams.length}개</p></div><button class="secondary" onclick={()=>changeCourse(item.id)}>학습하기 <Icon name="arrow" size={16} /></button></div>{/each}</section>
        <div class="notice"><Icon name="info" /><p>공개 체험 문제 원문과 수집한 첨부 파일은 배포하지 않습니다. 기본 문제는 자체 제작했으며, 추가 콘텐츠는 게시 권한을 확인한 자료를 사용하세요.</p></div>
      {/if}
      <footer class="page-footer"><span>문제연습</span><span>나의 학습 공간 · {bank.courses.length}개 과정</span></footer>
    </main>
  </div>
</div>

{#if questionsOpen&&active}<div class="modal-backdrop question-drawer-backdrop"><div id="mobile-question-sheet" class="question-drawer" role="dialog" aria-modal="true" aria-label="문항 목록" tabindex="-1"><QuestionNavigator session={active} onJump={jump} onMark={mark} onSubmit={requestFinish} onClose={()=>questionsOpen=false} /></div></div>{/if}
{#if toast}<div class="toast" class:quiz-toast={view==='quiz'} role="status"><Icon name="info" size={18} /><span>{toast}</span><button class="icon-button" aria-label="알림 닫기" onclick={()=>toast=''}><Icon name="close" size={17} /></button></div>{/if}
{#if confirm}<div class="modal-backdrop"><div class="modal" role="dialog" aria-modal="true" aria-labelledby="confirm-title" tabindex="-1"><span class="modal-icon"><Icon name="info" size={25} /></span><h2 id="confirm-title">{confirm.title}</h2><p>{confirm.description}</p><div class="modal-actions"><button class="secondary" onclick={()=>confirm=null}>취소</button><button class="primary" onclick={()=>{const action=confirm!.action;confirm=null;action();}}>{confirm.label}</button></div></div></div>{/if}
{#if accountOpen}<div class="modal-backdrop"><div class="modal account-modal" role="dialog" aria-modal="true" aria-labelledby="account-title" tabindex="-1"><div class="section-heading"><h2 id="account-title">학습 계정과 저장</h2><button class="icon-button" aria-label="계정 창 닫기" onclick={()=>accountOpen=false}><Icon name="close" /></button></div>{#if userId}<p class="account-email">{userEmail}</p><p class="muted">브라우저에는 자동 저장됩니다. 기기 사이에서 기록을 옮기려면 클라우드 저장·불러오기를 사용하세요.</p><p class="notice compact" role="status">{cloudMessage}</p><div class="manage-actions"><button class="primary" disabled={busy} onclick={()=>{accountOpen=false;requestUpload();}}><Icon name="cloud" size={17} /> 현재 기록 클라우드 저장</button><button class="secondary" disabled={busy} onclick={()=>{accountOpen=false;requestLoad();}}>클라우드 기록 불러오기</button><button class="text-button" disabled={busy} onclick={logout}>로그아웃</button></div>{:else if cloudConfigured}<div class="auth-tabs"><button class:selected={authMode==='login'} onclick={()=>{authMode='login';authMessage='';}}>로그인</button><button class:selected={authMode==='signup'} onclick={()=>{authMode='signup';authMessage='';}}>회원가입</button></div><p class="muted">공통 Supabase 계정으로 내 학습 기록을 보관하세요. 게스트 기록과 계정 기록은 따로 저장됩니다.</p><form onsubmit={authenticate}><label for="auth-email">이메일</label><input id="auth-email" type="email" bind:value={email} required autocomplete="email" /><label for="auth-password">비밀번호</label><input id="auth-password" type="password" bind:value={password} required minlength="8" autocomplete={authMode==='login'?'current-password':'new-password'} /><button class="primary" disabled={busy}>{busy?'처리 중…':authMode==='login'?'로그인':'회원가입'}</button><p role="status" class="small">{authMessage}</p></form>{:else}<div class="notice"><Icon name="cloud" /><p>지금은 브라우저 저장 모드입니다. Supabase 연결을 설정하면 계정과 클라우드 기록을 사용할 수 있습니다.</p></div><p class="muted">진행 중인 답안·오답·메모는 이 브라우저에 저장됩니다. 과정·문제 관리에서 파일로 백업할 수 있습니다.</p><button class="secondary" onclick={()=>{accountOpen=false;go('manage');}}>백업 관리로 이동</button>{/if}</div></div>{/if}
