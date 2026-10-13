import adapter from '@sveltejs/adapter-vercel';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';

export default defineConfig({
	define: { 'import.meta.env.VITE_DREAMING_AGRI_BASE_PATH': JSON.stringify('/dreaming-agri') },
	resolve: { dedupe: ['svelte'] },
	server: {
		watch: { ignored: ['**/backend/**', '**/project/**/.svelte-kit/**', '**/project/**/.vercel/**'] }
	},
	plugins: [
		sveltekit({
			alias: {
				$agri: fileURLToPath(new URL('./project/dreaming_agri/frontend/src/lib', import.meta.url)),
				$practice: fileURLToPath(new URL('./project/ai-practice/src/lib', import.meta.url))
			},
			compilerOptions: {
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},
			adapter: adapter()
		})
	]
});
