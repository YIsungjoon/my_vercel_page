# Backend

Supabase가 인증, 데이터베이스, 파일 저장소, 실시간 동기화와 서버 측 함수를 담당합니다.

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
