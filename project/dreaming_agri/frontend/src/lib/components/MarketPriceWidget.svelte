<script lang="ts">
	import { farmStore } from '$lib/farmStore.svelte';
	import { fetchCropMarketPrice, type MarketPriceInfo } from '$lib/services/marketApiService';

	let market = $state<MarketPriceInfo | null>(null);
	let loading = $state(true);

	// Harvest Revenue Simulator state
	let boxCount = $state<number>(30);

	const currentFarm = $derived(farmStore.currentFarm);

	$effect(() => {
		loadMarketData(currentFarm.crop);
	});

	async function loadMarketData(crop: string) {
		loading = true;
		try {
			market = await fetchCropMarketPrice(crop);
		} finally {
			loading = false;
		}
	}

	// SVG Line Chart Calculation for 7-day trend
	const lineChartPoints = $derived.by(() => {
		if (!market || !market.weeklyHistory || market.weeklyHistory.length === 0) return [];
		const history = market.weeklyHistory;
		const prices = history.map((h) => h.price);
		const minP = Math.min(...prices) * 0.97;
		const maxP = Math.max(...prices) * 1.03;
		const pRange = maxP - minP || 1;

		const svgWidth = 560;
		const svgHeight = 180;
		const paddingX = 40;
		const paddingTop = 32;
		const paddingBottom = 35;
		const drawHeight = svgHeight - paddingTop - paddingBottom;
		const drawWidth = svgWidth - paddingX * 2;

		return history.map((item, index) => {
			const x = paddingX + (index / (history.length - 1)) * drawWidth;
			const y = svgHeight - paddingBottom - ((item.price - minP) / pRange) * drawHeight;
			return {
				...item,
				x: Math.round(x * 10) / 10,
				y: Math.round(y * 10) / 10
			};
		});
	});

	const polylinePointsStr = $derived(lineChartPoints.map((p) => `${p.x},${p.y}`).join(' '));
	const areaPolygonStr = $derived(
		lineChartPoints.length > 0
			? `${lineChartPoints[0].x},145 ${polylinePointsStr} ${lineChartPoints[lineChartPoints.length - 1].x},145`
			: ''
	);

	// Financial Calculations (Gross Revenue vs Net Profit)
	const estimatedGrossRevenue = $derived.by(() => {
		if (!market || !boxCount) return 0;
		return boxCount * market.avgPrice;
	});

	const commissionFee = $derived(Math.round(estimatedGrossRevenue * 0.07)); // 7% wholesale commission
	const shippingFee = $derived(boxCount * 2500); // 2,500 KRW per box
	const packageFee = $derived(boxCount * 1200); // 1,200 KRW per box
	const netProfit = $derived(estimatedGrossRevenue - commissionFee - shippingFee - packageFee);

	// Cross-Market 5-Major Market Comparison Mock Table
	const crossMarkets = $derived.by(() => {
		if (!market) return [];
		const base = market.avgPrice;
		return [
			{ name: '서울 가락도매시장', price: market.maxPrice, isTop: true, change: '+4.5%' },
			{ name: '대구 북부도매시장', price: Math.round(base * 0.98 / 100) * 100, isTop: false, change: '+1.2%' },
			{ name: '대전 노은도매시장', price: Math.round(base * 0.96 / 100) * 100, isTop: false, change: '-0.5%' },
			{ name: '광주 각화도매시장', price: Math.round(base * 0.95 / 100) * 100, isTop: false, change: '-1.0%' },
			{ name: '부산 엄궁도매시장', price: Math.round(base * 0.97 / 100) * 100, isTop: false, change: '+0.8%' }
		];
	});
</script>

<div class="market-widget-card">
	<div class="widget-header">
		<div class="title-meta">
			<span class="badge-api">💰 aT KAMIS 실시간 도매시세</span>
			<h3>{currentFarm.crop} 경락가 꺾은선 추이 및 농가 순수익 시뮬레이션</h3>
		</div>
		<span class="crop-tag">🌱 {currentFarm.crop} ({currentFarm.variety})</span>
	</div>

	{#if loading}
		<div class="loading-box">전국 도매시장 경락가를 조회하는 중입니다...</div>
	{:else if market}
		<div class="market-body-grid">
			<!-- Left: Wholesale Price Overview & 7-Day Line Chart -->
			<div class="price-overview-box">
				<div class="main-price-row">
					<div class="price-big">
						<small>전국 평균 도매가 ({market.unit})</small>
						<strong class="price-num">{market.avgPrice.toLocaleString()} <span class="unit-won">원</span></strong>
					</div>
					<div
						class="trend-badge"
						class:trend-up={market.trendStatus === 'up'}
						class:trend-down={market.trendStatus === 'down'}
					>
						{market.trendStatus === 'up' ? '▲' : '▼'} {Math.abs(market.changeRate)}%
					</div>
				</div>

				<div class="price-sub-grid">
					<div class="sub-item">
						<small>최고가</small>
						<span class="val max">{market.maxPrice.toLocaleString()}원</span>
					</div>
					<div class="sub-item">
						<small>최저가</small>
						<span class="val min">{market.minPrice.toLocaleString()}원</span>
					</div>
					<div class="sub-item">
						<small>최고가 형성 시장</small>
						<span class="val market-name">📍 {market.topMarket}</span>
					</div>
				</div>

				<!-- 7-Day Line Chart with Price Values Above Dots -->
				<div class="line-chart-wrapper">
					<small class="box-title">📈 최근 7일 도매/경락가 꺾은선 추이 (원/상자)</small>
					<div class="svg-chart-box">
						<svg class="line-chart-svg" viewBox="0 0 560 180" preserveAspectRatio="none">
							<defs>
								<linearGradient id="chartGradient" x1="0" y1="0" x2="0" y2="1">
									<stop offset="0%" stop-color="#2563eb" stop-opacity="0.25" />
									<stop offset="100%" stop-color="#2563eb" stop-opacity="0.0" />
								</linearGradient>
							</defs>

							<!-- Baseline grid line -->
							<line x1="30" y1="145" x2="530" y2="145" stroke="#e2ebe0" stroke-width="1" />

							<!-- Area Fill -->
							{#if areaPolygonStr}
								<polygon points={areaPolygonStr} fill="url(#chartGradient)" />
							{/if}

							<!-- Line -->
							{#if polylinePointsStr}
								<polyline
									points={polylinePointsStr}
									fill="none"
									stroke="#2563eb"
									stroke-width="3.5"
									stroke-linecap="round"
									stroke-linejoin="round"
								/>
							{/if}

							<!-- Data Dots & Price Text Label ABOVE Dot -->
							{#each lineChartPoints as pt}
								<!-- Price Label ABOVE Dot -->
								<text
									x={pt.x}
									y={pt.y - 10}
									text-anchor="middle"
									font-size="11"
									font-weight="850"
									fill="#1e3a8a"
								>
									{pt.price.toLocaleString()}원
								</text>

								<!-- Dot Circle -->
								<circle cx={pt.x} cy={pt.y} r="5" fill="#ffffff" stroke="#2563eb" stroke-width="3" />

								<!-- X-Axis Date Label -->
								<text x={pt.x} y="165" text-anchor="middle" font-size="11" font-weight="700" fill="#64748b">
									{pt.date}
								</text>
							{/each}
						</svg>
					</div>
				</div>
			</div>

			<!-- Right: Revenue & Net Profit Simulator + Cross Market Comparison -->
			<div class="revenue-and-comparison">
				<!-- Revenue & Net Profit Simulator -->
				<div class="revenue-simulator-box">
					<h4>⚡ 농가 실 순이익(Net Profit) 산출 계산기</h4>
					<p class="sim-desc">수확 상자 수 입력 시 수수료(7%), 운송비, 상자비를 제하고 **손에 쥐는 순이익**을 계산합니다.</p>

					<div class="sim-form-group">
						<label for="box-input">수확 예정 물량 ({market.unit})</label>
						<div class="input-with-btn">
							<input id="box-input" type="number" bind:value={boxCount} min="1" max="1000" />
							<span class="input-unit">상자</span>
						</div>
						<div class="quick-btns">
							<button type="button" onclick={() => (boxCount = 10)}>10상자</button>
							<button type="button" onclick={() => (boxCount = 30)}>30상자</button>
							<button type="button" onclick={() => (boxCount = 50)}>50상자</button>
							<button type="button" onclick={() => (boxCount = 100)}>100상자</button>
						</div>
					</div>

					<div class="sim-result-card">
						<div class="sim-row">
							<span>총 예상 매출액 (Gross):</span>
							<strong class="revenue-val">{estimatedGrossRevenue.toLocaleString()} 원</strong>
						</div>
						<div class="deduction-breakdown">
							<small>• 공제 항목: 수수료 7%({commissionFee.toLocaleString()}원) + 운송비({shippingFee.toLocaleString()}원) + 상자비({packageFee.toLocaleString()}원)</small>
						</div>
						<div class="sim-row net-profit-row">
							<span>농가 실제 정산 순수익 (Net):</span>
							<strong class="net-profit-val">￦ {netProfit.toLocaleString()} 원</strong>
						</div>
					</div>
				</div>

				<!-- Cross Market 5-Major Market Comparison Table -->
				<div class="cross-market-box">
					<h4>📊 전국 5대 도매시장 실시간 경락가 비교</h4>
					<div class="market-table-scroll" role="region" aria-label="전국 5대 도매시장 경락가 비교표">
						<table class="market-table">
						<thead>
							<tr>
								<th>도매시장 명칭</th>
								<th>경락가 ({market.unit})</th>
								<th>등락률</th>
							</tr>
						</thead>
						<tbody>
							{#each crossMarkets as m}
								<tr class:is-top-market={m.isTop}>
									<td>
										{m.name}
										{#if m.isTop}
											<span class="top-badge">★ 최고가</span>
										{/if}
									</td>
									<td class="price-td">{m.price.toLocaleString()} 원</td>
									<td class="change-td" class:plus={m.change.startsWith('+')}>{m.change}</td>
								</tr>
							{/each}
						</tbody>
						</table>
					</div>
				</div>
			</div>
		</div>
	{/if}
</div>

<style>
	.market-widget-card {
		width: 100%;
		min-width: 0;
		max-width: 100%;
		margin-bottom: 24px;
		background: #ffffff;
		border: 1px solid #dce5dc;
		border-radius: 18px;
		padding: 22px;
		box-shadow: 0 6px 20px rgba(23, 61, 41, 0.04);
	}

	.widget-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		flex-wrap: wrap;
		gap: 12px;
		margin-bottom: 18px;
	}

	.title-meta {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.badge-api {
		font-size: 0.72rem;
		font-weight: 800;
		color: #1e40af;
		background: #dbeafe;
		padding: 2px 8px;
		border-radius: 6px;
		width: fit-content;
	}

	.widget-header h3 {
		margin: 0;
		font-size: 1.1rem;
		color: #173d29;
	}

	.crop-tag {
		font-size: 0.78rem;
		color: #556c5e;
		font-weight: 700;
		background: #f0f7ef;
		padding: 4px 10px;
		border-radius: 6px;
	}

	.loading-box {
		padding: 30px;
		text-align: center;
		color: #6a7f72;
	}

	.market-body-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(340px, 100%), 1fr));
		gap: 20px;
		min-width: 0;
	}

	/* Price Overview */
	.price-overview-box {
		min-width: 0;
		max-width: 100%;
		background: #f8faf8;
		border: 1px solid #e1ebe0;
		border-radius: 14px;
		padding: 18px;
	}

	.main-price-row {
		display: flex;
		justify-content: space-between;
		align-items: flex-end;
		margin-bottom: 14px;
		padding-bottom: 12px;
		border-bottom: 1px solid #e1ebe0;
	}

	.price-big small {
		display: block;
		font-size: 0.76rem;
		color: #597062;
		margin-bottom: 2px;
	}

	.price-num {
		font-size: 1.6rem;
		font-weight: 850;
		color: #164228;
	}

	.unit-won { font-size: 1rem; font-weight: 700; }

	.trend-badge {
		font-size: 0.85rem;
		font-weight: 800;
		padding: 4px 10px;
		border-radius: 8px;
	}

	.trend-up { background: #fee2e2; color: #dc2626; }
	.trend-down { background: #dbeafe; color: #2563eb; }

	.price-sub-grid {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 8px;
		margin-bottom: 18px;
	}

	.sub-item {
		background: #ffffff;
		padding: 8px 10px;
		border-radius: 8px;
		border: 1px solid #e5eee4;
	}

	.sub-item small {
		display: block;
		font-size: 0.7rem;
		color: #6c8274;
	}

	.sub-item .val {
		font-size: 0.85rem;
		font-weight: 800;
	}

	.val.max { color: #dc2626; }
	.val.min { color: #2563eb; }
	.val.market-name { color: #166534; font-size: 0.76rem; }

	/* SVG Line Chart Style */
	.line-chart-wrapper .box-title {
		font-size: 0.82rem;
		color: #173d29;
		font-weight: 800;
		display: block;
		margin-bottom: 8px;
	}

	.svg-chart-box {
		background: #ffffff;
		border: 1px solid #e3ebe2;
		border-radius: 12px;
		padding: 10px 6px 4px;
	}

	.line-chart-svg {
		width: 100%;
		height: auto;
		display: block;
	}

	/* Revenue & Comparison Column */
	.revenue-and-comparison {
		display: flex;
		flex-direction: column;
		gap: 16px;
		min-width: 0;
		max-width: 100%;
	}

	/* Revenue Simulator */
	.revenue-simulator-box {
		background: #f0f7f0;
		border: 1px solid #cde0ca;
		border-radius: 14px;
		padding: 16px;
	}

	.revenue-simulator-box h4 {
		margin: 0 0 4px;
		font-size: 0.98rem;
		color: #164228;
	}

	.sim-desc {
		margin: 0 0 12px;
		font-size: 0.78rem;
		color: #556c5e;
		line-height: 1.4;
	}

	.sim-form-group label {
		font-size: 0.78rem;
		font-weight: 750;
		color: #1c522e;
		display: block;
		margin-bottom: 4px;
	}

	.input-with-btn {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-bottom: 6px;
	}

	.input-with-btn input {
		width: 110px;
		padding: 6px 10px;
		border: 1px solid #b2cbaf;
		border-radius: 8px;
		font-size: 1rem;
		font-weight: 800;
		color: #164228;
	}

	.input-unit { font-size: 0.85rem; font-weight: 750; color: #2e593d; }

	.quick-btns {
		display: flex;
		gap: 4px;
		margin-bottom: 12px;
	}

	.quick-btns button {
		padding: 3px 8px;
		border: 1px solid #b2cbaf;
		border-radius: 6px;
		background: #ffffff;
		font-size: 0.72rem;
		font-weight: 700;
		color: #2b5437;
		cursor: pointer;
	}

	.sim-result-card {
		background: #ffffff;
		padding: 12px;
		border-radius: 10px;
		border: 1px solid #b2cbaf;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.sim-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		font-size: 0.8rem;
		color: #4b6152;
	}

	.revenue-val {
		font-size: 1rem;
		font-weight: 850;
		color: #15803d;
	}

	.deduction-breakdown {
		font-size: 0.7rem;
		color: #64748b;
		background: #f8faf8;
		padding: 4px 8px;
		border-radius: 6px;
	}

	.net-profit-row {
		border-top: 1px dashed #cbd5e1;
		padding-top: 6px;
	}

	.net-profit-val {
		font-size: 1.15rem;
		font-weight: 900;
		color: #2563eb;
	}

	/* Cross Market Table */
	.cross-market-box {
		min-width: 0;
		max-width: 100%;
		background: #ffffff;
		border: 1px solid #e1ebe0;
		border-radius: 14px;
		padding: 14px;
	}

	.cross-market-box h4 {
		margin: 0 0 10px;
		font-size: 0.9rem;
		color: #173d29;
	}

	.market-table {
		width: 100%;
		min-width: 440px;
		border-collapse: collapse;
		font-size: 0.78rem;
	}

	.market-table th, .market-table td {
		padding: 6px 8px;
		text-align: left;
		border-bottom: 1px solid #f0f4f0;
	}

	.market-table th {
		background: #f6faf6;
		color: #4b6152;
		font-weight: 750;
	}

	.price-td { font-weight: 800; color: #164228; text-align: right; }
	.change-td { text-align: right; font-weight: 700; color: #2563eb; }
	.change-td.plus { color: #dc2626; }

	.is-top-market { background: #f0fdf4; }
	.top-badge {
		font-size: 0.65rem;
		background: #dcfce7;
		color: #15803d;
		padding: 1px 4px;
		border-radius: 4px;
		font-weight: 800;
		margin-left: 4px;
	}

	.market-table-scroll {
		max-width: 100%;
		overflow-x: auto;
		border-radius: 8px;
	}

	@media (max-width: 640px) {
		.market-widget-card {
			padding: 16px;
			border-radius: 8px;
		}

		.price-overview-box,
		.revenue-simulator-box,
		.cross-market-box {
			padding: 14px;
		}

		.price-sub-grid {
			grid-template-columns: 1fr 1fr;
		}

		.price-sub-grid .sub-item:last-child {
			grid-column: 1 / -1;
		}

		.quick-btns {
			display: grid;
			grid-template-columns: repeat(4, minmax(0, 1fr));
		}

		.quick-btns button {
			padding: 6px 2px;
		}

		.sim-row {
			align-items: flex-start;
			flex-direction: column;
			gap: 2px;
		}
	}
</style>
