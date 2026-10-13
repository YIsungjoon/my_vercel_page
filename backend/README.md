# Shared Supabase Backend

Supabase가 인증, 데이터베이스, 파일 저장소, 실시간 동기화와 서버 측 함수를 담당합니다.

`my_vercel_page`의 모든 서비스가 사용하는 공통 백엔드입니다. 서비스마다 별도의 Supabase 프로젝트나 로컬 스택을 만들지 않고 이 폴더의 설정, 마이그레이션과 Edge Functions를 함께 사용합니다. 농장 프론트엔드는 Vercel의 포털 배포에 포함되며 `/dreaming-agri`에서 실행합니다.

```text
backend/
├─ package.json
└─ supabase/
   ├─ config.toml
   ├─ migrations/
   ├─ functions/
   └─ seed.sql
```

주요 명령:

```bash
npm install
npm run dev
npm run status
npm run db:reset
npm run stop
```

운영 Supabase 프로젝트가 준비되면 `npx supabase link --project-ref <project-id>`로 연결하고, 모든 변경을 마이그레이션으로 검토한 뒤 반영합니다.

연결은 이 `backend/` 폴더에서 한 번 수행합니다. 기존 프로젝트에 연결한 뒤 `npx supabase migration list`로 원격 적용 이력을 확인하고 미적용 마이그레이션을 검토합니다. 기존 22개 마이그레이션은 농장 서비스의 현재 테이블·RPC를 유지하기 위해 그대로 보존합니다.

저장소 루트에서는 `npm run dev:backend`, `status:backend`, `stop:backend`, `test:backend`, `lint:backend`를 사용할 수 있습니다. 로컬 DB 테스트 11개와 스키마 검사는 Docker와 Supabase 로컬 스택이 실행 중이어야 합니다.

## 공통 연결과 서비스별 권한

각 프론트엔드의 로컬 환경 파일과 Vercel 프로젝트에 같은 공통 Supabase 값을 설정합니다.

| 변수 | 사용 위치 |
| --- | --- |
| `SUPABASE_URL` | SvelteKit 서버의 공통 프로젝트 URL |
| `SUPABASE_PUBLISHABLE_KEY` | SvelteKit 서버의 공개 키, 사용자 세션·RLS와 함께 사용 |
| `PUBLIC_SUPABASE_URL` | 브라우저 인증 클라이언트, 서버와 동일한 URL |
| `PUBLIC_SUPABASE_PUBLISHABLE_KEY` | 브라우저에서 사용 가능한 동일 프로젝트 공개 키 |

Supabase CLI는 `backend/supabase/config.toml`을 사용합니다. 통합 앱은 루트 환경변수를 사용하고 독립 실행은 각 프론트엔드 폴더의 환경변수를 사용하므로 백엔드 폴더만 설정해도 모든 앱에 환경변수가 전파되는 것은 아닙니다.

- **인증:** 같은 Supabase Auth의 사용자 계정을 사용합니다. 서비스별 데이터 접근 권한은 해당 서비스의 멤버십과 RLS로 판단합니다. 같은 계정 사용과 도메인 간 자동 로그인은 별개이며, 공통 로그인 세션이 필요하면 도메인·쿠키·인증 콜백 구조를 함께 설계합니다.
- **DB:** 기존 농장 데이터는 `public` 스키마와 `farm_memberships` 기반 권한을 유지합니다. 신규 서비스는 별도 스키마로 구분하고 필요한 객체에만 GRANT와 RLS를 설정합니다. Data API로 공개할 스키마는 로컬 `api.schemas`와 운영 프로젝트의 Exposed schemas에도 등록합니다. [공식 스키마 안내](https://supabase.com/docs/guides/api/using-custom-schemas)
- **Storage:** 신규 서비스는 `<service-id>-<purpose>` 형태의 버킷과 서비스별 Storage RLS를 사용합니다.
- **Edge Functions:** 외부 API·서버 비밀키가 필요한 신규 기능을 이 폴더에서 관리합니다. 신규 함수 이름에 서비스 ID를 포함해 구분하며 기존 `record-weather`, `dispatch-observation-events`의 이름과 호출 경로는 유지합니다.
- **비밀키:** secret/service-role 키는 Edge Functions 등 필요한 서버 환경에서만 사용합니다. 브라우저 변수에 넣지 않습니다. 기존 웹 API는 사용자 세션으로 Supabase를 호출하는 연결 계층으로 유지합니다.

## Auth 주소 설정

현재 로그인 화면이 있는 농장 앱의 로컬 주소는 `http://127.0.0.1:5174`이며 이를 기본 `site_url`로 사용합니다. 로컬 리다이렉트 허용 목록에는 포털(5173)과 농장 앱(5174)의 localhost/127.0.0.1 주소를 등록했습니다.

운영 Supabase Dashboard의 Auth URL Configuration에는 실제 기본 서비스 URL과 서비스별 인증 콜백 URL을 등록합니다. `config.toml` 수정만으로 운영 프로젝트의 Auth 주소가 갱신되는 것은 아닙니다. 새 인증 흐름은 자신의 서비스 콜백 URL을 명시해 기본 Site URL이 다른 서비스로 보내지 않도록 구성합니다. [공식 리다이렉트 안내](https://supabase.com/docs/guides/auth/redirect-urls)

로컬 `project_id = "backend"`는 폴더 이동 이전의 컨테이너·볼륨 식별자를 유지하기 위해 변경하지 않았습니다. 새 위치에서도 기존 로컬 Supabase 데이터와 같은 식별자를 사용합니다.

## 가상농장 날씨 기록

`김제 가상농장`은 전북특별자치도 김제시 좌표에 고정되어 있습니다. `record-weather` Edge Function은 Open-Meteo 현재 날씨를 조회하고 같은 관측 시각의 호출을 중복 없이 `weather_observations`에 저장합니다.

Supabase Cron은 매일 김제 현지시간 00:00, 06:00, 12:00, 18:00에 함수를 호출합니다. Cron 자체는 UTC 기준 `0 3,9,15,21 * * *`로 등록되며 호출 전용 난수 비밀값은 Edge Function 환경과 Supabase Vault에만 보관합니다.

```bash
# 로컬 실행(Docker 필요)
npm run weather:serve

# 연결된 Supabase 프로젝트에 배포
npm run weather:deploy
```

함수에는 `POST` 요청만 허용합니다. 배포 환경에서는 Supabase의 기본 서버용 환경변수를 사용하므로 별도의 날씨 API 키가 필요하지 않습니다.

Cron 호출은 `WEATHER_CRON_SECRET`이 일치할 때만 허용됩니다. 실제 값은 저장소나 일반 환경 파일에 두지 않고 Edge Function Secret과 Vault에서 관리합니다.

## 문제연습 서비스 스키마

문제연습은 같은 프로젝트의 `ai_practice` 스키마를 사용합니다. 과정·과목·단원·문항, 문항 수정 이력, 사용자별 풀이·답안·메모·북마크를 별도로 관리하며 기존 농장 테이블과 권한을 재사용하지 않습니다. 모든 테이블에 RLS가 적용되며 게시 콘텐츠는 공개 조회, 학습 기록은 본인 조회, 콘텐츠 편집은 명시적으로 등록한 staff만 허용합니다.

`202610130001_ai_practice.sql`과 `202610130002_ai_practice_seed.sql`을 적용합니다. 로컬 api.schemas와 5175 Auth 주소는 config.toml에 추가되어 있습니다. 운영 Dashboard의 Exposed schemas에도 `ai_practice`와 실제 서비스 인증 주소를 설정해야 합니다.

[서비스 README](../project/ai-practice/README.md)에 운영 적용 순서와 편집자 등록, 클라우드 저장 방식이 있습니다. 앱의 `npm test`는 별도 PostgreSQL 엔진에서 스키마·RPC·RLS를 검증하며 운영 Supabase 연결을 대신하지 않습니다.
