<script lang="ts">
	import { farmStore } from '$lib/farmStore.svelte';
	import { SOLAR_TERMS, getSolarTermForDate, type SolarTermInfo } from '$lib/solarTerms';
	import type { Task, TaskCategory } from '$lib/types';

	let { onSelectDate, onOpenAddTask }: { onSelectDate?: (dateStr: string) => void; onOpenAddTask?: (dateStr: string) => void } = $props();

	let currentDate = $state(new Date());
	let calendarMode = $state<'month' | 'week'>('month');

	const year = $derived(currentDate.getFullYear());
	const month = $derived(currentDate.getMonth() + 1); // 1~12

	// Calculate current month's calendar grid days
	const calendarDays = $derived.by(() => {
		const firstDayOfMonth = new Date(year, month - 1, 1);
		const lastDayOfMonth = new Date(year, month, 0);
		
		const startingDayOfWeek = firstDayOfMonth.getDay(); // 0 = Sun
		const totalDaysInMonth = lastDayOfMonth.getDate();

		const days: { dateStr: string; dayNum: number; isCurrentMonth: boolean; solarTerm: SolarTermInfo | null }[] = [];

		// Previous month trailing days
		const prevMonthLastDay = new Date(year, month - 1, 0).getDate();
		for (let i = startingDayOfWeek - 1; i >= 0; i--) {
			const pDay = prevMonthLastDay - i;
			const pMonth = month - 1 < 1 ? 12 : month - 1;
			const pYear = month - 1 < 1 ? year - 1 : year;
			const dateStr = `${pYear}-${String(pMonth).padStart(2, '0')}-${String(pDay).padStart(2, '0')}`;
			days.push({
				dateStr,
				dayNum: pDay,
				isCurrentMonth: false,
				solarTerm: getSolarTermForDate(dateStr)
			});
		}

		// Current month days
		for (let d = 1; d <= totalDaysInMonth; d++) {
			const dateStr = `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
			days.push({
				dateStr,
				dayNum: d,
				isCurrentMonth: true,
				solarTerm: getSolarTermForDate(dateStr)
			});
		}

		// Next month leading days
		const remainingCells = 42 - days.length; // 6 rows * 7 days
		for (let n = 1; n <= remainingCells; n++) {
			const nMonth = month + 1 > 12 ? 1 : month + 1;
			const nYear = month + 1 > 12 ? year + 1 : year;
			const dateStr = `${nYear}-${String(nMonth).padStart(2, '0')}-${String(n.toString()).padStart(2, '0')}`;
			days.push({
				dateStr,
				dayNum: n,
				isCurrentMonth: false,
				solarTerm: getSolarTermForDate(dateStr)
			});
		}

		return days;
	});

	// Get active solar term for current month
	const currentSolarTerms = $derived(SOLAR_TERMS.filter((t) => t.month === month));

	function prevMonth() {
		currentDate = new Date(year, month - 2, 1);
	}

	function nextMonth() {
		currentDate = new Date(year, month, 1);
	}

	function goToday() {
		currentDate = new Date();
	}

	const todayStr = new Date().toISOString().slice(0, 10);
</script>

<section class="farming-calendar-wrapper">
	<!-- Calendar Header Controls -->
	<div class="calendar-top-bar">
		<div class="month-title-group">
			<button type="button" class="btn-nav" aria-label="이전 달" title="이전 달" onclick={prevMonth}>‹</button>
			<h2>{year}년 {month}월 전통 농사 달력</h2>
			<button type="button" class="btn-nav" aria-label="다음 달" title="다음 달" onclick={nextMonth}>›</button>
			<button type="button" class="btn-today" onclick={goToday}>오늘 ({todayStr})</button>
		</div>

		<div class="mode-toggle-group">
			<button aria-pressed={calendarMode === 'month'} class:active={calendarMode === 'month'} onclick={() => (calendarMode = 'month')}>
				월간 달력
			</button>
			<button aria-pressed={calendarMode === 'week'} class:active={calendarMode === 'week'} onclick={() => (calendarMode = 'week')}>
				주간 타임라인
			</button>
		</div>
	</div>

	<!-- 24 Solar Terms Insight Banner -->
	{#if currentSolarTerms.length > 0}
		<div class="solar-terms-banner">
			<span class="banner-title">🎋 {month}월 전통 24절기 영농 지침:</span>
			<div class="terms-chips">
				{#each currentSolarTerms as term}
					<div class="term-chip">
						<strong>{term.icon} {term.name}({term.nameHanja}) - 약 {term.approxDay}일</strong>
						<p>{term.farmingAdvice}</p>
					</div>
				{/each}
			</div>
		</div>
	{/if}

	{#if calendarMode === 'month'}
		<!-- Monthly Grid View -->
		<div class="calendar-grid">
			<div class="day-name col-sun">일</div>
			<div class="day-name">월</div>
			<div class="day-name">화</div>
			<div class="day-name">수</div>
			<div class="day-name">목</div>
			<div class="day-name">금</div>
			<div class="day-name col-sat">토</div>

			{#each calendarDays as day}
				{@const dayTasks = farmStore.currentFarmTasks.filter((t) => t.scheduled_date === day.dateStr)}
				<div
					class="calendar-cell"
					class:other-month={!day.isCurrentMonth}
					class:is-today={day.dateStr === todayStr}
				>
					<div class="cell-top">
						<span class="day-number">{day.dayNum}</span>
						{#if day.solarTerm}
							<span class="solar-term-badge">
								{day.solarTerm.icon} {day.solarTerm.name}
							</span>
						{/if}
						<button
							type="button"
							class="btn-add-quick"
							aria-label={`${day.dateStr}에 작업 등록`}
							title={`${day.dateStr}에 작업 등록`}
							onclick={() => onOpenAddTask?.(day.dateStr)}
						>
							+
						</button>
					</div>

					<!-- Tasks in Cell -->
					<div class="cell-tasks-list">
						{#each dayTasks.slice(0, 3) as task}
							<div class={`mini-task-pill status-${task.status}`}>
								{#if task.is_followup}
									<span class="icon-f">⚡</span>
								{/if}
								<span class="task-title-text">{task.title}</span>
							</div>
						{/each}
						{#if dayTasks.length > 3}
							<span class="more-count">+{dayTasks.length - 3}개 더보기</span>
						{/if}
					</div>
				</div>
			{/each}
		</div>
	{:else}
		<!-- Weekly Timeline View -->
		<div class="weekly-timeline-box">
			<h3>📅 주간 핵심 영농 일정 타임라인</h3>
			<div class="weekly-cards-grid">
				{#each farmStore.weeklyTasks as task}
					<div class={`timeline-task-card status-${task.status}`}>
						<div class="timeline-top">
							<span class="date-badge">📅 {task.scheduled_date}</span>
							<span class="cat-badge">{task.category}</span>
							{#if task.is_followup}
								<span class="followup-badge">⚡ 후속작업</span>
							{/if}
						</div>
						<h4>{task.title}</h4>
						{#if task.description}
							<p>{task.description}</p>
						{/if}
						<div class="timeline-bottom">
							<span class={`status-pill status-${task.status}`}>
								{task.status === 'completed' ? '✓ 완료' : task.status === 'issue' ? '⚠️ 문제발생' : '대기중'}
							</span>
						</div>
					</div>
				{/each}
			</div>
		</div>
	{/if}
</section>

<style>
	.farming-calendar-wrapper {
		margin-bottom: 28px;
		background: #ffffff;
		border: 1px solid #dce5dc;
		border-radius: 20px;
		padding: 24px;
		box-shadow: 0 8px 24px rgba(23, 61, 41, 0.04);
	}

	.calendar-top-bar {
		display: flex;
		justify-content: space-between;
		align-items: center;
		flex-wrap: wrap;
		gap: 16px;
		margin-bottom: 20px;
	}

	.month-title-group {
		display: flex;
		align-items: center;
		gap: 12px;
	}

	.month-title-group h2 {
		margin: 0;
		font-size: 1.4rem;
		color: #173d29;
	}

	.btn-nav {
		display: inline-grid;
		width: 36px;
		height: 36px;
		padding: 0;
		place-items: center;
		border: 1px solid #d2ded0;
		border-radius: 8px;
		background: #f6faf6;
		color: #173d29;
		font-weight: 700;
		font-size: 1.25rem;
		cursor: pointer;
	}

	.btn-today {
		padding: 6px 12px;
		border: 1px solid #25663b;
		border-radius: 8px;
		background: #e4f2e1;
		color: #1c522e;
		font-size: 0.82rem;
		font-weight: 700;
		cursor: pointer;
	}

	.mode-toggle-group button {
		padding: 8px 14px;
		border: 1px solid #d2ded0;
		border-radius: 10px;
		background: #ffffff;
		color: #4b6152;
		font-size: 0.85rem;
		font-weight: 700;
		cursor: pointer;
	}

	.mode-toggle-group button.active {
		background: #173d29;
		color: #ffffff;
		border-color: #173d29;
	}

	.solar-terms-banner {
		padding: 14px 18px;
		border-radius: 14px;
		background: linear-gradient(135deg, #f0f7ef 0%, #e2f0e0 100%);
		border: 1px solid #cde0ca;
		margin-bottom: 20px;
	}

	.banner-title {
		font-size: 0.85rem;
		font-weight: 800;
		color: #1c522e;
		display: block;
		margin-bottom: 8px;
	}

	.terms-chips {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(280px, 100%), 1fr));
		gap: 10px;
	}

	.term-chip {
		min-width: 0;
		padding: 10px 14px;
		border-radius: 10px;
		background: #ffffff;
		border: 1px solid #d2ded0;
	}

	.term-chip strong {
		font-size: 0.88rem;
		color: #164228;
	}

	.term-chip p {
		margin: 4px 0 0;
		font-size: 0.78rem;
		color: #556c5e;
		line-height: 1.4;
	}

	/* Monthly Calendar Grid with Fixed Cell Dimensions */
	.calendar-grid {
		display: grid;
		grid-template-columns: repeat(7, minmax(0, 1fr));
		border-top: 1px solid #e1ebe0;
		border-left: 1px solid #e1ebe0;
	}

	.day-name {
		padding: 10px 4px;
		text-align: center;
		font-size: 0.82rem;
		font-weight: 800;
		color: #2b4534;
		background: #f4f8f4;
		border-right: 1px solid #e1ebe0;
		border-bottom: 1px solid #e1ebe0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.col-sun { color: #dc2626; }
	.col-sat { color: #2563eb; }

	.calendar-cell {
		box-sizing: border-box;
		height: 115px; /* Strictly fixed height for all calendar cells */
		padding: 6px 8px;
		border-right: 1px solid #e1ebe0;
		border-bottom: 1px solid #e1ebe0;
		background: #ffffff;
		position: relative;
		display: flex;
		flex-direction: column;
		overflow: hidden;
	}

	.calendar-cell.other-month {
		background: #fafcf9;
		opacity: 0.55;
	}

	.calendar-cell.is-today {
		background: #f0fdf4;
		box-shadow: inset 0 0 0 2px #25663b;
	}

	.cell-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 4px;
		flex-shrink: 0;
	}

	.day-number {
		font-size: 0.86rem;
		font-weight: 750;
		color: #173d29;
	}

	.solar-term-badge {
		font-size: 0.65rem;
		font-weight: 800;
		color: #15803d;
		background: #dcfce7;
		padding: 1px 5px;
		border-radius: 4px;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 70px;
	}

	.btn-add-quick {
		display: none;
		padding: 0 6px;
		border: 1px solid #cde0ca;
		border-radius: 4px;
		background: #ffffff;
		font-size: 0.8rem;
		cursor: pointer;
	}

	.calendar-cell:hover .btn-add-quick {
		display: inline-block;
	}

	.calendar-cell:focus-within .btn-add-quick {
		display: inline-grid;
	}

	@media (pointer: coarse) {
		.btn-add-quick {
			display: inline-grid;
			place-items: center;
		}
	}

	.cell-tasks-list {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 3px;
		overflow-y: auto;
		scrollbar-width: thin;
	}

	.mini-task-pill {
		padding: 3px 6px;
		border-radius: 4px;
		font-size: 0.72rem;
		font-weight: 650;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.mini-task-pill.status-completed { background: #dcfce7; color: #166534; }
	.mini-task-pill.status-issue { background: #fee2e2; color: #991b1b; }
	.mini-task-pill.status-pending { background: #fef3c7; color: #92400e; }

	.icon-f { color: #d97706; margin-right: 2px; }

	.more-count {
		font-size: 0.68rem;
		color: #6a7f72;
		font-weight: 700;
	}

	/* Weekly Timeline */
	.weekly-timeline-box h3 { margin-top: 0; color: #173d29; }

	.weekly-cards-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
		gap: 14px;
	}

	.timeline-task-card {
		padding: 16px;
		border-radius: 12px;
		background: #f8faf8;
		border: 1px solid #e1ebe0;
	}

	.timeline-top {
		display: flex;
		gap: 6px;
		margin-bottom: 8px;
	}

	.date-badge { font-size: 0.74rem; color: #5a7063; font-weight: 700; }
	.cat-badge { font-size: 0.72rem; padding: 2px 6px; border-radius: 4px; background: #e4f2e1; color: #245b38; font-weight: 800; }
	.followup-badge { font-size: 0.72rem; padding: 2px 6px; border-radius: 4px; background: #fffbeb; color: #d97706; font-weight: 800; }

	.timeline-task-card h4 { margin: 0 0 4px; font-size: 0.98rem; color: #173d29; }
	.timeline-task-card p { margin: 0 0 10px; font-size: 0.82rem; color: #5d7366; }

	.status-pill { font-size: 0.74rem; font-weight: 700; padding: 2px 8px; border-radius: 6px; }
	.status-pill.status-completed { background: #dcfce7; color: #166534; }
	.status-pill.status-issue { background: #fee2e2; color: #991b1b; }
	.status-pill.status-pending { background: #fef3c7; color: #92400e; }

	@media (max-width: 768px) {
		.farming-calendar-wrapper {
			padding: 16px;
			border-radius: 8px;
		}

		.calendar-top-bar,
		.month-title-group {
			align-items: stretch;
		}

		.month-title-group {
			display: grid;
			grid-template-columns: 36px minmax(0, 1fr) 36px;
			width: 100%;
		}

		.month-title-group h2 {
			align-self: center;
			font-size: 1.05rem;
			text-align: center;
		}

		.btn-today {
			grid-column: 1 / -1;
		}

		.mode-toggle-group {
			display: grid;
			grid-template-columns: 1fr 1fr;
			width: 100%;
		}

		.calendar-grid {
			font-size: 0.75rem;
		}
		.calendar-cell {
			height: 82px;
			padding: 4px;
		}

		.solar-term-badge {
			display: none;
		}

		.btn-add-quick {
			display: inline-grid;
			width: 24px;
			height: 24px;
			padding: 0;
			place-items: center;
		}

		.mini-task-pill {
			padding: 2px 3px;
			font-size: 0.64rem;
		}
	}
</style>
