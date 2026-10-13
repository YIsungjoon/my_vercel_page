# Frontend

Svelte 5와 SvelteKit 기반 웹 애플리케이션입니다. `@sveltejs/adapter-vercel`을 명시적으로 사용합니다.

```bash
cp .env.example .env
npm install
npm run dev
```

Vercel에서는 저장소 기준 `project/dreaming_agri/frontend`를 Root Directory로 지정하고 `.env.example`의 공개 Supabase 변수를 프로젝트 환경변수로 등록합니다. 실제 secret/service-role key와 AI API key에는 `PUBLIC_` 접두사를 사용하지 않습니다.

저장소 루트에서 `npm run dev:agri`를 실행하면 포털(5173)과 겹치지 않는 5174 포트에서 시작합니다. 이 폴더에서 직접 실행할 때는 `npm run dev -- --port 5174 --strictPort`를 사용할 수 있습니다.
