# Features

화면이나 기술 계층이 아닌 제품 도메인 단위로 코드를 배치합니다.

예정된 기능 영역은 `farms`, `seasons`, `calendar`, `tasks`, `work-logs`, `assistant`입니다. 각 영역은 필요한 component, state, schema, API 코드를 내부에 함께 두고 여러 기능에서 재사용되는 코드만 상위 `src/lib`로 올립니다.
