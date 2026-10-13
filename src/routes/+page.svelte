<script lang="ts">
	import Icon from '$lib/components/Icon.svelte';
	import { categories, services } from '$lib/services';

	let query = $state('');
	let category = $state('전체');
	const filteredServices = $derived(services.filter((service) => {
		const searchable = [service.name, service.kicker, service.description, service.category, ...service.tags]
			.join(' ').toLocaleLowerCase();
		return (category === '전체' || service.category === category)
			&& searchable.includes(query.trim().toLocaleLowerCase());
	}));

	function resetFilters() {
		query = '';
		category = '전체';
	}
</script>

<svelte:head>
	<title>서비스 목록 · My Vercel Page</title>
	<meta name="description" content="Dreaming Agri를 비롯한 웹 서비스 목록과 바로가기." />
</svelte:head>

<a class="skip-link" href="#main">본문으로 바로가기</a>

<div class="workspace">
	<aside class="sidebar" aria-label="서비스 탐색">
		<a class="brand" href="/" aria-label="My Vercel Page 홈">
			<span class="brand-mark"><Icon name="grid" size={20} /></span>
			<span>My Services<span class="brand-caption">YIsungjoon</span></span>
		</a>

		<nav class="overview-nav" aria-label="주 메뉴">
			<a class="nav-item active" href="#services" aria-current="page">
				<Icon name="grid" size={19} />
				<span>전체 서비스</span>
				<span class="nav-count">{services.length}</span>
			</a>
		</nav>

		<nav class="service-nav" aria-labelledby="sidebar-services-title">
			<h2 id="sidebar-services-title" class="sidebar-label">서비스 바로가기</h2>
			<ul>
				{#each services as service (service.id)}
					<li>
						{#if service.href}
							<a class="nav-service" href={service.href}>
								<span class="nav-service-icon"><Icon name={service.icon ?? 'grid'} size={19} /></span>
								<span class="nav-service-name">{service.name}</span>
								<Icon name="external" size={15} />
							</a>
						{:else}
							<span class="nav-service unavailable" aria-disabled="true">
								<span class="nav-service-icon"><Icon name={service.icon ?? 'grid'} size={19} /></span>
								<span class="nav-service-name">{service.name}<span class="nav-service-note">연결 준비 중</span></span>
							</span>
						{/if}
					</li>
				{/each}
			</ul>
		</nav>

		<div class="sidebar-footer">
			<a class="repository-link" href="https://github.com/YIsungjoon/my_vercel_page" target="_blank" rel="noreferrer">
				<Icon name="github" size={18} />
				<span>GitHub 저장소</span>
				<Icon name="external" size={14} />
				<span class="sr-only"> (새 탭)</span>
			</a>
		</div>
	</aside>

	<div class="page-body">
		<header class="topbar">
			<span>My Vercel Page</span>
			<span class="topbar-owner">YIsungjoon</span>
		</header>
		<main id="main" tabindex="-1">
			<section id="services" aria-labelledby="services-title">
				<div class="page-heading">
					<div>
						<h1 id="services-title">서비스 목록 <span>{services.length}</span></h1>
						<p>사용할 서비스를 선택하세요.</p>
					</div>
					<div class="search-field">
						<Icon name="search" size={19} />
						<label class="sr-only" for="service-search">서비스 검색</label>
						<input id="service-search" type="search" bind:value={query} placeholder="이름 또는 기능 검색" autocomplete="off" />
						{#if query}
							<button class="clear-search" type="button" aria-label="검색어 지우기" onclick={() => query = ''}>
								<Icon name="close" size={17} />
							</button>
						{/if}
					</div>
				</div>

				<div class="filter-row">
					<div class="category-list" role="group" aria-label="서비스 분류">
						{#each ['전체', ...categories] as item}
							<button type="button" class:selected={category === item} aria-pressed={category === item} onclick={() => category = item}>{item}</button>
						{/each}
					</div>
					<span class="result-count" role="status" aria-live="polite">{filteredServices.length}개 서비스</span>
				</div>

				{#if filteredServices.length}
					<ul class="service-list" aria-label="서비스 목록">
						{#each filteredServices as service (service.id)}
							<li>
								<article class="service-card" aria-labelledby={`title-${service.id}`}>
									<span class="service-icon" aria-hidden="true"><Icon name={service.icon ?? 'grid'} size={29} /></span>
									<div class="service-content">
										<p class="service-category">{service.category}</p>
										<h2 id={`title-${service.id}`}>{service.name}</h2>
										<p class="service-description">{service.description}</p>
										<ul class="tags" aria-label="주요 기능">
											{#each service.tags as tag}<li>{tag}</li>{/each}
										</ul>
									</div>
									<div class="service-actions">
										{#if service.href}
											<a class="open-service" href={service.href}>서비스 열기 <Icon name="arrow" size={18} /></a>
										{:else}
											<span class="connection-pending">연결 준비 중</span>
										{/if}
										<a class="source-link" href={service.sourceUrl} target="_blank" rel="noreferrer" aria-label={`${service.name} 소스 코드 (새 탭)`}>
											<Icon name="github" size={16} /> 소스 코드 <Icon name="external" size={13} />
										</a>
									</div>
								</article>
							</li>
						{/each}
					</ul>
				{:else}
					<div class="empty-state">
						<Icon name="search" size={28} />
						<h2>검색 결과가 없습니다.</h2>
						<p>검색어나 분류를 변경해 보세요.</p>
						<button type="button" onclick={resetFilters}>전체 서비스 보기 <Icon name="arrow" size={16} /></button>
					</div>
				{/if}
			</section>
			<footer class="footer">© {new Date().getFullYear()} YIsungjoon</footer>
		</main>
	</div>
</div>
