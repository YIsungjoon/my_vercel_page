<script lang="ts">
 import { appPath, loginPath } from '$agri/paths';
	import type { load } from './+page.server';
	type PageData = Awaited<ReturnType<typeof load>>;
	import { farmStore } from '$agri/farmStore.svelte';
	import WeatherPestWidget from '$agri/components/WeatherPestWidget.svelte';
	import { fetchAgriculturalWeather, type WeatherInfo } from '$agri/services/agriApiService';
	import type { GrowthStage } from '$agri/types';

	let { data }: { data: PageData } = $props();

	let realTimeWeather = $state<WeatherInfo | null>(null);
	let serverHydrated = $state(false);

	$effect(() => {
		if (!serverHydrated && data.farms?.length) {
			farmStore.hydrateFromServer(data.farms, data.tasks ?? []);
			serverHydrated = true;
		}
	});

	$effect(() => {
		const region = farmStore.currentFarm.region;
		fetchAgriculturalWeather(region).then((res) => {
			realTimeWeather = res;
		});

		const timer = setInterval(() => {
			fetchAgriculturalWeather(region).then((res) => {
				realTimeWeather = res;
			});
		}, 3600000);

		return () => clearInterval(timer);
	});

	// Modal & Form State for Farm Registration
	let showRegModal = $state(false);
	let newName = $state('');
	let newRegion = $state('전북특별자치도 김제시');
	let newCrop = $state('토마토');
	let newVariety = $state('');
	let newPlantedAt = $state(new Date().toISOString().slice(0, 10));
	let newGrowthStage = $state<GrowthStage>('영양생장기');
	let newNotes = $state('');

	const weatherLabels: Record<number, string> = {
		0: '맑음', 1: '대체로 맑음', 2: '부분적으로 흐림', 3: '흐림',
		45: '안개', 48: '서리 안개', 51: '약한 이슬비', 53: '이슬비', 55: '강한 이슬비',
		61: '약한 비', 63: '비', 65: '강한 비', 80: '약한 소나기', 81: '소나기', 82: '강한 소나기', 95: '뇌우'
	};

	async function handleRegisterFarm(e: SubmitEvent) {
		e.preventDefault();
		if (!newName || !newCrop || !newVariety) {
			alert('Farm name, crop, and variety are required.');
			return;
		}

		const response = await fetch(appPath('/api/farms'), {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				name: newName,
				region: newRegion,
				crop: newCrop,
				variety: newVariety,
				planted_at: newPlantedAt,
				growth_stage: newGrowthStage,
				notes: newNotes
			})
		});

		if (response.status === 401) {
			window.location.assign(loginPath('/'));
			return;
		}

		const result = await response.json().catch(() => ({}));
		if (!response.ok) {
			alert(result.error || 'Farm registration failed.');
			return;
		}

		if (result.farm && result.cycle) {
			farmStore.addPersistedFarm({
				id: result.farm.id,
				name: result.farm.name,
				region: result.farm.region,
				crop: result.cycle.crop,
				variety: result.cycle.variety,
				planted_at: result.cycle.planted_at,
				growth_stage: result.cycle.growth_stage as GrowthStage,
				notes: result.cycle.notes ?? undefined,
				created_at: result.farm.created_at
			});
		}

		// Reset form
		newName = '';
		newVariety = '';
		newNotes = '';
		showRegModal = false;
	}

	const growthStageBadges: Record<GrowthStage, string> = {
		'육묘기': 'stage-seedling',
		'영양생장기': 'stage-vegetative',
		'생식생장기': 'stage-reproductive',
		'수확기': 'stage-harvest',
		'수확후정리': 'stage-post'
	};
</script>

<svelte:head>
	<title>농장 현황 & 등록 | Dreaming Agri</title>
</svelte:head>

<main class="page-container">
	<header class="hero-header">
		<div class="header-top">
			<div>
				<span class="badge">MVP core</span>
				<h1>농장·작물 현황 및 생육 단계</h1>
				<p>가상·실제 환경데이터와 작업 기록을 기반으로 예측형 농장 운영을 시작합니다.</p>
			</div>
			<button type="button" class="btn-primary" onclick={() => (showRegModal = true)}>
				<svg viewBox="0 0 24 24" class="icon"><path fill="none" stroke="currentColor" stroke-width="2" d="M12 5v14m-7-7h14"/></svg>
				신규 농장 등록
			</button>
		</div>
	</header>

	<!-- Current Active Farm Banner & Details -->
	<section class="card active-farm-card">
		<div class="farm-header-row">
			<div class="farm-title">
				<span class="crop-badge">{farmStore.currentFarm.crop}</span>
				<h2>{farmStore.currentFarm.name}</h2>
				<span class={`stage-pill ${growthStageBadges[farmStore.currentFarm.growth_stage]}`}>
					{farmStore.currentFarm.growth_stage}
				</span>
			</div>
			<div class="farm-meta">
				<span>📍 {farmStore.currentFarm.region}</span>
			</div>
		</div>

		<div class="farm-details-grid">
			<div class="detail-box">
				<small>재배 작물 / 품종</small>
				<strong>{farmStore.currentFarm.crop} ({farmStore.currentFarm.variety})</strong>
			</div>
			<div class="detail-box">
				<small>정식일 (Planting Date)</small>
				<strong>{farmStore.currentFarm.planted_at}</strong>
			</div>
			<div class="detail-box">
				<small>현재 생육 단계</small>
				<strong class="highlight">{farmStore.currentFarm.growth_stage}</strong>
			</div>
			<div class="detail-box">
				<small>오늘의 대기 작업</small>
				<strong>{farmStore.todayTasks.filter(t => t.status === 'pending').length} 건</strong>
			</div>
		</div>

		{#if farmStore.currentFarm.notes}
			<div class="farm-notes">
				<strong>📝 메모 & 온실 환경</strong>
				<p>{farmStore.currentFarm.notes}</p>
			</div>
		{/if}
	</section>

	<!-- Real-time Agricultural Weather & NIFS/RDA Pest & Disease Warning Widget -->
	<WeatherPestWidget />

	<!-- Concise Market & Weather Quick Insight Banner -->
	<div class="market-quick-banner">
		<div class="banner-info">
			<span class="badge-quick">📊 실시간 농업 분석 요약</span>
			<h4>{farmStore.currentFarm.name} 기상 특보 & {farmStore.currentFarm.crop} 도매시세</h4>
			<div class="quick-stats-row">
				<span>🌤️ <strong>관측 기온:</strong> {realTimeWeather ? `${realTimeWeather.temperature}°C (습도 ${realTimeWeather.humidity}%)` : '수집 중...'}</span>
				<span>💰 <strong>{farmStore.currentFarm.crop} 도매가:</strong> 최근 상승세 (전국 평균 34,500원)</span>
			</div>
		</div>
		<a href={appPath('/market')} class="btn-goto-market">
			도매시세 & 상세 기상 분석 보러가기 &rarr;
		</a>
	</div>

	<!-- Today's Quick Tasks Overview -->
	<div class="two-col-grid">
		<section class="card">
			<div class="card-header">
				<h3>📅 오늘의 작업 요약</h3>
				<a href={appPath('/tasks')} class="link-more">전체 일정 보기 &rarr;</a>
			</div>
			{#if farmStore.todayTasks.length === 0}
				<p class="empty-text">오늘 예정된 작업이 없습니다.</p>
			{:else}
				<ul class="quick-task-list">
					{#each farmStore.todayTasks as task}
						<li class={`task-item status-${task.status}`}>
							<div class="task-info">
								<span class="cat-tag">{task.category}</span>
								<strong>{task.title}</strong>
								{#if task.is_followup}
									<span class="followup-tag">[후속작업]</span>
								{/if}
							</div>
							<span class={`status-badge ${task.status}`}>
								{task.status === 'completed' ? '완료' : task.status === 'issue' ? '문제발생' : '대기중'}
							</span>
						</li>
					{/each}
				</ul>
			{/if}
		</section>

		<!-- Weather Information Section -->
		<section class="card weather-card">
			<div class="card-header">
				<span class="weather-eyebrow">REAL-TIME FARM WEATHER</span>
				<h3>실시간 농가 기상 관측</h3>
				<span class="region-sub-tag">📍 {farmStore.currentFarm.region}</span>
			</div>
			{#if realTimeWeather}
				<div class="weather-content">
					<div class="weather-temp">
						<strong>{realTimeWeather.temperature}°C</strong>
						<span>{realTimeWeather.skyCondition === 'sunny' ? '☀️ 맑음' : '☁️ 구름 많음'}</span>
					</div>
					<div class="weather-metrics">
						<div>
							<small>상대습도</small>
							<strong>{realTimeWeather.humidity}%</strong>
						</div>
						<div>
							<small>강수확률</small>
							<strong>{realTimeWeather.precipitationProbability}%</strong>
						</div>
						<div>
							<small>기상 상태</small>
							<strong class={realTimeWeather.warningType !== 'none' ? 'warn-text' : 'normal-text'}>
								{realTimeWeather.warningType !== 'none' ? '주의보 발생' : '정상 관측'}
							</strong>
						</div>
					</div>
				</div>
			{:else}
				<div class="weather-placeholder">
					<p>해당 농가 지리 실시간 기상을 관측 중입니다...</p>
				</div>
			{/if}
		</section>
	</div>

	<!-- Registered Farms List -->
	<section class="card">
		<div class="card-header">
			<h3>🏡 등록된 전체 농장 목록 ({farmStore.farms.length}개)</h3>
		</div>
		<div class="farms-grid">
			{#each farmStore.farms as farm}
				<div
					class="farm-mini-card"
					class:selected={farm.id === farmStore.selectedFarmId}
					role="button"
					tabindex="0"
					onclick={() => farmStore.selectFarm(farm.id)}
					onkeydown={(e) => e.key === 'Enter' && farmStore.selectFarm(farm.id)}
				>
					<div class="mini-header">
						<span class="mini-crop">{farm.crop}</span>
						<h4>{farm.name}</h4>
					</div>
					<p class="mini-region">📍 {farm.region}</p>
					<div class="mini-footer">
						<span>품종: {farm.variety}</span>
						<span class="stage-tag">{farm.growth_stage}</span>
					</div>
				</div>
			{/each}
		</div>
	</section>
</main>

<!-- Farm Registration Modal -->
{#if showRegModal}
	<div class="modal-backdrop" role="presentation" onkeydown={(event) => event.stopPropagation()} onclick={() => (showRegModal = false)}>
		<div class="modal-card" role="dialog" aria-modal="true" tabindex="-1" onkeydown={(event) => event.stopPropagation()} onclick={(e) => e.stopPropagation()}>
			<div class="modal-header">
				<h3>🌱 신규 농장 및 작물 등록</h3>
				<button type="button" class="btn-close" onclick={() => (showRegModal = false)}>&times;</button>
			</div>
			<form onsubmit={handleRegisterFarm} class="modal-form">
				<div class="form-group">
					<label for="reg-name">농장명 *</label>
					<input id="reg-name" type="text" bind:value={newName} placeholder="예: 김제 스마트 토마토 농장 2동" required />
				</div>

				<div class="form-row">
					<div class="form-group">
						<label for="reg-crop">작물명 *</label>
						<input id="reg-crop" type="text" bind:value={newCrop} placeholder="예: 토마토, 참외, 파프리카" required />
					</div>
					<div class="form-group">
						<label for="reg-variety">품종 *</label>
						<input id="reg-variety" type="text" bind:value={newVariety} placeholder="예: 마이노르, 꿀봉" required />
					</div>
				</div>

				<div class="form-row">
					<div class="form-group">
						<label for="reg-region">지역</label>
						<input id="reg-region" type="text" bind:value={newRegion} placeholder="예: 전북특별자치도 김제시" />
					</div>
					<div class="form-group">
						<label for="reg-planted">정식일 (Planting Date) *</label>
						<input id="reg-planted" type="date" bind:value={newPlantedAt} required />
					</div>
				</div>

				<div class="form-group">
					<label for="reg-stage">현재 생육 단계 *</label>
					<select id="reg-stage" bind:value={newGrowthStage}>
						<option value="육묘기">육묘기</option>
						<option value="영양생장기">영양생장기</option>
						<option value="생식생장기">생식생장기</option>
						<option value="수확기">수확기</option>
						<option value="수확후정리">수확후정리</option>
					</select>
				</div>

				<div class="form-group">
					<label for="reg-notes">농장 메모 및 시설 정보</label>
					<textarea id="reg-notes" bind:value={newNotes} rows="3" placeholder="예: 스마트온실 B동, EC 2.2 표준 관리"></textarea>
				</div>

				<div class="modal-actions">
					<button type="button" class="btn-secondary" onclick={() => (showRegModal = false)}>취소</button>
					<button type="submit" class="btn-primary">등록 완료</button>
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

	.hero-header {
		margin-bottom: 28px;
	}

	.header-top {
		display: flex;
		justify-content: space-between;
		align-items: flex-end;
		gap: 20px;
		flex-wrap: wrap;
	}

	.badge {
		display: inline-block;
		padding: 4px 10px;
		border-radius: 999px;
		background: #dff0d9;
		color: #2b6139;
		font-size: 0.72rem;
		font-weight: 800;
		letter-spacing: 0.08em;
		text-transform: uppercase;
	}

	h1 {
		margin: 10px 0 8px;
		font-size: clamp(1.8rem, 4vw, 2.4rem);
		letter-spacing: -0.04em;
		color: #173d29;
	}

	.hero-header p {
		margin: 0;
		color: #5b6e62;
		font-size: 0.96rem;
	}

	.btn-primary {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		padding: 12px 20px;
		border: none;
		border-radius: 12px;
		background: #25663b;
		color: #ffffff;
		font-weight: 700;
		font-size: 0.92rem;
		cursor: pointer;
		box-shadow: 0 4px 14px rgba(37, 102, 59, 0.25);
		transition: all 180ms ease;
	}

	.btn-primary:hover {
		background: #1c522e;
		transform: translateY(-1px);
	}

	.icon {
		width: 18px;
		height: 18px;
	}

	.card {
		padding: 28px;
		border: 1px solid #dce5dc;
		border-radius: 20px;
		background: #ffffff;
		box-shadow: 0 10px 30px rgba(23, 61, 41, 0.04);
		margin-bottom: 24px;
	}

	.active-farm-card {
		background: linear-gradient(135deg, #ffffff 0%, #f6faf5 100%);
		border-color: #cde0ca;
	}

	.market-quick-banner {
		display: flex;
		justify-content: space-between;
		align-items: center;
		flex-wrap: wrap;
		gap: 16px;
		background: linear-gradient(135deg, #f0f7f0 0%, #e2f0e0 100%);
		border: 1px solid #cde0ca;
		border-radius: 16px;
		padding: 18px 24px;
		margin-bottom: 24px;
	}

	.badge-quick {
		font-size: 0.72rem;
		font-weight: 800;
		color: #1e40af;
		background: #ffffff;
		padding: 2px 8px;
		border-radius: 6px;
	}

	.banner-info h4 {
		margin: 4px 0;
		font-size: 1.1rem;
		color: #164228;
	}

	.quick-stats-row {
		display: flex;
		gap: 18px;
		font-size: 0.82rem;
		color: #4b6152;
		flex-wrap: wrap;
	}

	.btn-goto-market {
		padding: 10px 18px;
		background: #173d29;
		color: #ffffff;
		border-radius: 10px;
		font-size: 0.85rem;
		font-weight: 750;
		text-decoration: none;
		transition: background 0.2s;
	}

	.btn-goto-market:hover {
		background: #25663b;
	}

	.farm-header-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		flex-wrap: wrap;
		gap: 16px;
		padding-bottom: 20px;
		border-bottom: 1px solid #e2ebe0;
	}

	.farm-title {
		display: flex;
		align-items: center;
		gap: 12px;
		flex-wrap: wrap;
	}

	.crop-badge {
		padding: 6px 12px;
		border-radius: 8px;
		background: #e4f2e1;
		color: #245b38;
		font-size: 0.82rem;
		font-weight: 800;
	}

	.farm-title h2 {
		margin: 0;
		font-size: 1.5rem;
		color: #163d28;
	}

	.stage-pill {
		padding: 4px 10px;
		border-radius: 999px;
		font-size: 0.76rem;
		font-weight: 750;
	}

	.stage-vegetative { background: #e0f2fe; color: #0369a1; }
	.stage-reproductive { background: #fef3c7; color: #b45309; }
	.stage-harvest { background: #dcfce7; color: #15803d; }
	.stage-seedling { background: #f3e8ff; color: #6b21a8; }
	.stage-post { background: #f3f4f6; color: #4b5563; }

	.farm-details-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
		gap: 16px;
		margin-top: 20px;
	}

	.detail-box {
		padding: 16px;
		border-radius: 14px;
		background: #ffffff;
		border: 1px solid #e6eee4;
	}

	.detail-box small {
		display: block;
		font-size: 0.74rem;
		color: #738779;
		margin-bottom: 4px;
	}

	.detail-box strong {
		font-size: 1.05rem;
		color: #173d29;
	}

	.detail-box strong.highlight {
		color: #25663b;
	}

	.farm-notes {
		margin-top: 20px;
		padding: 16px;
		border-radius: 12px;
		background: #f0f7ef;
		font-size: 0.9rem;
		color: #354e3e;
	}

	.two-col-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 24px;
	}

	@media (max-width: 840px) {
		.two-col-grid {
			grid-template-columns: 1fr;
		}
	}

	.card-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 18px;
	}

	.card-header h3 {
		margin: 0;
		font-size: 1.15rem;
		color: #173d29;
	}

	.link-more {
		font-size: 0.85rem;
		font-weight: 700;
		color: #25663b;
		text-decoration: none;
	}

	.quick-task-list {
		list-style: none;
		margin: 0;
		padding: 0;
	}

	.task-item {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 12px 14px;
		border-radius: 10px;
		background: #f8faf8;
		border: 1px solid #e8eee7;
		margin-bottom: 8px;
	}

	.task-info {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	.cat-tag {
		font-size: 0.72rem;
		padding: 2px 6px;
		border-radius: 4px;
		background: #e2ece0;
		color: #2d5a3c;
		font-weight: 700;
	}

	.followup-tag {
		font-size: 0.7rem;
		color: #dc2626;
		font-weight: 800;
	}

	.status-badge {
		font-size: 0.75rem;
		font-weight: 700;
		padding: 3px 8px;
		border-radius: 6px;
	}

	.status-badge.completed { background: #dcfce7; color: #166534; }
	.status-badge.issue { background: #fee2e2; color: #991b1b; }
	.status-badge.pending { background: #fef3c7; color: #92400e; }

	.weather-card {
		background: #153825;
		color: #ffffff;
		border-color: #1e4d34;
	}

	.weather-eyebrow {
		font-size: 0.68rem;
		font-weight: 800;
		letter-spacing: 0.14em;
		color: #8ed697;
	}

	.weather-card h3 {
		color: #ffffff;
	}

	.region-sub-tag {
		font-size: 0.76rem;
		color: #a4e5ac;
		font-weight: 700;
		margin-top: 4px;
		display: block;
	}

	.warn-text { color: #f97316 !important; }
	.normal-text { color: #4ade80 !important; }

	.weather-content {
		display: flex;
		flex-direction: column;
		gap: 18px;
	}

	.weather-temp strong {
		font-size: 2.8rem;
		line-height: 1;
	}

	.weather-temp span {
		display: block;
		margin-top: 6px;
		font-size: 0.95rem;
		color: #b5d8bc;
	}

	.weather-metrics {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 10px;
	}

	.weather-metrics div {
		padding: 12px;
		border-radius: 10px;
		background: rgba(255, 255, 255, 0.08);
	}

	.weather-metrics small {
		display: block;
		font-size: 0.7rem;
		color: #9cbca4;
	}

	.weather-metrics strong {
		font-size: 1.05rem;
	}

	.farms-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(260px, 100%), 1fr));
		gap: 16px;
	}

	.farm-mini-card {
		padding: 18px;
		border-radius: 14px;
		border: 1px solid #e1ebe0;
		background: #fbfdfb;
		cursor: pointer;
		transition: all 150ms ease;
	}

	.farm-mini-card:hover {
		border-color: #25663b;
		transform: translateY(-2px);
	}

	.farm-mini-card.selected {
		border-color: #25663b;
		background: #edf7eb;
		box-shadow: 0 0 0 2px #25663b;
	}

	.mini-header {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-bottom: 8px;
	}

	.mini-crop {
		font-size: 0.75rem;
		font-weight: 800;
		padding: 2px 6px;
		border-radius: 4px;
		background: #25663b;
		color: #fff;
	}

	.mini-header h4 {
		margin: 0;
		font-size: 0.98rem;
		color: #173d29;
	}

	.mini-region {
		margin: 0 0 12px;
		font-size: 0.8rem;
		color: #6a7f72;
	}

	.mini-footer {
		display: flex;
		justify-content: space-between;
		align-items: center;
		font-size: 0.78rem;
		color: #485c50;
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
		max-width: 540px;
		max-height: 90vh;
		overflow-y: auto;
		background: #ffffff;
		border-radius: 20px;
		padding: 28px;
		box-shadow: 0 20px 50px rgba(0, 0, 0, 0.2);
	}

	.modal-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 20px;
	}

	.modal-header h3 {
		margin: 0;
		font-size: 1.25rem;
		color: #173d29;
	}

	.btn-close {
		border: none;
		background: none;
		font-size: 1.5rem;
		cursor: pointer;
		color: #888;
	}

	.modal-form {
		display: flex;
		flex-direction: column;
		gap: 16px;
	}

	.form-group {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.form-row {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 14px;
	}

	label {
		font-size: 0.82rem;
		font-weight: 700;
		color: #2b4534;
	}

	input, select, textarea {
		padding: 10px 12px;
		border: 1px solid #d2ded0;
		border-radius: 10px;
		font-size: 0.9rem;
		font-family: inherit;
	}

	input:focus, select:focus, textarea:focus {
		outline: none;
		border-color: #25663b;
		box-shadow: 0 0 0 3px rgba(37, 102, 59, 0.15);
	}

	.modal-actions {
		display: flex;
		justify-content: flex-end;
		gap: 12px;
		margin-top: 10px;
	}

	.btn-secondary {
		padding: 10px 18px;
		border: 1px solid #d2ded0;
		border-radius: 10px;
		background: #f4f8f4;
		color: #3b5243;
		font-weight: 600;
		cursor: pointer;
	}
</style>
