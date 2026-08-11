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
			errorMessage = 'Supabase environment variables are not configured.';
			return;
		}

		isSubmitting = true;
		const result =
			mode === 'sign-in'
				? await client.auth.signInWithPassword({ email, password })
				: await client.auth.signUp({ email, password });
		isSubmitting = false;

		if (result.error) {
			errorMessage = result.error.message;
			return;
		}

		if (mode === 'sign-up' && !result.data.session) {
			successMessage = 'Check your email to confirm your account, then sign in.';
			mode = 'sign-in';
			return;
		}

		const next = page.url.searchParams.get('next') || '/';
		await goto(next);
	}
</script>

<svelte:head>
	<title>Account | Dreaming Agri</title>
</svelte:head>

<main class="auth-page">
	<section class="auth-panel" aria-labelledby="auth-title">
		<div class="auth-heading">
			<span class="eyebrow">Dreaming Agri</span>
			<h1 id="auth-title">{mode === 'sign-in' ? 'Sign in' : 'Create account'}</h1>
			<p>Use an account to keep farm records private and sync them across sessions.</p>
		</div>

		<form onsubmit={submit}>
			<label for="auth-email">Email</label>
			<input id="auth-email" type="email" bind:value={email} autocomplete="email" required />

			<label for="auth-password">Password</label>
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
				{isSubmitting ? 'Working...' : mode === 'sign-in' ? 'Sign in' : 'Create account'}
			</button>
		</form>

		<button type="button" class="mode-toggle" onclick={() => (mode = mode === 'sign-in' ? 'sign-up' : 'sign-in')}>
			{mode === 'sign-in' ? 'Need an account? Create one' : 'Already have an account? Sign in'}
		</button>
		<a class="back-link" href="/">Back to dashboard</a>
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
		letter-spacing: 0.08em;
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