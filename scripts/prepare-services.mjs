import { readdir, readFile, writeFile, mkdir, unlink } from 'node:fs/promises';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = fileURLToPath(new URL('../', import.meta.url));
const frontend = resolve(root, 'project/dreaming_agri/frontend');
const source = resolve(frontend, 'src/routes');
const target = resolve(root, 'src/routes/dreaming-agri');
const manifest = resolve(root, '.svelte-kit/service-routes.json');

async function filesIn(directory) {
	const entries = await readdir(directory, { withFileTypes: true });
	const lists = await Promise.all(entries.map((entry) => {
		const path = resolve(directory, entry.name);
		return entry.isDirectory() ? filesIn(path) : [path];
	}));
	return lists.flat();
}

const routes = await filesIn(source);
const generated = [];
for (const path of routes) {
	const name = relative(source, path).replaceAll('\\', '/');
	if (!/\+(page|layout)\.svelte$|\+(page\.server|server)\.ts$/.test(name)) continue;
	const output = resolve(target, name);
	const imported = relative(dirname(output), path).replaceAll('\\', '/');
	let content;
	if (name.endsWith('+layout.svelte')) {
		content = `<script lang="ts">\n import Layout from '${imported}';\n let { children } = $props();\n</script>\n<Layout {children} />\n`;
	} else if (name.endsWith('+page.svelte')) {
		const hasData = routes.includes(path.replace('+page.svelte', '+page.server.ts'));
		content = `<script lang="ts">\n import Page from '${imported}';\n${hasData ? ' import type { PageData } from \'./$types\';\n let { data }: { data: PageData } = $props();\n' : ''}</script>\n<Page${hasData ? ' {data}' : ''} />\n`;
	} else if (name.endsWith('+page.server.ts')) {
		content = `import { load as loadService } from '${imported}';\nexport const load = ({ locals }: { locals: App.Locals }) => loadService({ locals });\n`;
	} else {
		content = `export * from '${imported}';\n`;
	}
	await mkdir(dirname(output), { recursive: true });
	const previous = await readFile(output, 'utf8').catch(() => '');
	if (previous !== content) await writeFile(output, content);
	generated.push(name);
}

// Delete only previously generated files inside this mount, never service source.
const previous = JSON.parse(await readFile(manifest, 'utf8').catch(() => '[]'));
for (const name of previous) {
	const path = resolve(target, name);
	if (!path.startsWith(target + '/') && !path.startsWith(target + '\\')) throw new Error('Invalid generated route');
	if (!generated.includes(name)) await unlink(path).catch((error) => { if (error.code !== 'ENOENT') throw error; });
}
await mkdir(dirname(manifest), { recursive: true });
await writeFile(manifest, JSON.stringify(generated));
await writeFile(resolve(target, '+layout.ts'), 'export const prerender = false;\n');

// Both apps use the root toolchain; a root-only npm ci is sufficient on Vercel.
const cli = resolve(root, 'node_modules/@sveltejs/kit/svelte-kit.js');
for (const cwd of [frontend, root]) {
	const result = spawnSync(process.execPath, [cli, 'sync'], { cwd, stdio: 'inherit' });
	if (result.status !== 0) process.exit(result.status ?? 1);
}
