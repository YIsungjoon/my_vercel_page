<script lang="ts">
	import favicon from '$agri/assets/favicon.svg';
	import { page } from '$app/state';
	import AppSidebar from '$agri/components/AppSidebar.svelte';
	import '../app.css';
	import { appPath } from '$agri/paths';

	let { children } = $props();
	const isAuthRoute = $derived(page.url.pathname.startsWith(appPath('/auth')));
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
	<title>Dreaming Agri</title>
	<meta
		name="description"
		content="가상 환경데이터를 농작업 계획과 기록으로 연결하는 예측형 농장 운영관리 플랫폼"
	/>
</svelte:head>

<div class="agri-app">
	{#if !isAuthRoute}
		<AppSidebar />
	{/if}
	<div class="app-content" class:auth-content={isAuthRoute}>
		{@render children()}
	</div>
</div>

<style>
	.app-content {
		min-width: 0;
		margin-left: var(--sidebar-width);
	}

	.app-content.auth-content {
		margin-left: 0;
	}

	@media (max-width: 960px) {
		.app-content {
			margin-left: 0;
		}
	}
</style>
