# Server-only code

Supabase의 권한이 필요한 호출, AI 서비스 호출과 기타 비밀값을 사용하는 코드는 이 경계 또는 SvelteKit의 `*.server.ts` 파일에만 둡니다. 이 폴더의 모듈을 클라이언트 컴포넌트에서 import하지 않습니다.
