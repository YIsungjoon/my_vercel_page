# My Vercel Page

여러 웹 서비스를 프로젝트별로 관리하는 저장소입니다. 최상위 Svelte 5 + SvelteKit 앱은 사이드바의 서비스 바로가기와 검색 가능한 서비스 목록을 제공하는 포털이며, 개별 서비스는 `project/<프로젝트명>/` 안에서 독립적으로 실행하고 배포합니다.

저장소: [YIsungjoon/my_vercel_page](https://github.com/YIsungjoon/my_vercel_page)

```text
my_vercel_page/
├─ src/                          # 서비스 포털
│  ├─ lib/services.ts             # 서비스 이름, 설명, 분류, 이동 주소
│  └─ routes/+page.svelte         # 포털 첫 화면
├─ static/                       # 포털 정적 자산
├─ package.json                  # 포털 및 개별 서비스 실행 명령
├─ vercel.json                   # 포털 Vercel 설정
└─ project/
   └─ dreaming_agri/             # 기존 농장 운영관리 프로젝트 전체
      ├─ frontend/               # SvelteKit 앱
      ├─ backend/                # Supabase
      ├─ ai/                     # 예측, RAG, 이미지 분석
      ├─ docs/                   # 기존 로컬 개발 기록 (Git 제외)
      ├─ ref/                    # 기획 자료
      ├─ package.json
      └─ README.md
```

## 로컬 실행

Node.js 22.12 이상과 npm을 사용합니다. 루트와 각 프로젝트는 별도의 의존성과 잠금 파일을 유지합니다.

```bash
# 최상위 서비스 포털: http://localhost:5173
npm ci
npm run dev

# 다른 터미널: Dreaming Agri http://localhost:5174
npm run install:agri
npm run dev:agri

# Supabase 로컬 스택: Docker 호환 런타임 필요
npm run dev:backend
```

포털의 로컬 기본 이동 주소는 `http://localhost:5174`입니다. 포털과 농장 앱을 함께 실행한 뒤 `서비스 바로가기`를 누릅니다. 기존 `npm run dev:frontend`, `dev:backend`, `stop:backend` 명령도 새 폴더를 가리킵니다.

Dreaming Agri의 환경 파일은 `project/dreaming_agri/frontend/`에서 관리합니다. 프로젝트 자체의 실행 방법은 [프로젝트 README](project/dreaming_agri/README.md)를 참고하세요.

```bash
npm run check          # 포털 타입·접근성 검사
npm run check:agri     # 농장 앱 타입·접근성 검사
npm run check:all      # 두 앱 검사
npm run build          # 포털 Vercel 빌드
npm run build:agri      # 농장 앱 Vercel 빌드
```

## Vercel 배포

같은 저장소에서 앱마다 별도의 Vercel 프로젝트를 연결합니다.

| 앱 | Root Directory | Framework | 설치 / 빌드 |
| --- | --- | --- | --- |
| 서비스 포털 | 저장소 루트 (`.`) | SvelteKit | `npm ci` / `npm run build` |
| Dreaming Agri | `project/dreaming_agri/frontend` | SvelteKit | `npm ci` / `npm run build` |

**기존 Dreaming Agri Vercel 프로젝트의 Root Directory를 `frontend`에서 `project/dreaming_agri/frontend`로 변경해야 합니다.** GitHub 연결도 이름을 변경한 저장소 `YIsungjoon/my_vercel_page`를 가리키는지 확인합니다. 기존 농장 앱의 환경변수는 해당 Vercel 프로젝트에서 계속 관리합니다.

포털 Vercel 프로젝트에 `VITE_DREAMING_AGRI_URL`을 농장 앱의 실제 운영 URL로 설정하고 빌드합니다. 루트 `.env.example`에 변수 이름이 있습니다. 이 변수는 공개 이동 주소이며 빌드 결과에 포함됩니다. 값이 비어 있는 운영 빌드에서는 잘못된 주소로 이동시키지 않고 `연결 준비` 상태를 표시합니다. 값을 변경하면 포털을 다시 빌드합니다.

포털은 사전 렌더링하며 Supabase나 AI 키를 사용하지 않습니다. 비밀키에는 `VITE_` 또는 `PUBLIC_` 접두사를 붙이지 않습니다.

## 서비스 추가 및 프론트 규칙

1. `project/<프로젝트명>/`에 앱, 의존성, 환경변수 예시와 README를 둡니다.
2. `src/lib/services.ts`의 `services` 배열에 고유 ID, 이름, 설명, 분류, 태그와 실제 이동 URL을 추가합니다. 사이드바 바로가기, 서비스 목록, 분류 버튼과 개수는 이 목록에서 생성됩니다. 서비스 아이콘은 `icon`으로 지정할 수 있으며 기본값은 `grid`입니다.
3. 별도 Vercel 프로젝트를 만들고 해당 앱의 폴더를 Root Directory로 지정합니다.
4. 한국어 제품 문구, Svelte 5 runes, TypeScript strict 설정을 따릅니다. 320px 이상 모바일에서 가로 넘침이 없어야 하며 검색 입력 label, 키보드 포커스, 44px 터치 영역, 동작 감소 설정을 제공합니다.

각 프로젝트 내부의 코드와 환경변수는 해당 프로젝트에서 관리하고, 포털은 서비스 목록과 탐색만 담당합니다. Git 이력과 공통 Git 설정은 저장소 루트에 유지합니다.
