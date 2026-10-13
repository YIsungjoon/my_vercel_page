<script lang="ts">
	import { farmStore } from '$lib/farmStore.svelte';
	import type { FarmAdminSummary, IssueCategory } from '$lib/types';

	let adminSummaries = $derived(farmStore.getAdminSummaries());

	let totalFarms = $derived(adminSummaries.length);
	let totalPending = $derived(adminSummaries.reduce((sum, s) => sum + s.pending_count, 0));
	let totalIssues = $derived(adminSummaries.reduce((sum, s) => sum + s.issue_count, 0));
	let highRiskFarms = $derived(adminSummaries.filter((s) => s.risk_level === 'danger' || s.risk_level === 'warning').length);

	// Risk level filter
	let riskFilter = $state<'all' | 'warning_danger' | 'normal'>('all');

	const filteredSummaries = $derived.by(() => {
		if (riskFilter === 'warning_danger') {
			return adminSummaries.filter((s) => s.risk_level === 'danger' || s.risk_level === 'warning');
		}
		if (riskFilter === 'normal') {
			return adminSummaries.filter((s) => s.risk_level === 'normal');
		}
		return adminSummaries;
	});

	// Assign Followup Task Modal from Admin
	let selectedSummaryForAction = $state<FarmAdminSummary | null>(null);
	let urgentTaskTitle = $state('');
	let urgentTaskCategory = $state<'관수/시비' | '환경관리' | '병해충방제' | '후속작업'>('후속작업');

	function openUrgentTaskModal(summary: FarmAdminSummary) {
		selectedSummaryForAction = summary;
		urgentTaskTitle = `[관리자 지시] ${summary.farm.name} 반복 문제 긴급 점검 및 방제`;
	}

	function handleAssignUrgentTask(e: SubmitEvent) {
		e.preventDefault();
		if (!selectedSummaryForAction || !urgentTaskTitle) return;

		farmStore.addTask({
			farm_id: selectedSummaryForAction.farm.id,
			title: urgentTaskTitle,
			description: '통합 관리자 모니터링 화면에서 할당된 긴급 지도/후속 작업입니다.',
			scheduled_date: new Date().toISOString().slice(0, 10),
			category: urgentTaskCategory,
			priority: 'high',
			is_followup: true
		});

		alert(`${selectedSummaryForAction.farm.name}에 긴급 작업이 성공적으로 등록되었습니다.`);
		selectedSummaryForAction = null;
	}
</script>

<svelte:head>
	<title>농가 통합 관리자 대시보드 | Dreaming Agri</title>
</svelte:head>

<main class="page-container">
	<header class="header-bar">
		<div>
			<span class="admin-badge">ADMIN DASHBOARD</span>
			<h1>농가별 미완료 작업 & 반복 문제 통제 모니터링</h1>
			<p>전체 농가의 미이행 작업 현황과 반복되는 이상·병해충 발생 패턴을 한눈에 파악하고 긴급 지시를 전달합니다.</p>
		</div>
	</header>

	<!-- Executive Metrics Bar -->
	<section class="metrics-grid">
		<div class="metric-card">
			<small>등록 농가 총수</small>
			<strong>{totalFarms} <span class="unit">개소</span></strong>
		</div>
		<div class="metric-card warning-metric">
			<small>미완료 작업 총 건수</small>
			<strong>{totalPending} <span class="unit">건</span></strong>
		</div>
		<div class="metric-card danger-metric">
			<small>문제 발생 기록 건수</small>
			<strong>{totalIssues} <span class="unit">건</span></strong>
		</div>
		<div class="metric-card alert-metric">
			<small>집중 관리 필요 농가</small>
			<strong>{highRiskFarms} <span class="unit">농가</span></strong>
		</div>
	</section>

	<!-- Filter Tabs -->
	<div class="filter-tabs">
		<button class:active={riskFilter === 'all'} onclick={() => (riskFilter = 'all')}>
			전체 농가 ({totalFarms})
		</button>
		<button class:active={riskFilter === 'warning_danger'} onclick={() => (riskFilter = 'warning_danger')}>
			⚠️ 집중 관리 대상 ({highRiskFarms})
		</button>
		<button class:active={riskFilter === 'normal'} onclick={() => (riskFilter = 'normal')}>
			✓ 정상 운영 ({totalFarms - highRiskFarms})
		</button>
	</div>

	<!-- Farm Admin List Cards -->
	<section class="admin-list">
		{#each filteredSummaries as s}
			<article class={`admin-farm-card risk-${s.risk_level}`}>
				<div class="farm-top-info">
					<div class="farm-title-group">
						<span class="crop-tag">{s.farm.crop}</span>
						<h2>{s.farm.name}</h2>
						<span class="region-text">📍 {s.farm.region}</span>
					</div>
					<div class="risk-badge-box">
						{#if s.risk_level === 'danger'}
							<span class="risk-badge risk-danger">🚨 위험 (즉시 점검 필요)</span>
						{:else if s.risk_level === 'warning'}
							<span class="risk-badge risk-warning">⚠️ 주의 (이슈/미완료 누적)</span>
						{:else}
							<span class="risk-badge risk-normal">✓ 정상 (관리에이전트 이행중)</span>
						{/if}
					</div>
				</div>

				<div class="status-summary-grid">
					<div class="stat-box">
						<span class="stat-label">미완료 작업</span>
						<strong class={s.pending_count > 0 ? 'text-warn' : ''}>{s.pending_count} 건</strong>
					</div>
					<div class="stat-box">
						<span class="stat-label">이행 완료</span>
						<strong>{s.completed_count} 건</strong>
					</div>
					<div class="stat-box">
						<span class="stat-label">문제/이상 발생</span>
						<strong class={s.issue_count > 0 ? 'text-danger' : ''}>{s.issue_count} 건</strong>
					</div>
					<div class="stat-box">
						<span class="stat-label">품종 / 생육단계</span>
						<strong>{s.farm.variety} ({s.farm.growth_stage})</strong>
					</div>
				</div>

				<!-- Recurring Issues Breakdown -->
				<div class="issues-breakdown-box">
					<h4>🔁 반복 발생 문제 분류 및 빈도 현황</h4>
					{#if s.recurring_issues.length === 0}
						<p class="no-issues-text">최근 반복적으로 보고된 이상 발생 이슈가 없습니다.</p>
					{:else}
						<div class="issues-tags">
							{#each s.recurring_issues as issue}
								<div class="issue-pill">
									<span class="issue-name">🐛 {issue.category}</span>
									<span class="issue-count">{issue.count}회 감지</span>
								</div>
							{/each}
						</div>
					{/if}
				</div>

				<!-- Recent Activity Logs preview -->
				{#if s.recent_logs.length > 0}
					<div class="recent-logs-box">
						<small>최근 이슈 및 수행 일지:</small>
						<ul>
							{#each s.recent_logs as log}
								<li class={`log-type-${log.action}`}>
									<span class="log-date">{log.created_at.slice(0, 10)}</span>
									<strong>[{log.action === 'issue' ? '문제발생' : log.action === 'completed' ? '완료' : '연기'}]</strong>
									<span>{log.note}</span>
								</li>
							{/each}
						</ul>
					</div>
				{/if}

				<!-- Admin Action Footer -->
				<div class="admin-card-footer">
					<button
						type="button"
						class="btn-admin-action"
						onclick={() => openUrgentTaskModal(s)}
					>
						⚡ 관리자 긴급 후속 작업 할당
					</button>
				</div>
			</article>
		{/each}
	</section>
</main>

<!-- Urgent Task Assignment Modal -->
{#if selectedSummaryForAction}
	<div class="modal-backdrop" role="presentation" onkeydown={(event) => event.stopPropagation()} onclick={() => (selectedSummaryForAction = null)}>
		<div class="modal-card" role="dialog" aria-modal="true" tabindex="-1" onkeydown={(event) => event.stopPropagation()} onclick={(e) => e.stopPropagation()}>
			<div class="modal-header">
				<h3>⚡ 관리자 긴급 작업 할당</h3>
				<button type="button" class="btn-close" onclick={() => (selectedSummaryForAction = null)}>&times;</button>
			</div>

			<form onsubmit={handleAssignUrgentTask} class="modal-form">
				<div class="farm-info-banner">
					<strong>대상 농가:</strong> {selectedSummaryForAction.farm.name} ({selectedSummaryForAction.farm.crop})
				</div>

				<div class="form-group">
					<label for="urgent-title">지시 작업 제목 *</label>
					<input id="urgent-title" type="text" bind:value={urgentTaskTitle} required />
				</div>

				<div class="form-group">
					<label for="urgent-cat">작업 카테고리</label>
					<select id="urgent-cat" bind:value={urgentTaskCategory}>
						<option value="후속작업">후속작업</option>
						<option value="병해충방제">병해충방제</option>
						<option value="환경관리">환경관리</option>
						<option value="관수/시비">관수/시비</option>
					</select>
				</div>

				<div class="modal-actions">
					<button type="button" class="btn-secondary" onclick={() => (selectedSummaryForAction = null)}>취소</button>
					<button type="submit" class="btn-primary">긴급 작업 등록 발송</button>
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
		margin-bottom: 28px;
	}

	.admin-badge {
		display: inline-block;
		font-size: 0.72rem;
		font-weight: 800;
		letter-spacing: 0.14em;
		color: #991b1b;
		background: #fee2e2;
		padding: 4px 10px;
		border-radius: 6px;
	}

	h1 { margin: 8px 0; font-size: 2rem; color: #173d29; }

	.header-bar p { margin: 0; color: #5e7366; font-size: 0.94rem; }

	.metrics-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
		gap: 16px;
		margin-bottom: 28px;
	}

	.metric-card {
		padding: 20px;
		border-radius: 16px;
		background: #ffffff;
		border: 1px solid #dce5dc;
		box-shadow: 0 4px 16px rgba(23, 61, 41, 0.03);
	}

	.metric-card small { display: block; font-size: 0.78rem; color: #6a7f72; margin-bottom: 6px; }

	.metric-card strong { font-size: 2rem; color: #173d29; }

	.metric-card .unit { font-size: 1rem; font-weight: 600; color: #5e7366; }

	.warning-metric { border-color: #fde68a; background: #fffbeb; }
	.danger-metric { border-color: #fecaca; background: #fef2f2; }
	.alert-metric { border-color: #fed7aa; background: #fff7ed; }

	.filter-tabs {
		display: flex;
		gap: 10px;
		margin-bottom: 24px;
	}

	.filter-tabs button {
		padding: 10px 18px;
		border: 1px solid #d2ded0;
		border-radius: 12px;
		background: #ffffff;
		color: #4b6152;
		font-size: 0.88rem;
		font-weight: 700;
		cursor: pointer;
	}

	.filter-tabs button.active {
		background: #173d29;
		color: #ffffff;
		border-color: #173d29;
	}

	.admin-list {
		display: flex;
		flex-direction: column;
		gap: 24px;
	}

	.admin-farm-card {
		padding: 26px;
		border-radius: 20px;
		background: #ffffff;
		border: 1px solid #dce5dc;
		box-shadow: 0 8px 24px rgba(23, 61, 41, 0.04);
	}

	.admin-farm-card.risk-danger { border-left: 6px solid #dc2626; }
	.admin-farm-card.risk-warning { border-left: 6px solid #d97706; }
	.admin-farm-card.risk-normal { border-left: 6px solid #16a34a; }

	.farm-top-info {
		display: flex;
		justify-content: space-between;
		align-items: center;
		flex-wrap: wrap;
		gap: 14px;
		margin-bottom: 20px;
	}

	.farm-title-group {
		display: flex;
		align-items: center;
		gap: 12px;
	}

	.crop-tag {
		padding: 4px 8px;
		border-radius: 6px;
		background: #e4f2e1;
		color: #245b38;
		font-size: 0.8rem;
		font-weight: 800;
	}

	.farm-title-group h2 { margin: 0; font-size: 1.35rem; color: #173d29; }

	.region-text { font-size: 0.85rem; color: #6a7f72; }

	.risk-badge {
		padding: 6px 12px;
		border-radius: 999px;
		font-size: 0.78rem;
		font-weight: 800;
	}

	.risk-danger { background: #fee2e2; color: #991b1b; }
	.risk-warning { background: #fef3c7; color: #92400e; }
	.risk-normal { background: #dcfce7; color: #166534; }

	.status-summary-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
		gap: 12px;
		margin-bottom: 20px;
	}

	.stat-box {
		padding: 14px;
		border-radius: 12px;
		background: #f8faf8;
		border: 1px solid #e6eee4;
	}

	.stat-label { display: block; font-size: 0.74rem; color: #6a7f72; margin-bottom: 4px; }

	.stat-box strong { font-size: 1.05rem; color: #173d29; }

	.text-warn { color: #d97706; }
	.text-danger { color: #dc2626; }

	.issues-breakdown-box {
		padding: 16px;
		border-radius: 14px;
		background: #fcfdfc;
		border: 1px solid #e5eee4;
		margin-bottom: 16px;
	}

	.issues-breakdown-box h4 { margin: 0 0 10px; font-size: 0.9rem; color: #234832; }

	.no-issues-text { margin: 0; font-size: 0.84rem; color: #788c80; }

	.issues-tags { display: flex; gap: 10px; flex-wrap: wrap; }

	.issue-pill {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 12px;
		border-radius: 8px;
		background: #fef2f2;
		border: 1px solid #fecaca;
		font-size: 0.82rem;
	}

	.issue-name { font-weight: 700; color: #991b1b; }
	.issue-count { font-weight: 800; color: #dc2626; background: #ffffff; padding: 2px 6px; border-radius: 4px; }

	.recent-logs-box {
		margin-bottom: 16px;
		padding: 12px 14px;
		border-radius: 10px;
		background: #f4f8f4;
		font-size: 0.84rem;
	}

	.recent-logs-box ul { margin: 6px 0 0; padding-left: 18px; color: #43594b; }

	.admin-card-footer {
		display: flex;
		justify-content: flex-end;
		padding-top: 14px;
		border-top: 1px solid #edf2ed;
	}

	.btn-admin-action {
		padding: 10px 18px;
		border: none;
		border-radius: 10px;
		background: #173d29;
		color: #ffffff;
		font-weight: 700;
		font-size: 0.85rem;
		cursor: pointer;
	}

	/* Modal */
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
		max-width: 500px;
		background: #ffffff;
		border-radius: 20px;
		padding: 28px;
	}

	.modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; }

	.btn-close { border: none; background: none; font-size: 1.5rem; cursor: pointer; }

	.modal-form { display: flex; flex-direction: column; gap: 16px; }

	.farm-info-banner {
		padding: 12px;
		border-radius: 10px;
		background: #e4f2e1;
		color: #173d29;
		font-size: 0.9rem;
	}

	.form-group { display: flex; flex-direction: column; gap: 6px; }

	label { font-size: 0.82rem; font-weight: 700; color: #2b4534; }

	input, select {
		padding: 10px;
		border: 1px solid #d2ded0;
		border-radius: 10px;
		font-size: 0.9rem;
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
