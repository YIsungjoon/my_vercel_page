<script lang="ts">
 import { appPath } from '$agri/paths';
	import { farmStore } from '$agri/farmStore.svelte';
	import type { AIConsultation } from '$agri/types';

	let inputQuestion = $state('');
	let isThinking = $state(false);
	let messages = $state<{ sender: 'user' | 'ai'; text: string; time: string }[]>([
		{
			sender: 'ai',
			text: `안녕하세요! <strong>${farmStore.currentFarm.name}</strong> (${farmStore.currentFarm.crop} / ${farmStore.currentFarm.growth_stage}) 전담 AI 농업 컨설턴트입니다.<br/>농장의 작업 기록과 생육 데이터를 기반으로 맞춤형 답변을 드리거나, 전문가 상담용 요약 리포트를 생성해 드립니다.`,
			time: new Date().toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' })
		}
	]);

	// Consultation Report Modal state
	let showSummaryModal = $state(false);
	let summaryText = $state('');
	let copied = $state(false);

	const quickQuestions = [
		'최근 발생한 흰가루병/문제 기록을 분석하고 대책 알려줘',
		`${farmStore.currentFarm.crop} ${farmStore.currentFarm.growth_stage} 주요 주의사항은?`,
		'오늘의 미완료 작업 및 후속 조치 현황 요약해줘',
		'양액 공급 EC/pH 및 환기 관리 가이드 알려줘'
	];

	async function askAI(prompt?: string) {
		const q = prompt || inputQuestion;
		if (!q.trim() || isThinking) return;

		const userTime = new Date().toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' });
		messages = [...messages, { sender: 'user', text: q, time: userTime }];
		inputQuestion = '';
		isThinking = true;

		const farm = farmStore.currentFarm;

		try {
			const res = await fetch(appPath('/api/ai'), {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					question: q,
					farm_name: farm.name,
					crop: farm.crop,
					growth_stage: farm.growth_stage
				})
			});

			const data = await res.json();
			const aiTime = new Date().toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' });
			const responseText = data.answer || '답변을 생성하지 못했습니다.';

			messages = [...messages, { sender: 'ai', text: responseText, time: aiTime }];
			farmStore.addAIConsultation(farm.id, q, responseText);
		} catch (err) {
			const aiTime = new Date().toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' });
			const fallbackText = `💡 <strong>${farm.name} 기록 분석 답변</strong>:<br/>${farm.crop} (${farm.growth_stage}) 표준 가이드에 따라 온실 환기 및 양액 EC 2.2 유지를 권장합니다.`;

			messages = [...messages, { sender: 'ai', text: fallbackText, time: aiTime }];
			farmStore.addAIConsultation(farm.id, q, fallbackText);
		} finally {
			isThinking = false;
		}
	}

	function generateConsultationSummary() {
		const farm = farmStore.currentFarm;
		const tasks = farmStore.currentFarmTasks;
		const pendingTasks = tasks.filter((t) => t.status === 'pending');
		const completedTasks = tasks.filter((t) => t.status === 'completed');
		const issueLogs = farmStore.logs.filter((l) => l.farm_id === farm.id && l.action === 'issue');
		const followupTasks = tasks.filter((t) => t.is_followup);

		const todayStr = new Date().toLocaleDateString('ko-KR', { year: 'numeric', month: 'long', day: 'numeric' });

		summaryText = `================================================
[Dreaming Agri] 농가 현장 종합 상담 및 지도 요약 리포트
작성일자: ${todayStr}
================================================

1. 농가 및 작물 기본 현황
------------------------------------------------
- 농가명: ${farm.name}
- 소재지: ${farm.region}
- 재배 작물 / 품종: ${farm.crop} / ${farm.variety}
- 정식 일자: ${farm.planted_at}
- 현재 생육 단계: ${farm.growth_stage}
- 온실/메모: ${farm.notes || '특이사항 없음'}

2. 최근 발생 문제 및 현장 이슈 (${issueLogs.length}건)
------------------------------------------------
${
	issueLogs.length === 0
		? '- 특이사항 없음 (정상 운영 중)'
		: issueLogs
				.map(
					(l, i) =>
						`${i + 1}. [${l.issue_category || '일반'}] ${l.note} (${l.created_at.slice(0, 10)})`
				)
				.join('\n')
}

3. 미완료 작업 및 생성된 후속 조치 목록 (${pendingTasks.length}건)
------------------------------------------------
${
	pendingTasks.length === 0
		? '- 미완료 작업 없음 (모두 이행 완료)'
		: pendingTasks
				.map(
					(t, i) =>
						`${i + 1}. [${t.category}] ${t.title} (예정일: ${t.scheduled_date}) ${t.is_followup ? '[⚡후속작업]' : ''}`
				)
				.join('\n')
}

4. AI 농업 컨설턴트 종합 권고사항
------------------------------------------------
- ${farm.crop} ${farm.growth_stage}에 맞춘 수분/양액 EC 2.2 정밀 제어 필요.
- 최근 등록된 문제 이슈와 관련하여 후속 작업 우선 처리 권장.
- 지도 기관 및 기술센터 상담 시 본 요약지를 제출하여 자문을 받으시기 바랍니다.
================================================`;

		showSummaryModal = true;
	}

	function copyToClipboard() {
		navigator.clipboard.writeText(summaryText);
		copied = true;
		setTimeout(() => (copied = false), 2000);
	}
</script>

<svelte:head>
	<title>AI 질의응답 & 상담 요약 | Dreaming Agri</title>
</svelte:head>

<main class="page-container">
	<header class="header-bar">
		<div>
			<span class="sub-badge">{farmStore.currentFarm.name}</span>
			<h1>농장 기록 기반 AI 질의응답 & 상담 요약</h1>
			<p>농장의 축적된 작업 및 문제 기록을 바탕으로 즉각적인 AI 상담과 전문가용 요약 리포트를 발급합니다.</p>
		</div>
		<button type="button" class="btn-summary-gen" onclick={generateConsultationSummary}>
			📄 상담용 요약 리포트 생성
		</button>
	</header>

	<div class="chat-container card">
		<div class="chat-header">
			<div class="ai-profile">
				<div class="ai-avatar">🤖</div>
				<div>
					<h3>Dreaming Agri AI Advisor</h3>
					<small>연동 농장: {farmStore.currentFarm.name} ({farmStore.currentFarm.crop})</small>
				</div>
			</div>
		</div>

		<!-- Quick Question Chips -->
		<div class="quick-questions-bar">
			<span>추천 질문:</span>
			{#each quickQuestions as qq}
				<button type="button" class="chip-btn" onclick={() => askAI(qq)}>
					{qq}
				</button>
			{/each}
		</div>

		<!-- Chat Message Window -->
		<div class="chat-messages">
			{#each messages as msg}
				<div class={`message-row ${msg.sender}`}>
					<div class="message-bubble">
						<div class="msg-text">{@html msg.text}</div>
						<span class="msg-time">{msg.time}</span>
					</div>
				</div>
			{/each}
			{#if isThinking}
				<div class="message-row ai">
					<div class="message-bubble thinking">
						AI가 농장 기록을 분석하고 있습니다...
					</div>
				</div>
			{/if}
		</div>

		<!-- Input Box -->
		<form onsubmit={(e) => { e.preventDefault(); askAI(); }} class="chat-input-bar">
			<input
				type="text"
				bind:value={inputQuestion}
				placeholder="농장 기록 및 작물 관리 관련 질문을 입력하세요 (예: 최근 발생 문제 요약)"
			/>
			<button type="submit" class="btn-send" disabled={!inputQuestion.trim() || isThinking}>
				전송
			</button>
		</form>
	</div>

	<!-- AI Consultation History -->
	<section class="card history-section">
		<h3>📜 이전 AI 상담 이력 ({farmStore.consultations.length}건)</h3>
		{#if farmStore.consultations.length === 0}
			<p class="empty-text">저장된 AI 상담 이력이 없습니다.</p>
		{:else}
			<div class="history-list">
				{#each farmStore.consultations as cons}
					<div class="history-item">
						<div class="history-q">
							<strong>Q: {cons.question}</strong>
							<span class="history-time">{cons.created_at.slice(0, 10)}</span>
						</div>
						<div class="history-a">{@html cons.answer}</div>
					</div>
				{/each}
			</div>
		{/if}
	</section>
</main>

<!-- Consultation Summary Report Modal -->
{#if showSummaryModal}
	<div class="modal-backdrop" role="presentation" onkeydown={(event) => event.stopPropagation()} onclick={() => (showSummaryModal = false)}>
		<div class="modal-card report-modal" role="dialog" aria-modal="true" tabindex="-1" onkeydown={(event) => event.stopPropagation()} onclick={(e) => e.stopPropagation()}>
			<div class="modal-header">
				<h3>📄 전문가 상담용 요약 리포트</h3>
				<button type="button" class="btn-close" onclick={() => (showSummaryModal = false)}>&times;</button>
			</div>

			<div class="report-body">
				<textarea readonly class="report-textarea">{summaryText}</textarea>
			</div>

			<div class="modal-actions">
				<button type="button" class="btn-secondary" onclick={() => (showSummaryModal = false)}>닫기</button>
				<button type="button" class="btn-primary" onclick={copyToClipboard}>
					{copied ? '✓ 클립보드 복사 완료!' : '📋 요약문 텍스트 복사'}
				</button>
			</div>
		</div>
	</div>
{/if}

<style>
	.page-container {
		max-width: 1100px;
		margin: 0 auto;
		padding: 36px 24px 60px;
	}

	.header-bar {
		display: flex;
		justify-content: space-between;
		align-items: flex-end;
		gap: 20px;
		margin-bottom: 24px;
		flex-wrap: wrap;
	}

	.sub-badge {
		font-size: 0.8rem;
		font-weight: 800;
		color: #25663b;
		background: #e4f2e1;
		padding: 4px 10px;
		border-radius: 6px;
	}

	h1 { margin: 8px 0; font-size: 2rem; color: #173d29; }

	.header-bar p { margin: 0; color: #5e7366; font-size: 0.94rem; }

	.btn-summary-gen {
		padding: 12px 20px;
		border: 1px solid #25663b;
		border-radius: 12px;
		background: #173d29;
		color: #ffffff;
		font-weight: 750;
		font-size: 0.92rem;
		cursor: pointer;
		box-shadow: 0 4px 14px rgba(23, 61, 41, 0.2);
	}

	.card {
		padding: 24px;
		border: 1px solid #dce5dc;
		border-radius: 20px;
		background: #ffffff;
		box-shadow: 0 8px 24px rgba(23, 61, 41, 0.04);
		margin-bottom: 24px;
	}

	.chat-container {
		display: flex;
		flex-direction: column;
		min-height: 520px;
	}

	.chat-header {
		padding-bottom: 16px;
		border-bottom: 1px solid #edf2ed;
	}

	.ai-profile {
		display: flex;
		align-items: center;
		gap: 12px;
	}

	.ai-avatar {
		width: 44px;
		height: 44px;
		border-radius: 12px;
		background: #e4f2e1;
		display: grid;
		place-items: center;
		font-size: 1.4rem;
	}

	.ai-profile h3 { margin: 0; font-size: 1.1rem; color: #173d29; }

	.ai-profile small { color: #6a7f72; font-size: 0.8rem; }

	.quick-questions-bar {
		display: flex;
		align-items: center;
		gap: 8px;
		margin: 14px 0;
		flex-wrap: wrap;
	}

	.quick-questions-bar span {
		font-size: 0.78rem;
		font-weight: 700;
		color: #597062;
	}

	.chip-btn {
		padding: 6px 12px;
		border: 1px solid #d2ded0;
		border-radius: 999px;
		background: #f6faf6;
		color: #245b38;
		font-size: 0.78rem;
		font-weight: 600;
		cursor: pointer;
	}

	.chip-btn:hover { background: #e4f2e1; }

	.chat-messages {
		flex: 1;
		overflow-y: auto;
		padding: 16px 0;
		display: flex;
		flex-direction: column;
		gap: 14px;
		max-height: 420px;
	}

	.message-row { display: flex; }
	.message-row.user { justify-content: flex-end; }
	.message-row.ai { justify-content: flex-start; }

	.message-bubble {
		max-width: 80%;
		padding: 14px 18px;
		border-radius: 16px;
		font-size: 0.92rem;
		line-height: 1.6;
	}

	.user .message-bubble {
		background: #25663b;
		color: #ffffff;
		border-bottom-right-radius: 4px;
	}

	.ai .message-bubble {
		background: #f0f7ef;
		color: #173d29;
		border-bottom-left-radius: 4px;
		border: 1px solid #e1ebe0;
	}

	.msg-time {
		display: block;
		margin-top: 6px;
		font-size: 0.68rem;
		opacity: 0.7;
	}

	.chat-input-bar {
		display: flex;
		gap: 10px;
		padding-top: 14px;
		border-top: 1px solid #edf2ed;
	}

	.chat-input-bar input {
		flex: 1;
		padding: 12px 16px;
		border: 1px solid #d2ded0;
		border-radius: 12px;
		font-size: 0.92rem;
	}

	.btn-send {
		padding: 12px 24px;
		border: none;
		border-radius: 12px;
		background: #25663b;
		color: #fff;
		font-weight: 700;
		cursor: pointer;
	}

	.btn-send:disabled { background: #a8bdaf; cursor: not-allowed; }

	.history-section h3 { margin-top: 0; color: #173d29; }

	.history-list { display: flex; flex-direction: column; gap: 12px; }

	.history-item {
		padding: 14px;
		border-radius: 12px;
		background: #f8faf8;
		border: 1px solid #e5eee4;
	}

	.history-q {
		display: flex;
		justify-content: space-between;
		font-size: 0.9rem;
		color: #173d29;
		margin-bottom: 6px;
	}

	.history-a { font-size: 0.88rem; color: #43594b; line-height: 1.5; }

	/* Report Modal */
	.modal-backdrop {
		position: fixed;
		inset: 0;
		z-index: 100;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 20px;
		background: rgba(12, 33, 22, 0.6);
		backdrop-filter: blur(4px);
	}

	.report-modal {
		max-width: 680px;
		width: 100%;
		background: #fff;
		border-radius: 20px;
		padding: 28px;
	}

	.modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; }

	.btn-close { border: none; background: none; font-size: 1.5rem; cursor: pointer; }

	.report-textarea {
		width: 100%;
		height: 380px;
		font-family: monospace;
		font-size: 0.85rem;
		line-height: 1.5;
		padding: 16px;
		border: 1px solid #d2ded0;
		border-radius: 12px;
		background: #f8faf8;
		resize: none;
	}

	.modal-actions { display: flex; justify-content: flex-end; gap: 12px; margin-top: 16px; }

	.btn-secondary {
		padding: 10px 18px;
		border: 1px solid #d2ded0;
		border-radius: 10px;
		background: #f4f8f4;
		color: #3b5243;
		font-weight: 600;
		cursor: pointer;
	}

	.btn-primary {
		padding: 10px 20px;
		border: none;
		border-radius: 10px;
		background: #25663b;
		color: #fff;
		font-weight: 700;
		cursor: pointer;
	}
</style>
