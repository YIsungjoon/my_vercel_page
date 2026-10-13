<script lang="ts">
  import type { Question, CaseStudy } from './bank';
  import { displayAnswer, isCorrect } from './engine';
  import Icon from './Icon.svelte';
  let { question, caseStudy, answer = '', revealed = false, note = '', onAnswer, onNote }: {
    question: Question; caseStudy?: CaseStudy; answer?: string; revealed?: boolean; note?: string;
    onAnswer?: (value:string) => void; onNote?: (value:string) => void;
  } = $props();
  const numeric = $derived(question.kind==='short'&&question.answers.every(value=>/^\d+(\.\d+)?$/.test(value.trim())));
</script>

{#if caseStudy}
  <details class="case-panel" open>
    <summary><span><Icon name="layers" size={17} /> 공통 자료</span><strong>{caseStudy.title}</strong></summary>
    <div class="case-content">
      <p>{caseStudy.summary}</p>
      <!-- svelte-ignore a11y_no_noninteractive_tabindex (Keyboard users need to scroll wide data tables.) -->
      <div class="table-scroll" tabindex="0" role="region" aria-label="사례 데이터 표">
        <table><thead><tr>{#each caseStudy.columns as column}<th scope="col">{column}</th>{/each}</tr></thead><tbody>{#each caseStudy.rows as row}<tr>{#each row as cell}<td>{cell}</td>{/each}</tr>{/each}</tbody></table>
      </div>
      <p class="table-scroll-hint"><Icon name="arrow" size={14} /> 표를 좌우로 밀어 전체 내용을 확인하세요.</p>
      <ul>{#each caseStudy.notes as item}<li>{item}</li>{/each}</ul>
    </div>
  </details>
{/if}

<h2 class="question-prompt">{question.prompt}</h2>
{#if question.kind === 'choice'}
  <fieldset class="choices" disabled={revealed}>
    <legend class="sr-only">답안 선택</legend>
    {#each question.choices ?? [] as choice, index}
      <label class:selected={answer === String(index)} class:correct-choice={revealed && question.answers.includes(String(index))} class:wrong-choice={revealed && answer === String(index) && !isCorrect(question,answer)}>
        <input type="radio" name={`answer-${question.id}`} value={String(index)} checked={answer === String(index)} onchange={() => onAnswer?.(String(index))} />
        <span class="choice-index">{index + 1}</span><span>{choice}</span>
        {#if revealed && question.answers.includes(String(index))}<Icon name="check" size={18} />{/if}
      </label>
    {/each}
  </fieldset>
{:else}
  <div class="short-answer"><label for={`answer-${question.id}`}>답안 입력</label><input id={`answer-${question.id}`} value={answer} disabled={revealed} autocomplete="off" autocapitalize="off" spellcheck={false} inputmode={numeric?'decimal':'text'} enterkeyhint="done" maxlength="20000" placeholder="지문에서 요구한 형식으로 입력하세요" oninput={event => onAnswer?.(event.currentTarget.value)} /><p>대소문자·공백 차이는 허용됩니다. 단위·쉼표·순서는 지시를 따라 주세요.</p></div>
{/if}

{#if revealed}
  <section id={`feedback-${question.id}`} class="explanation" class:incorrect={!isCorrect(question,answer)} aria-label="정답과 해설" aria-live="polite">
    <div class="explanation-title"><Icon name={isCorrect(question,answer) ? 'check' : 'info'} /><strong>{isCorrect(question,answer) ? '정답입니다' : answer.trim() ? '다시 확인해 보세요' : '응답하지 않은 문제입니다'}</strong></div>
    <p class="answer-line">정답 <strong>{question.answers.map(a => displayAnswer(question,a)).join(' 또는 ')}</strong></p>
    <p>{question.explanation}</p>
    <div class="takeaway"><Icon name="spark" size={16} /><span>{question.takeaway}</span></div>
  </section>
  <div class="note-field"><label for={`note-${question.id}`}>나의 풀이 메모 <span>자동 저장</span></label><textarea id={`note-${question.id}`} value={note} rows="3" maxlength="20000" placeholder="헷갈린 이유나 다음에 확인할 기준을 적어 보세요." oninput={event => onNote?.(event.currentTarget.value)}></textarea></div>
{/if}
