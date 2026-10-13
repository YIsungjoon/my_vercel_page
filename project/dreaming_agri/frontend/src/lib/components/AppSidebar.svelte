<script lang="ts">
	import { browser } from '$app/environment';
	import { page } from '$app/state';
	import { farmStore } from '$lib/farmStore.svelte';

	const navigation = [
		{
			id: 'overview',
			label: '농장 현황 & 등록',
			href: '/',
			path: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6'
		},
		{
			id: 'tasks',
			label: '오늘 & 주간 작업',
			href: '/tasks',
			path: 'M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01'
		},
		{
			id: 'market',
			label: '도매시세 & 농업 분석',
			href: '/market',
			path: 'M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z'
		},
		{
			id: 'ai',
			label: 'AI 질의응답 & 요약',
			href: '/ai',
			path: 'M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z'
		},
		{
			id: 'admin',
			label: '농가 통합 관리자',
			href: '/admin',
			path: 'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z'
		}
	];

	let mobileOpen = $state(false);
	let mobileViewport = $state(false);

	$effect(() => {
		if (!browser) return;

		const media = window.matchMedia('(max-width: 960px)');
		const updateViewport = () => (mobileViewport = media.matches);
		updateViewport();
		media.addEventListener('change', updateViewport);

		return () => media.removeEventListener('change', updateViewport);
	});

	function isPathActive(href: string): boolean {
		const pathname = page.url.pathname;
		if (href === '/') return pathname === '/';
		return pathname.startsWith(href);
	}
</script>

<svelte:window onkeydown={(event) => event.key === 'Escape' && (mobileOpen = false)} />

<header class="mobile-bar">
	<button
		type="button"
		class="menu-button"
		aria-label={mobileOpen ? '메뉴 닫기' : '메뉴 열기'}
		aria-expanded={mobileOpen}
		aria-controls="app-sidebar"
		onclick={() => (mobileOpen = !mobileOpen)}
	>
		<span></span><span></span><span></span>
	</button>
	<a class="mobile-brand" href="/">
		<span class="brand-mark" aria-hidden="true"><i></i></span>
		<strong>Dreaming Agri</strong>
	</a>
</header>

{#if mobileOpen}
	<button
		type="button"
		class="backdrop visible"
		aria-hidden="true"
		tabindex="-1"
		onclick={() => (mobileOpen = false)}
	></button>
{/if}

<aside
	id="app-sidebar"
	class:open={mobileOpen}
	aria-label="주요 탐색"
	aria-hidden={mobileViewport && !mobileOpen ? 'true' : undefined}
	inert={mobileViewport && !mobileOpen}
>
	<div class="sidebar-top">
		<a class="brand" href="/">
			<span class="brand-mark" aria-hidden="true"><i></i></span>
			<span>
				<strong>Dreaming Agri</strong>
				<small>Farm Operations MVP</small>
			</span>
		</a>
		<button
			type="button"
			class="sidebar-close"
			aria-label="메뉴 닫기"
			title="메뉴 닫기"
			onclick={() => (mobileOpen = false)}
		>
			&times;
		</button>
	</div>

	<!-- Farm Switcher Dropdown -->
	<div class="farm-context">
		<label for="farm-select" class="farm-label">
			<span class="farm-icon">{farmStore.currentFarm.crop.slice(0, 1)}</span>
			<span class="farm-info">
				<small>현재 관리 농장</small>
				<strong>{farmStore.currentFarm.name}</strong>
			</span>
		</label>
		<select
			id="farm-select"
			class="farm-select-input"
			value={farmStore.selectedFarmId}
			onchange={(e) => farmStore.selectFarm(e.currentTarget.value)}
		>
			{#each farmStore.farms as farm}
				<option value={farm.id}>
					{farm.name} ({farm.crop} / {farm.growth_stage})
				</option>
			{/each}
		</select>
	</div>

	<nav aria-label="메인 메뉴">
		<p>MENU</p>
		<ul>
			{#each navigation as item}
				<li>
					<a
						href={item.href}
						class:active={isPathActive(item.href)}
						aria-current={isPathActive(item.href) ? 'page' : undefined}
						onclick={() => (mobileOpen = false)}
					>
						<svg viewBox="0 0 24 24" aria-hidden="true">
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d={item.path}></path>
						</svg>
						<span>{item.label}</span>
					</a>
				</li>
			{/each}
		</ul>
	</nav>

	<div class="sidebar-footer">
		<div class="status-row">
			<span aria-hidden="true"></span>
			<strong>Supabase & Weather Live</strong>
		</div>
		<p>작물: {farmStore.currentFarm.crop} ({farmStore.currentFarm.variety})</p>
		<p>생육단계: <span class="stage-tag">{farmStore.currentFarm.growth_stage}</span></p>
	</div>
</aside>

<style>
	:global(:root) {
		--sidebar-width: 272px;
	}

	aside {
		position: fixed;
		z-index: 40;
		inset: 0 auto 0 0;
		display: flex;
		width: var(--sidebar-width);
		padding: 28px 20px 24px;
		flex-direction: column;
		overflow-y: auto;
		background:
			radial-gradient(circle at 20% 8%, rgba(119, 183, 112, 0.15), transparent 32%),
			#123322;
		color: #f4f8f4;
		box-shadow: 12px 0 40px rgba(18, 51, 34, 0.08);
	}

	.brand,
	.mobile-brand {
		display: flex;
		align-items: center;
		gap: 12px;
		text-decoration: none;
	}

	.sidebar-top {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
	}

	.sidebar-close {
		display: none;
	}

	.brand {
		padding: 0 8px;
	}

	.brand-mark {
		position: relative;
		display: grid;
		width: 36px;
		height: 36px;
		flex: 0 0 auto;
		place-items: center;
		border-radius: 11px;
		background: #dff0d9;
	}

	.brand-mark::before,
	.brand-mark i {
		position: absolute;
		content: '';
		background: #39774a;
	}

	.brand-mark::before {
		width: 12px;
		height: 17px;
		border-radius: 12px 2px 12px 2px;
		transform: translate(-3px, -2px) rotate(-10deg);
	}

	.brand-mark i {
		width: 2px;
		height: 13px;
		border-radius: 2px;
		transform: translate(4px, 7px) rotate(30deg);
	}

	.brand > span:last-child {
		display: flex;
		min-width: 0;
		flex-direction: column;
		gap: 2px;
	}

	.brand strong,
	.mobile-brand strong {
		font-size: 0.98rem;
		letter-spacing: -0.02em;
		color: #f4f8f4;
	}

	.brand small {
		font-size: 0.64rem;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: #91aa99;
	}

	.farm-context {
		position: relative;
		margin-top: 28px;
		padding: 12px;
		border: 1px solid rgba(255, 255, 255, 0.12);
		border-radius: 16px;
		background: rgba(255, 255, 255, 0.06);
	}

	.farm-label {
		display: flex;
		align-items: center;
		gap: 12px;
		cursor: pointer;
	}

	.farm-icon {
		display: grid;
		width: 38px;
		height: 38px;
		flex: 0 0 auto;
		place-items: center;
		border-radius: 12px;
		background: #2f6842;
		font-size: 0.9rem;
		font-weight: 800;
		color: #dff0d9;
	}

	.farm-info {
		display: flex;
		min-width: 0;
		flex-direction: column;
		gap: 2px;
	}

	.farm-info small {
		font-size: 0.65rem;
		color: #8ca493;
	}

	.farm-info strong {
		overflow: hidden;
		font-size: 0.84rem;
		text-overflow: ellipsis;
		white-space: nowrap;
		color: #ffffff;
	}

	.farm-select-input {
		margin-top: 8px;
		width: 100%;
		padding: 6px 10px;
		border: 1px solid rgba(255, 255, 255, 0.2);
		border-radius: 8px;
		background: #1a422d;
		color: #e4f0e1;
		font-size: 0.78rem;
		cursor: pointer;
	}

	nav {
		margin-top: 28px;
	}

	nav > p {
		margin: 0 12px 10px;
		font-size: 0.62rem;
		font-weight: 800;
		letter-spacing: 0.16em;
		color: #718a79;
	}

	nav ul {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	nav li + li {
		margin-top: 6px;
	}

	nav a {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 12px 14px;
		border-radius: 12px;
		font-size: 0.88rem;
		font-weight: 650;
		color: #aebfb3;
		text-decoration: none;
		transition: all 150ms ease;
	}

	nav a:hover {
		background: rgba(255, 255, 255, 0.08);
		color: #f4f8f4;
	}

	nav a.active {
		background: #dff0d9;
		color: #1c4d2e;
		font-weight: 750;
	}

	nav svg {
		width: 20px;
		height: 20px;
		flex: 0 0 auto;
		fill: none;
		stroke: currentColor;
	}

	.sidebar-footer {
		margin-top: auto;
		padding: 16px;
		border-top: 1px solid rgba(255, 255, 255, 0.1);
	}

	.status-row {
		display: flex;
		align-items: center;
		gap: 9px;
	}

	.status-row span {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: #7dc879;
		box-shadow: 0 0 0 4px rgba(125, 200, 121, 0.12);
	}

	.status-row strong {
		font-size: 0.78rem;
	}

	.sidebar-footer p {
		margin: 6px 0 0 0;
		font-size: 0.72rem;
		color: #9cb3a4;
	}

	.stage-tag {
		display: inline-block;
		padding: 1px 6px;
		border-radius: 4px;
		background: rgba(125, 200, 121, 0.2);
		color: #a5e2a2;
		font-weight: 700;
	}

	.mobile-bar,
	.backdrop {
		display: none;
	}

	@media (max-width: 960px) {
		aside {
			width: min(84vw, 320px);
			transform: translateX(-105%);
			visibility: hidden;
			transition: transform 220ms ease, visibility 0s linear 220ms;
		}

		aside.open {
			transform: translateX(0);
			visibility: visible;
			transition-delay: 0s;
		}

		.mobile-bar {
			position: sticky;
			z-index: 30;
			top: 0;
			display: flex;
			height: 66px;
			padding: 0 18px;
			align-items: center;
			justify-content: flex-start;
			gap: 12px;
			border-bottom: 1px solid #dde5dc;
			background: rgba(244, 247, 242, 0.94);
			backdrop-filter: blur(14px);
		}

		.mobile-brand {
			color: #173d29;
		}

		.mobile-brand .brand-mark {
			width: 32px;
			height: 32px;
		}

		.menu-button {
			display: grid;
			width: 40px;
			height: 40px;
			padding: 10px;
			place-content: center;
			gap: 4px;
			border: 1px solid #d7e1d6;
			border-radius: 12px;
			background: #fff;
			cursor: pointer;
		}

		.menu-button span {
			display: block;
			width: 17px;
			height: 2px;
			border-radius: 2px;
			background: #245b38;
		}

		.sidebar-close {
			display: grid;
			width: 40px;
			height: 40px;
			padding: 0;
			flex: 0 0 auto;
			place-items: center;
			border: 1px solid rgba(255, 255, 255, 0.16);
			border-radius: 8px;
			background: rgba(255, 255, 255, 0.08);
			color: #f4f8f4;
			font-size: 1.5rem;
			line-height: 1;
			cursor: pointer;
		}

		.backdrop {
			position: fixed;
			z-index: 35;
			inset: 0;
			display: block;
			padding: 0;
			border: 0;
			background: rgba(9, 28, 18, 0.48);
			opacity: 0;
			pointer-events: none;
			transition: opacity 180ms ease;
		}

		.backdrop.visible {
			opacity: 1;
			pointer-events: auto;
		}
	}
</style>
