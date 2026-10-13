<script lang="ts">
  let { name, size = 20 }: { name: string; size?: number } = $props();
  const paths: Record<string,string> = {
    home:'M3 10 12 3l9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1z',
    book:'M4 4h6a3 3 0 0 1 3 3v14a4 4 0 0 0-4-2H4zM13 7a3 3 0 0 1 3-3h5v15h-4a4 4 0 0 0-4 2',
    clock:'M12 8v5l3 2M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0',
    bookmark:'M6 3h12v18l-6-4-6 4z',
    settings:'M4 7h16M4 17h16M8 4v6M16 14v6',
    arrow:'M5 12h14m-5-5 5 5-5 5',
    back:'M19 12H5m5-5-5 5 5 5',
    search:'M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0',
    check:'m5 12 4 4L19 6',
    close:'m6 6 12 12M6 18 18 6',
    spark:'m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5z',
    message:'M21 11a8 8 0 0 1-8 8H7l-5 3 2-6a8 8 0 1 1 17-5M8 9h8M8 13h5',
    layers:'m12 3 10 5-10 5L2 8zM2 12l10 5 10-5M2 16l10 5 10-5',
    chart:'M4 3v18h17M8 16v-5M13 16V7M18 16v-3',
    shield:'m12 3 9 4v5c0 5-5 8-9 10-4-2-9-5-9-10V7zM8 12l3 3 5-6',
    flag:'M5 22V3h14l-3 4 3 4H5',
    download:'M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5',
    upload:'M12 16V4m-5 5 5-5 5 5M4 16v5h16v-5',
    user:'M20 21v-2a6 6 0 0 0-6-6h-4a6 6 0 0 0-6 6v2M16 6a4 4 0 1 1-8 0 4 4 0 0 1 8 0',
    cloud:'M7 18H6a5 5 0 0 1 0-10 7 7 0 0 1 13-1 5 5 0 0 1-1 11h-1M12 12v9m-3-6 3-3 3 3',
    target:'M22 12a10 10 0 1 1-10-10M18 12a6 6 0 1 1-6-6m0 6 9-9M16 3h5v5',
    list:'M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01',
    info:'M12 11v6M12 7h.01M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0'
  };
</script>
<svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d={paths[name] ?? paths.book} /></svg>
