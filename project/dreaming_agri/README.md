# Dreaming Agri

`my_vercel_page` 저장소의 독립 프론트엔드 프로젝트입니다. 위치는 `project/dreaming_agri/`이며, 저장소 루트에서는 서비스 포털을 운영합니다. Supabase는 저장소 최상위 `backend/`에서 모든 서비스가 공유합니다. 아래 명령은 이 프로젝트 폴더를 기준으로 실행합니다.

가상 환경데이터를 농장의 생육 상태, 작업 일정, 준비 자원과 작업 기록으로 연결하는 예측형 농장 운영관리 MVP입니다.

프론트엔드와 AI 모듈은 이 프로젝트에 두고, DB와 Edge Functions는 공통 백엔드에서 관리합니다.

```text
dreaming_agri/
├─ frontend/              # Svelte 5 + SvelteKit, Vercel 배포
├─ ai/                    # 가상데이터, 일정 예측, RAG, 이미지 분석
├─ docs/                  # 아키텍처와 개발 규칙
└─ ref/                   # 기획 원문 PDF
```

## 빠른 시작

요구사항은 Node.js 20 이상, npm, Docker 호환 런타임입니다.

```bash
# 프런트엔드
npm --prefix frontend install
npm run dev:frontend

# Supabase 로컬 스택 (별도 터미널)
npm --prefix ../../backend install
npm run dev:backend
```

프런트엔드는 `http://localhost:5174`, Supabase Studio는 `http://localhost:54323`에서 확인합니다. `npm run dev:backend`가 출력하는 로컬 URL과 publishable key를 `frontend/.env.example`을 참고해 `frontend/.env`에 설정합니다. 저장소 루트에서 실행하는 포털은 `http://localhost:5173`을 사용합니다.

Vercel의 Supabase Integration을 사용하는 경우 `frontend`에서 `npx vercel link`와 `npx vercel env pull .env.development.local`을 실행하면 서버 전용 `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`를 사용할 수 있습니다.

## 배포 경계

- 운영은 저장소 루트의 포털과 함께 배포하며 `/dreaming-agri`에서 실행합니다. 별도 농장 Vercel 프로젝트는 필요하지 않습니다.
- Supabase 스키마 변경은 저장소 루트의 `backend/supabase/migrations`에 SQL 마이그레이션으로 기록합니다. 모든 서비스가 동일한 Supabase 프로젝트에 연결됩니다.
- 브라우저에는 Supabase publishable key만 노출합니다. secret/service-role key와 AI 제공자 키는 서버 전용 환경변수로 관리합니다.
- AI 실행 환경은 모델과 처리시간이 정해진 뒤 선택합니다. 프런트엔드가 AI 제공자를 직접 호출하지 않도록 유지합니다.

문서:

- [공통 Supabase 백엔드](../../backend/README.md)

- [초기 설정 작업 기록](docs/initial-setup.md)
- [아키텍처와 MVP 데이터 흐름](docs/architecture.md)
