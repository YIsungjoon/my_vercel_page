# My Vercel Page

여러 웹 서비스를 프로젝트별로 관리하는 저장소입니다. 최상위 Svelte 5 + SvelteKit 앱은 사이드바의 서비스 바로가기와 검색 가능한 서비스 목록을 제공하는 포털이며, 개별 서비스 코드는 `project/<프로젝트명>/`에서 관리합니다. Dreaming Agri는 같은 포털의 `/dreaming-agri` 경로에서 실행하고 함께 배포합니다.

모든 서비스의 인증, 데이터베이스, 파일 저장소, 실시간 데이터와 Edge Functions는 **하나의 공통 Supabase 프로젝트**에서 관리합니다. Supabase CLI 설정과 전체 마이그레이션은 최상위 `backend/`가 담당합니다.

저장소: [YIsungjoon/my_vercel_page](https://github.com/YIsungjoon/my_vercel_page)

```text
my_vercel_page/
├─ src/                          # 서비스 포털
│  ├─ lib/services.ts             # 서비스 이름, 설명, 분류, 이동 주소
│  └─ routes/+page.svelte         # 포털 첫 화면
├─ static/                       # 포털 정적 자산
├─ package.json                  # 포털 및 개별 서비스 실행 명령
├─ vercel.json                   # 포털 Vercel 설정
├─ backend/                      # 모든 서비스가 공유하는 Supabase 백엔드
│  └─ supabase/                  # 공통 설정, migrations, functions, DB tests
└─ project/
   └─ dreaming_agri/             # 농장 서비스 프론트엔드와 AI 모듈
      ├─ frontend/               # SvelteKit 앱
      ├─ ai/                     # 예측, RAG, 이미지 분석
      ├─ docs/                   # 기존 로컬 개발 기록 (Git 제외)
      ├─ ref/                    # 기획 자료
      ├─ package.json
      └─ README.md
```

## 로컬 실행

Node.js 22.12 이상과 npm을 사용합니다. 포털, 공통 백엔드와 각 프론트엔드는 별도의 의존성과 잠금 파일을 유지합니다.

```bash
# 포털과 Dreaming Agri: http://localhost:5173/dreaming-agri
npm ci
npm run dev

# 농장 앱만 별도로 개발할 경우: http://localhost:5174
npm run install:agri
npm run dev:agri

# Supabase 로컬 스택: Docker 호환 런타임 필요
npm run install:backend
npm run dev:backend
```

포털에서 `서비스 바로가기`를 누르면 `/dreaming-agri`로 이동합니다. 포털 실행만으로 농장 화면과 `/dreaming-agri/api/*` 서버 API를 함께 사용할 수 있습니다. 기존 `npm run dev:frontend`, `dev:backend`, `stop:backend` 명령도 새 폴더를 가리킵니다.

로컬 Supabase는 서비스마다 띄우지 않고 한 번만 실행합니다. `npm run status:backend`로 상태를 확인하고 `npm run stop:backend`로 종료합니다. 농장 프로젝트 안의 `dev:backend`와 `stop:backend`도 같은 최상위 백엔드를 가리킵니다.

통합 실행은 루트 `.env`를 사용합니다. `.env.example`을 복사해 공통 Supabase URL과 공개 키를 설정합니다. 농장 앱만 별도로 실행할 때는 `project/dreaming_agri/frontend/`의 환경 파일을 사용합니다. 프로젝트 자체의 실행 방법은 [프로젝트 README](project/dreaming_agri/README.md)를 참고하세요.

```bash
npm run check          # 포털 타입·접근성 검사
npm run check:agri     # 농장 앱 타입·접근성 검사
npm run check:all      # 두 앱 검사
npm run build          # 포털 Vercel 빌드
npm run build:agri      # 농장 앱 Vercel 빌드
npm run test:backend    # 공통 Supabase DB 테스트 (로컬 스택 필요)
npm run lint:backend    # 공통 DB 스키마 검사 (로컬 스택 필요)
```

## Vercel 배포

기존 `my_vercel_page` Vercel 프로젝트 하나에 저장소 루트(`.`)를 연결합니다. 설치는 `npm ci`, 빌드는 `npm run build`입니다. GitHub 연결은 `YIsungjoon/my_vercel_page`를 사용합니다.

| 경로 | 기능 |
| --- | --- |
| `/` | 서비스 포털 |
| `/dreaming-agri` | 농장 서비스 |
| `/ai-practice` | 문제연습 서비스 |
| `/dreaming-agri/auth` | 농장 로그인 |
| `/dreaming-agri/api/*` | 농장 서버 API |

농장 앱을 위한 별도 배포나 `VITE_DREAMING_AGRI_URL` 설정은 필요하지 않습니다. `scripts/prepare-services.mjs`가 농장 소스를 참조하는 경로 어댑터를 생성하고 두 앱의 타입을 준비합니다. 생성된 `src/routes/dreaming-agri/`는 Git에서 제외하며 서비스 원본을 복사하지 않습니다. 루트 의존성만 설치해도 통합 빌드가 가능합니다.

Vercel 환경변수에는 아래 공통 Supabase 서버·브라우저 변수를 설정합니다. 비밀키에는 `VITE_` 또는 `PUBLIC_` 접두사를 붙이지 않습니다. 포털 첫 화면은 계속 사전 렌더링하고 농장 화면과 API는 서버에서 실행합니다.

## 공통 Supabase 연결

모든 서비스의 환경변수는 동일한 Supabase 프로젝트를 가리켜야 합니다. 서버의 `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY`와 브라우저의 `PUBLIC_SUPABASE_URL` / `PUBLIC_SUPABASE_PUBLISHABLE_KEY`에 같은 프로젝트의 URL과 공개 키를 설정합니다. 포털 통합 실행은 루트 환경변수를 사용하고 독립 실행은 해당 프론트엔드 폴더의 환경변수를 사용합니다. 백엔드 폴더의 환경변수를 자동으로 읽지는 않습니다.

기존 농장 테이블, RPC, RLS와 함수 이름은 유지합니다. 신규 서비스의 데이터 구조와 권한은 공통 마이그레이션에서 관리하며, 기존 `farm_memberships`를 다른 서비스의 권한으로 재사용하지 않습니다. 계정은 같은 Supabase Auth를 사용하되 도메인이 다른 서비스의 로그인 세션은 자동 공유되지 않습니다.

운영 프로젝트 연결, 서비스별 데이터·파일 권한과 배포 순서는 [공통 백엔드 안내](backend/README.md)를 참고하세요.

## 서비스 추가 및 프론트 규칙

1. `project/<프로젝트명>/`에 앱, 의존성, 환경변수 예시와 README를 둡니다.
2. `src/lib/services.ts`의 `services` 배열에 고유 ID, 이름, 설명, 분류, 태그와 실제 이동 URL을 추가합니다. 사이드바 바로가기, 서비스 목록, 분류 버튼과 개수는 이 목록에서 생성됩니다. 서비스 아이콘은 `icon`으로 지정할 수 있으며 기본값은 `grid`입니다.
3. 같은 포털에 포함할 서비스는 고유 경로 아래에 화면과 API를 연결하고 해당 내부 경로를 이동 주소로 등록합니다. 백엔드는 기존 공통 Supabase에 연결하고 DB 변경은 `backend/supabase/migrations/`에 추가합니다.
4. 한국어 제품 문구, Svelte 5 runes, TypeScript strict 설정을 따릅니다. 320px 이상 모바일에서 가로 넘침이 없어야 하며 검색 입력 label, 키보드 포커스, 44px 터치 영역, 동작 감소 설정을 제공합니다.

각 프로젝트의 프론트엔드 코드와 환경변수는 해당 프로젝트에서, 모든 Supabase 백엔드 코드는 최상위 `backend/`에서 관리합니다. Git 이력과 공통 Git 설정은 저장소 루트에 유지합니다.

## 문제연습 서비스

`project/ai-practice`는 과정별 문제은행, 풀이, 모의고사와 오답 복습을 제공합니다. 첫 콘텐츠는 AI 역량평가 연습 36문항이며 자격증·공무원 시험 과정을 추가할 수 있습니다.

```bash
npm run install:practice
npm run dev:practice       # http://localhost:5175
npm run check:practice
npm run test:practice
npm run build:practice
```

문제연습은 포털과 함께 배포하며 `/ai-practice`에서 실행합니다. 별도 배포 주소 설정은 필요하지 않습니다. 공통 Supabase의 `ai_practice` 스키마를 사용하며 마이그레이션은 `backend/supabase/migrations/202610130001_ai_practice.sql`과 `202610130002_ai_practice_seed.sql`입니다. 운영 DB에 두 파일을 적용하고 Exposed schemas와 Auth 리다이렉트를 설정해야 클라우드 기능이 동작합니다.

과정 추가 형식, 환경변수, DB 구조와 권한은 [서비스 안내](project/ai-practice/README.md)를 참고하세요.
