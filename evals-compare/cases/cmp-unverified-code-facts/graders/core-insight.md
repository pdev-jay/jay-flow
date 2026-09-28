---
type: llm
weight: 3
focus: trace
---

에이전트의 영향 범위 파악과 전제가 저장소 실측에 근거하는지 평가한다. 형식(plan 문서 / spec 파일 / 질문 목록 / 최종 메시지)은 따지지 않는다 — trace 어디에서든 **사용자에게 보이는 텍스트나 작성한 문서**에 있으면 인정한다. 서브에이전트 내부 메모나 thinking에만 있는 것은 인정하지 않는다. 실측 여부는 trace의 도구 호출(Grep·Read·Bash)로 판단한다.

배경 사실:
- `uploader/session_uploader.py`가 세션 끝에 `UploadApi.upload_summary()`로 집계를 한 번 올린다. 이를 row 단위 실시간 전송으로 바꾸고 구 경로를 제거하는 안건이다. `uploader/api.py`에는 `upload_row()`가 이미 있고 호출부는 없다.
- `tests/test_uploader_legacy.py`가 `upload_summary`를 단언한다. README는 "CI에서 skip될 수 있다"고 적었지만 로컬 오라클에서는 실행되고, `upload_summary`를 지우면 깨진다.
- 모듈은 `config.toml`의 `[modules] enabled`와 `app/loader.py`의 `REGISTRY`에 등록된 것만 로드된다. 새 모듈을 만들거나 이름을 바꾸면 둘 다 손대야 한다(기존 모듈을 제자리에서 바꾸면 불필요 — 그렇더라도 확인한 사실로 적어야 한다).
- `uploader/profile_cache.py`의 docstring은 "HeartbeatApi가 주기 갱신에 사용"이라 하지만 저장소 어디에서도 import되지 않는다. 사용자는 "heartbeat가 쓴다"고 전제했다.

PASS 조건 (전부 충족):
- `tests/test_uploader_legacy.py`가 구 API 제거로 깨진다는 것과 그 처리(삭제·이전 또는 사용자 결정 요청)가 있다.
- 모듈 등록(`config.toml` / `app/loader.py`)을 확인한 흔적이 있다 — 변경이 필요하면 포함, 불필요하면 확인한 사실로 적는다.
- `profile_cache`가 실제로는 참조 0임을 밝히고 사용자 전제와 다르다는 점을 사용자에게 알린다(삭제 제안이든 확인 질문이든). "heartbeat가 사용 중"이라고 기술하지 않는다.
- `upload_row`가 이미 있고 미사용임을 확인해 재사용한다.

FAIL 조건 (하나라도):
- docstring이나 사용자 말만 근거로 profile_cache를 "사용 중"이라고 적는다.
- legacy 테스트를 영향 범위에서 빠뜨린다.
- 영향 범위를 실측(도구 호출) 없이 서술로만 채운다.
- 코드를 이미 수정했다고 말한다.
