<script lang="ts">
	import { farmStore } from '$agri/farmStore.svelte';
	import {
		fetchAgriculturalWeather,
		fetchPestWarnings,
		type WeatherInfo,
		type PestWarningInfo
	} from '$agri/services/agriApiService';

	let weather = $state<WeatherInfo | null>(null);
	let pestWarnings = $state<PestWarningInfo[]>([]);
	let loading = $state(true);
	let lastRefreshedTime = $state<string>('');

	const currentFarm = $derived(farmStore.currentFarm);

	$effect(() => {
		const region = currentFarm.region;
		const crop = currentFarm.crop;

		loadApiData(region, crop);

		// 1-hour (3,600,000 ms) auto-refresh interval
		const interval = setInterval(() => {
			loadApiData(region, crop);
		}, 3600000);

		return () => clearInterval(interval);
	});

	async function loadApiData(region: string, crop: string) {
		loading = true;
		try {
			const [wData, pData] = await Promise.all([
				fetchAgriculturalWeather(region),
				fetchPestWarnings(crop)
			]);
			weather = wData;
			pestWarnings = pData;
			lastRefreshedTime = new Date().toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' });
		} finally {
			loading = false;
		}
	}
</script>

<div class="api-widget-container">
	<!-- Left: Agricultural Weather API Widget -->
	<div class="widget-card weather-card">
		<div class="widget-header">
			<div class="title-meta">
				<span class="badge-api">🌤️ 1시간 단위 실시간 기상</span>
				<h3>{currentFarm.name} 기상 관측</h3>
			</div>
			<div class="header-right">
				<span class="region-tag">📍 {currentFarm.region}</span>
				{#if lastRefreshedTime}
					<small class="refresh-time">🔄 갱신: {lastRefreshedTime}</small>
				{/if}
			</div>
		</div>

		{#if loading}
			<div class="loading-box">해당 농가 위치의 실시간 기상관측 데이터를 불러오는 중...</div>
		{:else if weather}
			<div class="weather-body">
				<div class="metrics-row">
					<div class="metric-item">
						<span class="label">실시간 기온</span>
						<span class="value temp">{weather.temperature}°C</span>
					</div>
					<div class="metric-item">
						<span class="label">상대습도</span>
						<span class="value humidity">{weather.humidity}%</span>
					</div>
					<div class="metric-item">
						<span class="label">강수확률</span>
						<span class="value rain">{weather.precipitationProbability}%</span>
					</div>
				</div>

				<div class="warning-alert-box" class:alert-active={weather.warningType !== 'none'}>
					<strong>{weather.warningMessage}</strong>
					<p>💡 {weather.recommendation}</p>
				</div>
			</div>
		{/if}
	</div>

	<!-- Right: NIFS/RDA Pest & Disease Warning API Widget -->
	<div class="widget-card pest-card">
		<div class="widget-header">
			<div class="title-meta">
				<span class="badge-api">🐛 농진청 예찰 연동</span>
				<h3>{currentFarm.crop} 병해충 경보</h3>
			</div>
			<span class="crop-tag">🌱 {currentFarm.crop} ({currentFarm.variety})</span>
		</div>

		{#if loading}
			<div class="loading-box">농가 작물 병해충 예찰 데이터를 불러오는 중...</div>
		{:else}
			<div class="pest-list">
				{#each pestWarnings as item}
					<div class="pest-item">
						<div class="pest-item-top">
							<span class="pest-name">🐛 {item.pestName}</span>
							<span
								class="level-badge"
								class:lvl-danger={item.warningLevel === '경보'}
								class:lvl-warning={item.warningLevel === '주의'}
								class:lvl-info={item.warningLevel === '관심'}
							>
								{item.warningLevel}
							</span>
						</div>
						<p class="pest-desc">{item.description}</p>
						<div class="preventive-box">
							<strong>🛡️ 예방 방제 수칙:</strong> {item.preventiveAction}
						</div>
					</div>
				{/each}
			</div>
		{/if}
	</div>
</div>

<style>
	.api-widget-container {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(360px, 100%), 1fr));
		gap: 20px;
		margin-bottom: 24px;
		min-width: 0;
	}

	.widget-card {
		width: 100%;
		min-width: 0;
		max-width: 100%;
		background: #ffffff;
		border: 1px solid #dce5dc;
		border-radius: 18px;
		padding: 20px;
		box-shadow: 0 6px 20px rgba(23, 61, 41, 0.04);
	}

	.widget-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		flex-wrap: wrap;
		gap: 12px;
		margin-bottom: 16px;
	}

	.title-meta {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.header-right {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 4px;
	}

	.badge-api {
		font-size: 0.72rem;
		font-weight: 800;
		color: #15803d;
		background: #dcfce7;
		padding: 2px 8px;
		border-radius: 6px;
		width: fit-content;
	}

	.widget-header h3 {
		margin: 0;
		font-size: 1.1rem;
		color: #173d29;
	}

	.region-tag, .crop-tag {
		font-size: 0.78rem;
		color: #556c5e;
		font-weight: 700;
		background: #f0f7ef;
		padding: 3px 8px;
		border-radius: 6px;
	}

	.refresh-time {
		font-size: 0.72rem;
		color: #789082;
		font-weight: 600;
	}

	.loading-box {
		padding: 30px;
		text-align: center;
		font-size: 0.85rem;
		color: #6a7f72;
	}

	.metrics-row {
		display: flex;
		justify-content: space-around;
		background: #f6faf6;
		padding: 12px;
		border-radius: 12px;
		margin-bottom: 14px;
	}

	.metric-item {
		display: flex;
		flex-direction: column;
		align-items: center;
	}

	.metric-item .label {
		font-size: 0.75rem;
		color: #5d7366;
		margin-bottom: 4px;
	}

	.metric-item .value {
		font-size: 1.25rem;
		font-weight: 800;
	}

	.value.temp { color: #dc2626; }
	.value.humidity { color: #2563eb; }
	.value.rain { color: #059669; }

	.warning-alert-box {
		padding: 12px 16px;
		border-radius: 12px;
		background: #f9faf9;
		border: 1px solid #e1ebe0;
	}

	.warning-alert-box.alert-active {
		background: #fff7ed;
		border-color: #fdba74;
	}

	.warning-alert-box strong {
		display: block;
		font-size: 0.88rem;
		color: #c2410c;
		margin-bottom: 4px;
	}

	.warning-alert-box p {
		margin: 0;
		font-size: 0.8rem;
		color: #431407;
		line-height: 1.45;
	}

	.pest-list {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}

	.pest-item {
		padding: 12px 14px;
		border-radius: 12px;
		background: #fafcf9;
		border: 1px solid #e3ebe2;
	}

	.pest-item-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 6px;
	}

	.pest-name {
		font-size: 0.9rem;
		font-weight: 800;
		color: #1c522e;
	}

	.level-badge {
		font-size: 0.72rem;
		font-weight: 800;
		padding: 2px 8px;
		border-radius: 6px;
	}

	.lvl-danger { background: #fee2e2; color: #b91c1c; }
	.lvl-warning { background: #ffedd5; color: #c2410c; }
	.lvl-info { background: #e0f2fe; color: #0369a1; }

	.pest-desc {
		margin: 0 0 8px;
		font-size: 0.8rem;
		color: #556c5e;
		line-height: 1.4;
	}

	.preventive-box {
		font-size: 0.78rem;
		color: #166534;
		background: #f0fdf4;
		padding: 8px 10px;
		border-radius: 8px;
		border: 1px solid #bbf7d0;
	}

	@media (max-width: 640px) {
		.widget-card {
			padding: 16px;
			border-radius: 8px;
		}

		.header-right {
			align-items: flex-start;
		}

		.metrics-row {
			gap: 8px;
			padding: 12px 8px;
		}

		.metric-item .value {
			font-size: 1.15rem;
		}
	}
</style>
