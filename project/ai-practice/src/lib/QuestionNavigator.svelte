<script lang="ts">
  import Icon from './Icon.svelte';
  import { grade, type Session } from './engine';
  let { session, onJump, onMark, onSubmit, onClose }: {
    session: Session;
    onJump: (index:number) => void;
    onMark: () => void;
    onSubmit: () => void;
    onClose?: () => void;
  } = $props();
  const current = $derived(session.questions[session.current]);
</script>

<aside class="answer-sheet" aria-label="문항 이동">
  <div class="section-heading">
    <h2>문항 목록 <span class="sheet-progress">{grade(session).answered}/{session.questions.length} 응답</span></h2>
    {#if onClose}<button class="icon-button" aria-label="문항 목록 닫기" onclick={onClose}><Icon name="close" /></button>{/if}
  </div>
  <div class="answer-grid">
    {#each session.questions as question,index}
      <button class:current={session.current===index} class:answered={Boolean(session.answers[question.id]?.trim())} class:marked={session.marked.includes(question.id)} aria-label={`${index+1}번 ${session.answers[question.id]?.trim()?'응답 완료':'미응답'}${session.marked.includes(question.id)?' 검토 표시':''}`} aria-current={session.current===index?'step':undefined} onclick={()=>onJump(index)}>
        {index+1}{#if session.marked.includes(question.id)}<i></i>{/if}
      </button>
    {/each}
  </div>
  <div class="sheet-legend"><span><i class="answered-dot"></i>응답</span><span><i class="marked-dot"></i>검토</span></div>
  <button class="secondary mark-button" aria-pressed={session.marked.includes(current.id)} onclick={onMark}><Icon name="flag" size={17} />{session.marked.includes(current.id)?'검토 표시 해제':'나중에 다시 검토'}</button>
  <p class="sheet-note">답안은 이 기기에 자동 저장됩니다.</p>
  <button class="primary submit-button" onclick={onSubmit}>풀이 제출</button>
</aside>
