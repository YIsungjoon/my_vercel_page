<script lang="ts">
	let { name, size = 20 }: { name: 'grid' | 'arrow' | 'search' | 'github' | 'sprout' | 'plus' | 'close' | 'chevron' | 'external'; size?: number } = $props();
</script>

<svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
	{#if name === 'grid'}
		<rect x="3.5" y="3.5" width="6" height="6" rx="1.2" /><rect x="14.5" y="3.5" width="6" height="6" rx="1.2" /><rect x="3.5" y="14.5" width="6" height="6" rx="1.2" /><rect x="14.5" y="14.5" width="6" height="6" rx="1.2" />
	{:else if name === 'arrow'}
		<path d="M5 12h14M13 6l6 6-6 6" />
	{:else if name === 'external'}
		<path d="M7 17 17 7M7 7h10v10" />
	{:else if name === 'search'}
		<circle cx="10.5" cy="10.5" r="6.5" /><path d="m16 16 4.5 4.5" />
	{:else if name === 'github'}
		<path d="M9 19c-4.3 1.3-4.3-2.2-6-2.7m12 5v-3.8c0-1 .1-1.5-.5-2.1 3.3-.4 6.7-1.6 6.7-7.3 0-1.6-.5-2.9-1.5-4 .2-.5.7-2-.2-4 0 0-1.2-.4-4 1.5a13.7 13.7 0 0 0-7 0C5.7-.3 4.5.1 4.5.1c-.9 2-.4 3.5-.2 4C3.3 5.2 2.8 6.5 2.8 8.1c0 5.7 3.4 6.9 6.7 7.3-.6.6-.6 1.4-.5 2.1v3.8" transform="translate(1 1) scale(.9)" />
	{:else if name === 'sprout'}
		<path d="M12 21v-9M12 14C5 14 3 9 3 4c6 0 9 3 9 10ZM12 11c0-5 3-8 9-8 0 6-3 10-9 10" />
	{:else if name === 'plus'}
		<path d="M12 5v14M5 12h14" />
	{:else if name === 'close'}
		<path d="m6 6 12 12M6 18 18 6" />
	{:else}
		<path d="m9 5 7 7-7 7" />
	{/if}
</svg>
