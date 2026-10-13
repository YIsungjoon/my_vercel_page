# Frontend

Svelte 5와 SvelteKit 기반 웹 애플리케이션입니다. `@sveltejs/adapter-vercel`을 명시적으로 사용합니다.

백엔드는 저장소 최상위 `backend/`의 공통 Supabase를 사용합니다. 다른 서비스와 동일한 Supabase URL과 publishable key를 `.env.example`의 서버·브라우저 변수에 설정합니다. 상세 설정은 [공통 백엔드 안내](../../../backend/README.md)를 참고하세요.

```bash
cp .env.example .env
npm install
npm run dev
```

운영은 저장소 루트에서 포털과 함께 빌드·배포하며 `/dreaming-agri` 경로로 제공합니다. 루트 `.env.example`의 Supabase 변수를 기존 Vercel 프로젝트에 등록합니다. 실제 secret/service-role key와 AI API key에는 `PUBLIC_` 접두사를 사용하지 않습니다.

저장소 루트에서 `npm run dev:agri`를 실행하면 포털(5173)과 겹치지 않는 5174 포트에서 시작합니다. 이 폴더에서 직접 실행할 때는 `npm run dev -- --port 5174 --strictPort`를 사용할 수 있습니다.
