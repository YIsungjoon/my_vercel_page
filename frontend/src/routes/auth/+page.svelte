<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { getSupabaseBrowserClient } from '$lib/supabaseClient';

	let mode = $state<'sign-in' | 'sign-up'>('sign-in');
	let email = $state('');
	let password = $state('');
	let isSubmitting = $state(false);
	let errorMessage = $state('');
	let successMessage = $state('');

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		errorMessage = '';
		successMessage = '';

		const client = getSupabaseBrowserClient();
		if (!client) {
			errorMessage = '로그인 서비스가 설정되지 않았습니다. 관리자에게 문의해주세요.';
			return;
		}

		isSubmitting = true;
		const result =
			mode === 'sign-in'
				? await client.auth.signInWithPassword({ email, password })
				: await client.auth.signUp({ email, password });
		isSubmitting = false;

		if (result.error) {
			errorMessage =
				mode === 'sign-in'
					? '이메일 또는 비밀번호를 확인해주세요.'
					: '계정을 만들지 못했습니다. 입력 정보를 확인해주세요.';
			return;
		}

		if (mode === 'sign-up' && !result.data.session) {
			successMessage = '확인 메일을 보냈습니다. 이메일 인증을 완료한 뒤 로그인해주세요.';
			mode = 'sign-in';
			return;
		}

		const next = page.url.searchParams.get('next') || '/';
		await goto(next);
	}
</script>

<svelte:head>
	<title>로그인 | Dreaming Agri</title>
</svelte:head>

<main class="auth-page">
	<section class="auth-panel" aria-labelledby="auth-title">
		<div class="auth-heading">
			<span class="eyebrow">Dreaming Agri</span>
			<h1 id="auth-title">{mode === 'sign-in' ? '로그인' : '계정 만들기'}</h1>
			<p>농장 기록을 안전하게 보관하고 작업 현황을 이어서 관리합니다.</p>
		</div>

		<form onsubmit={submit}>
			<label for="auth-email">이메일</label>
			<input id="auth-email" type="email" bind:value={email} autocomplete="email" required />

			<label for="auth-password">비밀번호</label>
			<input
				id="auth-password"
				type="password"
				bind:value={password}
				autocomplete={mode === 'sign-in' ? 'current-password' : 'new-password'}
				minlength="6"
				required
			/>

			{#if errorMessage}
				<p class="message error" role="alert">{errorMessage}</p>
			{/if}
			{#if successMessage}
				<p class="message success" role="status">{successMessage}</p>
			{/if}

			<button type="submit" disabled={isSubmitting}>
				{isSubmitting ? '처리 중...' : mode === 'sign-in' ? '로그인' : '계정 만들기'}
			</button>
		</form>

		<button type="button" class="mode-toggle" onclick={() => (mode = mode === 'sign-in' ? 'sign-up' : 'sign-in')}>
			{mode === 'sign-in' ? '계정이 없으신가요? 계정 만들기' : '이미 계정이 있으신가요? 로그인'}
		</button>
		<a class="back-link" href="/">대시보드로 돌아가기</a>
	</section>
</main>

<style>
	.auth-page {
		display: grid;
		min-height: 100vh;
		padding: 48px 24px;
		place-items: center;
		background: #eef5ef;
	}

	.auth-panel {
		width: min(100%, 440px);
		padding: 40px;
		border: 1px solid #d8e4da;
		border-radius: 8px;
		background: #fff;
		box-shadow: 0 18px 50px rgba(18, 51, 34, 0.1);
	}

	.auth-heading {
		margin-bottom: 28px;
	}

	.eyebrow {
		color: #39774a;
		font-size: 0.75rem;
		font-weight: 700;
		letter-spacing: 0;
		text-transform: uppercase;
	}

	h1 {
		margin: 8px 0;
		color: #173b27;
		font-size: 2rem;
	}

	.auth-heading p {
		margin: 0;
		color: #5b6f61;
		line-height: 1.6;
	}

	form {
		display: grid;
		gap: 10px;
	}

	label {
		margin-top: 8px;
		color: #294735;
		font-size: 0.9rem;
		font-weight: 700;
	}

	input {
		width: 100%;
		padding: 12px 14px;
		border: 1px solid #c9d8cc;
		border-radius: 4px;
		font: inherit;
	}

	input:focus {
		border-color: #39774a;
		outline: 3px solid rgba(57, 119, 74, 0.14);
	}

	form button {
		margin-top: 14px;
		padding: 12px 16px;
		border: 0;
		border-radius: 4px;
		background: #245d3a;
		color: #fff;
		font: inherit;
		font-weight: 700;
		cursor: pointer;
	}

	form button:disabled {
		opacity: 0.6;
		cursor: wait;
	}

	.mode-toggle,
	.back-link {
		display: block;
		margin: 18px auto 0;
		color: #39774a;
		font: inherit;
		font-size: 0.9rem;
		text-align: center;
	}

	.mode-toggle {
		padding: 0;
		border: 0;
		background: transparent;
		cursor: pointer;
	}

	.back-link {
		margin-top: 12px;
		text-decoration: none;
	}

	.message {
		margin: 10px 0 0;
		font-size: 0.85rem;
		line-height: 1.5;
	}

	.error {
		color: #a33b32;
	}

	.success {
		color: #39774a;
	}

	@media (max-width: 520px) {
		.auth-panel {
			padding: 28px 22px;
		}
	}
</style>
