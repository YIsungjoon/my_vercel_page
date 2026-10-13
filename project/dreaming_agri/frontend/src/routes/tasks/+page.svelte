<script lang="ts">
 import { appPath, loginPath } from '$agri/paths';
	import { tick } from 'svelte';
	import { farmStore } from '$agri/farmStore.svelte';
	import FarmingCalendar from '$agri/components/FarmingCalendar.svelte';
	import type { Task, TaskCategory, TaskPriority, IssueCategory } from '$agri/types';
	import type { load } from './+page.server';
	type PageData = Awaited<ReturnType<typeof load>>;

	let { data }: { data: PageData } = $props();
	let serverHydrated = $state(false);

	$effect(() => {
		if (!serverHydrated && data.farms?.length) {
			farmStore.hydrateFromServer(data.farms, data.tasks ?? []);
			serverHydrated = true;
		}
	});

	let viewMode = $state<'today' | 'weekly' | 'all'>('today');
	let statusFilter = $state<string>('all');
	let categoryFilter = $state<string>('all');

	// Modal State for Action (Completion / Issue Registration)
	let activeTask = $state<Task | null>(null);
	let actionType = $state<'completed' | 'skipped' | 'issue'>('completed');
	let actionNote = $state('');
	let actionPhotoUrl = $state('');
	let issueCategory = $state<IssueCategory>('병해충');

	// Auto Follow-up Task options
	let createFollowup = $state(true);
	let followupTitle = $state('');
	let followupDate = $state(new Date(Date.now() + 86400000).toISOString().slice(0, 10));

	// Modal State for New Task Creation
	let showNewTaskModal = $state(false);
	let newTitle = $state('');
	let newDesc = $state('');
	let newDate = $state(new Date().toISOString().slice(0, 10));
	let newCategory = $state<TaskCategory>('관수/시비');
	let newPriority = $state<TaskPriority>('medium');
	let actionDialog = $state<HTMLElement | null>(null);
	let actionFirstInput = $state<HTMLTextAreaElement | null>(null);
	let newTaskDialog = $state<HTMLElement | null>(null);
	let newTaskFirstInput = $state<HTMLInputElement | null>(null);
	let modalOpener: HTMLElement | null = null;

	function openAddTaskForDate(dateStr: string) {
		newDate = dateStr;
		openNewTaskModal();
	}

	function rememberModalOpener() {
		modalOpener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
	}

	function openNewTaskModal() {
		rememberModalOpener();
		showNewTaskModal = true;
	}

	function restoreModalFocus() {
		const opener = modalOpener;
		modalOpener = null;
		void tick().then(() => opener?.focus());
	}

	function closeActionModal() {
		activeTask = null;
		restoreModalFocus();
	}

	function closeNewTaskModal() {
		showNewTaskModal = false;
		restoreModalFocus();
	}

	function handleDialogKeydown(event: KeyboardEvent, dialog: HTMLElement | null, close: () => void) {
		if (event.key === 'Escape') {
			event.preventDefault();
			close();
			return;
		}

		if (event.key !== 'Tab' || !dialog) return;

		const focusable = Array.from(
			dialog.querySelectorAll<HTMLElement>(
				'button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])'
			)
		).filter((element) => !element.hidden && element.getClientRects().length > 0);

		if (focusable.length === 0) {
			event.preventDefault();
			return;
		}

		const first = focusable[0];
		const last = focusable[focusable.length - 1];
		if (event.shiftKey && document.activeElement === first) {
			event.preventDefault();
			last.focus();
		} else if (!event.shiftKey && document.activeElement === last) {
			event.preventDefault();
			first.focus();
		}
	}

	$effect(() => {
		const modalIsOpen = Boolean(activeTask) || showNewTaskModal;
		if (!modalIsOpen) return;

		const previousOverflow = document.body.style.overflow;
		document.body.style.overflow = 'hidden';
		void tick().then(() => {
			if (activeTask) actionFirstInput?.focus();
			else if (showNewTaskModal) newTaskFirstInput?.focus();
		});

		return () => {
			document.body.style.overflow = previousOverflow;
		};
	});

	// Sample Crop Issue Photos for quick selection
	const samplePhotos = [
		{ label: '잎 흰가루병 반점', url: 'https://images.unsplash.com/photo-1592417817098-8f3d6eb12735?w=600&auto=format&fit=crop&q=80' },
		{ label: '참외/작물 시듦 현상', url: 'https://images.unsplash.com/photo-1591857177580-dc82b9ac4e1e?w=600&auto=format&fit=crop&q=80' },
		{ label: '양액 펌프/시설 고장', url: 'https://images.unsplash.com/photo-1581092160607-ee22621dd758?w=600&auto=format&fit=crop&q=80' }
	];

	// Filter tasks according to selected view & filters
	const filteredTasks = $derived.by(() => {
		let list = farmStore.currentFarmTasks;

		if (viewMode === 'today') {
			list = farmStore.todayTasks;
		} else if (viewMode === 'weekly') {
			list = farmStore.weeklyTasks;
		}

		if (statusFilter !== 'all') {
			list = list.filter((t) => t.status === statusFilter);
		}

		if (categoryFilter !== 'all') {
			list = list.filter((t) => t.category === categoryFilter);
		}

		const statusRank = { pending: 0, issue: 1, skipped: 2, completed: 3 } as const;
		const priorityRank = { high: 0, medium: 1, low: 2 } as const;

		return [...list].sort((a, b) => {
			if (viewMode === 'today') {
				const statusDifference = statusRank[a.status] - statusRank[b.status];
				if (statusDifference !== 0) return statusDifference;
			}
			const dateDifference = a.scheduled_date.localeCompare(b.scheduled_date);
			if (dateDifference !== 0) return dateDifference;
			return priorityRank[a.priority] - priorityRank[b.priority];
		});
	});

	const viewHeading = $derived(
		viewMode === 'today' ? '오늘 실행 작업' : viewMode === 'weekly' ? '이번 주 작업' : '전체 작업 일정'
	);

	function openActionModal(task: Task, type: 'completed' | 'skipped' | 'issue') {
		rememberModalOpener();
		activeTask = task;
		actionType = type;
		actionNote = type === 'completed' ? '작업 정상 완료' : type === 'issue' ? '특이사항 발생 및 문제 기록' : '작업 일정 연기';
		actionPhotoUrl = '';
		issueCategory = '병해충';
		createFollowup = type === 'issue';
		followupTitle = `[후속조치] ${task.title} 점검 및 방제`;
		followupDate = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
	}

	async function handleSaveAction(e: SubmitEvent) {
		e.preventDefault();
		if (!activeTask) return;

		const response = await fetch(
			appPath('/api/farms/' + encodeURIComponent(farmStore.selectedFarmId) + '/tasks/actions'),
			{
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					task_id: activeTask.id,
					action: actionType,
					note: actionNote,
					photo_url: actionPhotoUrl,
					issue_category: actionType === 'issue' ? issueCategory : undefined,
					create_followup: actionType === 'issue' && createFollowup,
					followup_title: followupTitle,
					followup_date: followupDate
				})
			}
		);

		if (response.status === 401) {
			window.location.assign(loginPath('/tasks'));
			return;
		}

		const result = await response.json().catch(() => ({}));
		if (!response.ok) {
			alert(result.error || '작업 기록을 저장하지 못했습니다.');
			return;
		}

		if (result.task) farmStore.addPersistedTask(result.task);
		if (result.followup) farmStore.addPersistedTask(result.followup);
		if (result.log) farmStore.addPersistedLog(result.log);

		closeActionModal();
	}
	async function handleCreateTask(e: SubmitEvent) {
		e.preventDefault();
		if (!newTitle) return;

		const response = await fetch(appPath('/api/farms/' + encodeURIComponent(farmStore.selectedFarmId) + '/tasks'), {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				title: newTitle,
				description: newDesc,
				scheduled_date: newDate,
				category: newCategory,
				priority: newPriority,
				is_followup: false
			})
		});

		if (response.status === 401) {
			window.location.assign(loginPath('/tasks'));
			return;
		}

		const result = await response.json().catch(() => ({}));
		if (!response.ok) {
			alert(result.error || '작업 일정을 추가하지 못했습니다.');
			return;
		}

		if (result.task) {
			farmStore.addPersistedTask(result.task);
		}

		newTitle = '';
		newDesc = '';
		closeNewTaskModal();
	}</script>

<svelte:head>
	<title>오늘 & 주간 작업 일정 | Dreaming Agri</title>
</svelte:head>

<main class="page-container">
	<header class="header-bar">
		<div>
			<span class="sub-badge">{farmStore.currentFarm.name}</span>
			<h1>농사 달력 & 농작업 일정</h1>
			<p>전통 24절기 농업 지침, 주간·월간 농사 달력, 작업 수행/문제 기록 및 후속 조치를 통합 관리합니다.</p>
		</div>
		<button type="button" class="btn-primary" onclick={openNewTaskModal}>
			+ 새 작업 일정 등록
		</button>
	</header>

	<!-- Filter Controls & View Selector -->
	<div class="control-panel">
		<div class="view-tabs">
			<button aria-pressed={viewMode === 'today'} class:active={viewMode === 'today'} onclick={() => (viewMode = 'today')}>
				오늘의 작업 ({farmStore.todayTasks.length})
			</button>
			<button aria-pressed={viewMode === 'weekly'} class:active={viewMode === 'weekly'} onclick={() => (viewMode = 'weekly')}>
				주간 작업 ({farmStore.weeklyTasks.length})
			</button>
			<button aria-pressed={viewMode === 'all'} class:active={viewMode === 'all'} onclick={() => (viewMode = 'all')}>
				전체 일정 ({farmStore.currentFarmTasks.length})
			</button>
		</div>

		<div class="filter-group">
			<label class="filter-control" for="task-status-filter">
				<span>상태</span>
				<select id="task-status-filter" bind:value={statusFilter}>
				<option value="all">모든 상태</option>
				<option value="pending">대기 중</option>
				<option value="completed">완료됨</option>
				<option value="issue">문제 발생</option>
				<option value="skipped">연기/미완료</option>
				</select>
			</label>

			<label class="filter-control" for="task-category-filter">
				<span>분류</span>
				<select id="task-category-filter" bind:value={categoryFilter}>
				<option value="all">모든 카테고리</option>
				<option value="관수/시비">관수/시비</option>
				<option value="환경관리">환경관리</option>
				<option value="병해충방제">병해충방제</option>
				<option value="수확/정리">수확/정리</option>
				<option value="후속작업">후속작업</option>
				</select>
			</label>
		</div>
	</div>

	<!-- Tasks List Grid -->
	<section class="tasks-section" aria-labelledby="task-list-heading">
		<div class="section-heading">
			<div>
				<span class="section-kicker">실행 우선순위</span>
				<h2 id="task-list-heading">{viewHeading}</h2>
			</div>
			<strong>{filteredTasks.length}건</strong>
		</div>
		{#if filteredTasks.length === 0}
			<div class="empty-card">
				<p>조건에 일치하는 작업 일정이 없습니다.</p>
			</div>
		{:else}
			<div class="tasks-grid">
				{#each filteredTasks as task}
					<article class={`task-card priority-${task.priority} status-${task.status}`}>
						<div class="task-card-header">
							<div class="header-tags">
								<span class="cat-tag">{task.category}</span>
								<span class={`priority-tag p-${task.priority}`}>
									{task.priority === 'high' ? '높음' : task.priority === 'medium' ? '보통' : '낮음'}
								</span>
								{#if task.is_followup}
									<span class="followup-badge">⚡ 후속작업</span>
								{/if}
							</div>
							<span class="scheduled-date">📅 {task.scheduled_date}</span>
						</div>

						<h3 class="task-title">{task.title}</h3>
						{#if task.description}
							<p class="task-desc">{task.description}</p>
						{/if}

						<!-- Task Action Logs preview if recorded -->
						{#each farmStore.logs.filter((l) => l.task_id === task.id) as log}
							<div class={`log-preview action-${log.action}`}>
								<div class="log-top">
									<strong>[{log.action === 'completed' ? '완료 기록' : log.action === 'issue' ? '문제 기록' : '연기 기록'}]</strong>
									{#if log.issue_category}
										<span class="issue-cat-tag">{log.issue_category}</span>
									{/if}
								</div>
								<p>{log.note}</p>
								{#if log.photo_url}
									<div class="photo-thumbnail">
										<img src={log.photo_url} alt="작업 현장 사진" />
									</div>
								{/if}
							</div>
						{/each}

						<!-- Action Buttons -->
						<div class="task-actions">
							{#if task.status === 'pending'}
								<button
									type="button"
									class="btn-act btn-complete"
									onclick={() => openActionModal(task, 'completed')}
								>
									✓ 완료 등록
								</button>
								<button
									type="button"
									class="btn-act btn-issue"
									onclick={() => openActionModal(task, 'issue')}
								>
									⚠️ 문제/특이사항
								</button>
								<button
									type="button"
									class="btn-act btn-skip"
									onclick={() => openActionModal(task, 'skipped')}
								>
									⏸ 연기
								</button>
							{:else}
								<span class={`status-pill pill-${task.status}`}>
									{task.status === 'completed' ? '✓ 완료됨' : task.status === 'issue' ? '⚠️ 문제 발생 기록됨' : '⏸ 연기됨'}
								</span>
							{/if}
						</div>
					</article>
				{/each}
			</div>
		{/if}
	</section>

	<!-- 24 Solar Terms Farming Calendar Component -->
	<FarmingCalendar onOpenAddTask={openAddTaskForDate} />
</main>

<!-- Task Action / Issue Log Modal -->
{#if activeTask}
	<div class="modal-backdrop" role="presentation" onkeydown={(event) => event.stopPropagation()} onclick={closeActionModal}>
		<div bind:this={actionDialog} class="modal-card" role="dialog" aria-modal="true" aria-labelledby="action-modal-title" tabindex="-1" onkeydown={(event) => handleDialogKeydown(event, actionDialog, closeActionModal)} onclick={(e) => e.stopPropagation()}>
			<div class="modal-header">
				<h3 id="action-modal-title">
					{actionType === 'completed' ? '✅ 작업 완료 등록' : actionType === 'issue' ? '🚨 문제 및 특이사항 등록' : '⏸ 작업 연기 등록'}
				</h3>
				<button type="button" class="btn-close" aria-label="작업 기록 창 닫기" title="닫기" onclick={closeActionModal}>&times;</button>
			</div>

			<form onsubmit={handleSaveAction} class="modal-form">
				<div class="task-summary-box">
					<strong>작업명:</strong> {activeTask.title} ({activeTask.category})
				</div>

				{#if actionType === 'issue'}
					<div class="form-group">
						<label for="issue-cat">문제 분류 (Issue Category) *</label>
						<select id="issue-cat" bind:value={issueCategory} required>
							<option value="병해충">🐛 병해충 발생 (흰가루병, 진딧물 등)</option>
							<option value="시설/장비 고장">⚙️ 시설/장비 고장 (양액 펌프, 센서 등)</option>
							<option value="기상/생육 이상">🌡️ 기상/생육 이상 (고온, 시듦, 황화)</option>
							<option value="자재 부족">📦 자재/양액 부족</option>
							<option value="기타">기타 특이사항</option>
						</select>
					</div>
				{/if}

				<div class="form-group">
					<label for="action-note">수행 메모 & 현장 기록 *</label>
					<textarea
						bind:this={actionFirstInput}
						id="action-note"
						bind:value={actionNote}
						rows="3"
						placeholder={actionType === 'issue' ? '문제 증상, 발생 위치, 발견 세부 내용을 입력하세요.' : '작업 결과 및 특이사항 메모'}
						required
					></textarea>
				</div>

				<!-- Photo Attachment -->
				<div class="form-group">
					<label for="photo-input">📷 사진 첨부 (Photo Attachment)</label>
					<input
						id="photo-input"
						type="text"
						bind:value={actionPhotoUrl}
						placeholder="이미지 URL 입력 또는 아래 샘플 사진 클릭"
					/>

					<div class="sample-photos-box">
						<small>빠른 샘플 사진 선택:</small>
						<div class="sample-btn-group">
							{#each samplePhotos as sample}
								<button
									type="button"
									class="btn-sample"
									onclick={() => (actionPhotoUrl = sample.url)}
								>
									{sample.label}
								</button>
							{/each}
						</div>
					</div>

					{#if actionPhotoUrl}
						<div class="photo-preview-box">
							<img src={actionPhotoUrl} alt="첨부 사진 미리보기" />
							<button type="button" class="btn-clear-photo" onclick={() => (actionPhotoUrl = '')}>삭제</button>
						</div>
					{/if}
				</div>

				<!-- Auto Follow-up Task Creation Section -->
				{#if actionType === 'issue'}
					<div class="followup-creation-box">
						<label class="checkbox-label">
							<input type="checkbox" bind:checked={createFollowup} />
							<strong>⚡ 후속 작업(Follow-up Task) 자동 생성</strong>
						</label>

						{#if createFollowup}
							<div class="followup-fields">
								<div class="form-group">
									<label for="follow-title">후속 작업 제목</label>
									<input id="follow-title" type="text" bind:value={followupTitle} required />
								</div>
								<div class="form-group">
									<label for="follow-date">예정일</label>
									<input id="follow-date" type="date" bind:value={followupDate} required />
								</div>
							</div>
						{/if}
					</div>
				{/if}

				<div class="modal-actions">
					<button type="button" class="btn-secondary" onclick={closeActionModal}>취소</button>
					<button type="submit" class="btn-primary">저장 및 등록</button>
				</div>
			</form>
		</div>
	</div>
{/if}

<!-- New Task Creation Modal -->
{#if showNewTaskModal}
	<div class="modal-backdrop" role="presentation" onkeydown={(event) => event.stopPropagation()} onclick={closeNewTaskModal}>
		<div bind:this={newTaskDialog} class="modal-card" role="dialog" aria-modal="true" aria-labelledby="new-task-modal-title" tabindex="-1" onkeydown={(event) => handleDialogKeydown(event, newTaskDialog, closeNewTaskModal)} onclick={(e) => e.stopPropagation()}>
			<div class="modal-header">
				<h3 id="new-task-modal-title">📋 새 작업 일정 등록</h3>
				<button type="button" class="btn-close" aria-label="새 작업 일정 창 닫기" title="닫기" onclick={closeNewTaskModal}>&times;</button>
			</div>
			<form onsubmit={handleCreateTask} class="modal-form">
				<div class="form-group">
					<label for="task-title">작업 제목 *</label>
					<input bind:this={newTaskFirstInput} id="task-title" type="text" bind:value={newTitle} placeholder="예: 3화방 곁순 제거 및 적엽" required />
				</div>

				<div class="form-group">
					<label for="task-desc">상세 설명</label>
					<textarea id="task-desc" bind:value={newDesc} rows="2" placeholder="작업 방법, 주의사항 등"></textarea>
				</div>

				<div class="form-row">
					<div class="form-group">
						<label for="task-date">예정일 *</label>
						<input id="task-date" type="date" bind:value={newDate} required />
					</div>
					<div class="form-group">
						<label for="task-cat">카테고리 *</label>
						<select id="task-cat" bind:value={newCategory}>
							<option value="관수/시비">관수/시비</option>
							<option value="환경관리">환경관리</option>
							<option value="병해충방제">병해충방제</option>
							<option value="수확/정리">수확/정리</option>
							<option value="후속작업">후속작업</option>
							<option value="기타">기타</option>
						</select>
					</div>
				</div>

				<div class="form-group">
					<label for="task-priority">우선순위</label>
					<select id="task-priority" bind:value={newPriority}>
						<option value="high">높음 (High)</option>
						<option value="medium">보통 (Medium)</option>
						<option value="low">낮음 (Low)</option>
					</select>
				</div>

				<div class="modal-actions">
					<button type="button" class="btn-secondary" onclick={closeNewTaskModal}>취소</button>
					<button type="submit" class="btn-primary">일정 추가</button>
				</div>
			</form>
		</div>
	</div>
{/if}

<style>
	.page-container {
		max-width: 1200px;
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

	h1 {
		margin: 8px 0;
		font-size: 2rem;
		color: #173d29;
	}

	.header-bar p {
		margin: 0;
		color: #5e7366;
		font-size: 0.94rem;
	}

	.btn-primary {
		padding: 12px 20px;
		border: none;
		border-radius: 12px;
		background: #25663b;
		color: #fff;
		font-weight: 700;
		cursor: pointer;
	}

	.control-panel {
		display: flex;
		justify-content: space-between;
		align-items: center;
		flex-wrap: wrap;
		gap: 16px;
		margin-bottom: 24px;
		padding: 14px 18px;
		background: #ffffff;
		border: 1px solid #dce5dc;
		border-radius: 16px;
	}

	.tasks-section {
		margin-bottom: 28px;
	}

	.section-heading {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: 16px;
		margin: 0 0 14px;
	}

	.section-heading h2 {
		margin: 2px 0 0;
		font-size: 1.25rem;
		color: #173d29;
	}

	.section-heading > strong {
		color: #25663b;
		font-size: 0.9rem;
	}

	.section-kicker {
		color: #697c70;
		font-size: 0.72rem;
		font-weight: 800;
	}

	.view-tabs {
		display: flex;
		gap: 8px;
	}

	.view-tabs button {
		padding: 8px 16px;
		border: none;
		border-radius: 10px;
		background: #f0f4f0;
		color: #4b6152;
		font-size: 0.88rem;
		font-weight: 700;
		cursor: pointer;
	}

	.view-tabs button.active {
		background: #25663b;
		color: #ffffff;
	}

	.filter-group {
		display: flex;
		gap: 10px;
	}

	.filter-control {
		display: flex;
		align-items: center;
		gap: 6px;
	}

	.filter-control > span {
		color: #607468;
		font-size: 0.75rem;
	}

	.filter-group select {
		padding: 8px 12px;
		border: 1px solid #d2ded0;
		border-radius: 8px;
		font-size: 0.85rem;
	}

	.tasks-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
		gap: 20px;
		align-items: start;
	}

	.task-card {
		padding: 22px;
		border: 1px solid #dce5dc;
		border-radius: 16px;
		background: #ffffff;
		display: flex;
		flex-direction: column;
		justify-content: space-between;
		box-shadow: 0 4px 16px rgba(23, 61, 41, 0.03);
	}

	.task-card-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 12px;
	}

	.header-tags {
		display: flex;
		align-items: center;
		gap: 6px;
	}

	.cat-tag {
		font-size: 0.72rem;
		font-weight: 800;
		padding: 3px 8px;
		border-radius: 6px;
		background: #e4f2e1;
		color: #245b38;
	}

	.priority-tag {
		font-size: 0.7rem;
		font-weight: 700;
		padding: 2px 6px;
		border-radius: 4px;
	}

	.priority-tag.p-high { background: #fee2e2; color: #991b1b; }
	.priority-tag.p-medium { background: #fef3c7; color: #92400e; }
	.priority-tag.p-low { background: #f3f4f6; color: #4b5563; }

	.followup-badge {
		font-size: 0.7rem;
		font-weight: 800;
		color: #d97706;
		background: #fffbeb;
		padding: 2px 6px;
		border-radius: 4px;
		border: 1px solid #fef3c7;
	}

	.scheduled-date {
		font-size: 0.78rem;
		color: #728779;
	}

	.task-title {
		margin: 0 0 8px;
		font-size: 1.1rem;
		color: #173d29;
	}

	.task-desc {
		margin: 0 0 14px;
		font-size: 0.88rem;
		color: #596d61;
		line-height: 1.5;
	}

	.log-preview {
		margin-top: 10px;
		padding: 10px 12px;
		border-radius: 10px;
		font-size: 0.82rem;
	}

	.log-preview.action-completed { background: #f0fdf4; border: 1px solid #bbf7d0; color: #166534; }
	.log-preview.action-issue { background: #fef2f2; border: 1px solid #fecaca; color: #991b1b; }
	.log-preview.action-skipped { background: #fffbeb; border: 1px solid #fef3c7; color: #92400e; }

	.log-top {
		display: flex;
		justify-content: space-between;
		margin-bottom: 4px;
	}

	.issue-cat-tag {
		background: #991b1b;
		color: #fff;
		padding: 1px 6px;
		border-radius: 4px;
		font-size: 0.68rem;
	}

	.photo-thumbnail img {
		width: 100%;
		max-height: 140px;
		object-fit: cover;
		border-radius: 8px;
		margin-top: 8px;
	}

	.task-actions {
		display: flex;
		gap: 8px;
		margin-top: 18px;
		padding-top: 14px;
		border-top: 1px solid #edf2ed;
	}

	.btn-act {
		flex: 1;
		padding: 8px 10px;
		border: none;
		border-radius: 8px;
		font-size: 0.78rem;
		font-weight: 700;
		cursor: pointer;
	}

	.btn-complete { background: #dcfce7; color: #15803d; }
	.btn-issue { background: #fee2e2; color: #b91c1c; }
	.btn-skip { background: #f3f4f6; color: #4b5563; }

	.status-pill {
		display: block;
		width: 100%;
		text-align: center;
		padding: 8px;
		border-radius: 8px;
		font-size: 0.85rem;
		font-weight: 700;
	}

	.status-pill.pill-completed { background: #dcfce7; color: #166534; }
	.status-pill.pill-issue { background: #fee2e2; color: #991b1b; }
	.status-pill.pill-skipped { background: #fef3c7; color: #92400e; }

	.empty-card {
		padding: 40px;
		text-align: center;
		background: #fff;
		border-radius: 16px;
		color: #728779;
	}

	/* Modal Styles */
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

	.modal-card {
		width: 100%;
		max-width: 560px;
		max-height: 90vh;
		overflow-y: auto;
		background: #ffffff;
		border-radius: 20px;
		padding: 28px;
	}

	.modal-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 20px;
	}

	.modal-header h3 { margin: 0; color: #173d29; }

	.btn-close { border: none; background: none; font-size: 1.5rem; cursor: pointer; }

	.modal-form { display: flex; flex-direction: column; gap: 16px; }

	.task-summary-box {
		padding: 12px;
		border-radius: 10px;
		background: #f0f7ef;
		font-size: 0.9rem;
		color: #173d29;
	}

	.form-group { display: flex; flex-direction: column; gap: 6px; }

	.form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }

	label { font-size: 0.82rem; font-weight: 700; color: #2b4534; }

	input, select, textarea {
		padding: 10px;
		border: 1px solid #d2ded0;
		border-radius: 10px;
		font-size: 0.9rem;
		font-family: inherit;
	}

	.sample-photos-box {
		margin-top: 6px;
	}

	.sample-btn-group {
		display: flex;
		gap: 6px;
		flex-wrap: wrap;
		margin-top: 4px;
	}

	.btn-sample {
		padding: 4px 8px;
		border: 1px solid #d2ded0;
		border-radius: 6px;
		background: #f8faf8;
		font-size: 0.74rem;
		cursor: pointer;
	}

	.photo-preview-box {
		position: relative;
		margin-top: 8px;
	}

	.photo-preview-box img {
		width: 100%;
		max-height: 180px;
		object-fit: cover;
		border-radius: 10px;
	}

	.btn-clear-photo {
		position: absolute;
		top: 8px;
		right: 8px;
		background: rgba(0, 0, 0, 0.7);
		color: #fff;
		border: none;
		padding: 4px 8px;
		border-radius: 4px;
		font-size: 0.72rem;
		cursor: pointer;
	}

	.followup-creation-box {
		padding: 16px;
		border: 1px solid #fde68a;
		border-radius: 12px;
		background: #fffbeb;
	}

	.checkbox-label {
		display: flex;
		align-items: center;
		gap: 8px;
		cursor: pointer;
	}

	.followup-fields {
		margin-top: 12px;
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	.modal-actions { display: flex; justify-content: flex-end; gap: 12px; margin-top: 10px; }

	.btn-secondary {
		padding: 10px 18px;
		border: 1px solid #d2ded0;
		border-radius: 10px;
		background: #f4f8f4;
		color: #3b5243;
		font-weight: 600;
		cursor: pointer;
	}

	@media (max-width: 640px) {
		.page-container {
			padding: 28px 16px 48px;
		}

		.header-bar {
			align-items: stretch;
			margin-bottom: 18px;
		}

		h1 {
			font-size: 1.55rem;
			line-height: 1.35;
		}

		.header-bar p {
			line-height: 1.55;
		}

		.header-bar .btn-primary {
			width: 100%;
		}

		.control-panel {
			align-items: stretch;
			padding: 12px;
			border-radius: 8px;
		}

		.view-tabs,
		.filter-group {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			width: 100%;
		}

		.view-tabs button {
			padding: 9px 4px;
			font-size: 0.78rem;
		}

		.filter-group {
			grid-template-columns: 1fr 1fr;
		}

		.filter-control {
			align-items: stretch;
			flex-direction: column;
		}

		.filter-group select {
			width: 100%;
		}

		.tasks-grid {
			grid-template-columns: minmax(0, 1fr);
			gap: 14px;
		}

		.task-card {
			padding: 16px;
			border-radius: 8px;
		}

		.task-card-header {
			align-items: flex-start;
			flex-direction: column;
			gap: 8px;
		}

		.task-actions {
			display: grid;
			grid-template-columns: 1fr 1fr;
		}

		.btn-skip {
			grid-column: 1 / -1;
		}

		.btn-act {
			min-height: 44px;
		}

		.modal-backdrop {
			align-items: flex-end;
			padding: 0;
		}

		.modal-card {
			max-height: 92vh;
			padding: 22px 18px;
			border-radius: 8px 8px 0 0;
		}

		.form-row {
			grid-template-columns: 1fr;
		}
	}
</style>
