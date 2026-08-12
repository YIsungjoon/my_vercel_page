<script lang="ts">
	import { farmStore } from '$lib/farmStore.svelte';
	import WeatherPestWidget from '$lib/components/WeatherPestWidget.svelte';
	import MarketPriceWidget from '$lib/components/MarketPriceWidget.svelte';
</script>

<svelte:head>
	<title>도매시세 & 농업 분석 | Dreaming Agri</title>
</svelte:head>

<main class="page-container">
	<header class="header-bar">
		<div>
			<span class="sub-badge">aT KAMIS & 공공데이터 연동</span>
			<h1>{farmStore.currentFarm.name} 도매시세 및 전문 농업 분석</h1>
			<p>실시간 지리 기상 특보, 농진청 병해충 예찰, aT 전국 도매시장 경락가 및 출하 예상 매출액을 통합 분석합니다.</p>
		</div>
	</header>

	<!-- Section 1: Real-time Agricultural Weather & Pest Warning Widgets -->
	<WeatherPestWidget />

	<!-- Section 2: aT KAMIS Wholesale Prices & Revenue Calculator Widget -->
	<MarketPriceWidget />
</main>

<style>
	.page-container {
		padding: 28px 36px;
		max-width: 1400px;
		margin: 0 auto;
		min-width: 0;
	}

	.header-bar {
		margin-bottom: 28px;
	}

	.sub-badge {
		font-size: 0.76rem;
		font-weight: 800;
		color: #1e40af;
		background: #dbeafe;
		padding: 3px 10px;
		border-radius: 6px;
	}

	.header-bar h1 {
		margin: 8px 0 4px;
		font-size: 1.6rem;
		color: #173d29;
	}

	.header-bar p {
		margin: 0;
		font-size: 0.9rem;
		color: #556c5e;
	}

	@media (max-width: 640px) {
		.page-container {
			padding: 28px 16px 48px;
		}

		.header-bar {
			margin-bottom: 20px;
		}

		.header-bar h1 {
			font-size: 1.45rem;
			line-height: 1.35;
		}

		.header-bar p {
			line-height: 1.55;
		}
	}
</style>
