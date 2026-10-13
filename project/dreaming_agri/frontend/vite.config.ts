import adapter from '@sveltejs/adapter-vercel';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';

export default defineConfig({
	plugins: [
		sveltekit({
			alias: { $agri: fileURLToPath(new URL('./src/lib', import.meta.url)) },
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},

			// Keep the deployment target explicit so local and Vercel builds use the same adapter.
			adapter: adapter()
		})
	]
});
