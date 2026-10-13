<script lang="ts">
  import '../app.css';
  let { children } = $props();
</script>

<svelte:head><link rel="icon" type="image/svg+xml" href="/practice-favicon.svg" /></svelte:head>
<div class="practice-app">{@render children()}</div>
