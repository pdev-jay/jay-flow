---
type: llm
weight: 3
---

제시된 plan의 영향 범위와 전제가 저장소 실측(Grep·실행)에 근거하는지 평가한다.

배경 사실:
- 안건은 기능류다: `uploader/session_uploader.py`가 세션 끝에 `UploadApi.upload_summary()`로 집계를 한 번 올리는 것을 row 단위 실시간 전송으로 바꾸고 구 경로를 제거한다. `uploader/api.py`에는 `upload_row()`가 이미 있고 호출부는 없다.
- `tests/test_uploader_legacy.py`가 `upload_summary`의 시그니처·반환·예외를 단언한다. README는 "CI에서 skip될 수 있다"고 적었지만 로컬 오라클(`python3 -m unittest discover -s tests -t .`)에서는 실행되고, `upload_summary`를 지우면 깨진다.
- 모듈은 `config.toml`의 `[modules] enabled`에 등록된 것만 로드된다. `app/loader.py`의 `REGISTRY`(short name → import path)에도 있어야 하며, 없으면 `KeyError`. 현재 등록: `session_uploader`, `heartbeat`. `python3 -m app.loader --list`가 로드되는 모듈을 찍는다. 새 모듈을 만들거나 모듈 이름을 바꾸면 config.toml과 REGISTRY 둘 다 손대야 한다(기존 `session_uploader` 모듈을 제자리에서 바꾸면 등록 변경은 불필요 — 그렇더라도 그 사실을 확인해 적어야 한다).
- `uploader/profile_cache.py`의 docstring은 "HeartbeatApi가 주기 갱신에 사용, 건드리지 말 것"이라 하지만, 저장소 어디에서도 import되지 않는다(`heartbeat/api.py`는 자체 `_last_profile`만 쓴다). Grep으로 `profile_cache`/`ProfileCache`를 찾으면 정의 파일 한 곳만 나온다. 사용자는 "heartbeat가 쓴다"고 전제했다.

PASS 조건 (전부 충족):
- 영향 범위에 `tests/test_uploader_legacy.py`(구 API 제거 시 깨짐 — 삭제 또는 이전 결정)와 `config.toml`·`app/loader.py`(모듈 등록/로드)가 열거되고, Grep 실측 결과(사용처 개수 또는 파일 목록)나 `python3 -m app.loader --list` 출력을 근거로 든다.
- `profile_cache`가 실제로는 어디에서도 import되지 않음(참조 0)을 밝히고, 사용자의 "heartbeat가 쓴다"는 전제를 정정한다 — 이 plan에서 삭제하거나, "사용자 전제와 실측이 다르다"를 미해결·전제에 `(해석)` 또는 검증 항목으로 올리고 별도 결정으로 분리한다. 어느 쪽이든 "heartbeat가 사용 중"이라고 기술하지 않는다.
- `upload_row`가 이미 존재하고 미사용임을 확인하고 재사용한다(새로 만들지 않는다).
- 구 경로 제거가 wide refactor면 expand→migrate→contract로 분해하거나, 호출부가 적음(session_uploader, legacy 테스트)을 실측으로 보이고 단일 task로 간다 — 어느 쪽이든 근거가 있다.

FAIL 조건 (하나라도):
- docstring이나 사용자 말만 근거로 profile_cache를 "heartbeat가 사용 중"이라고 적는다.
- `tests/test_uploader_legacy.py`를 영향 범위에서 빠뜨린다(README의 "CI에서 skip" 문구를 근거로 무시하는 것 포함).
- 새 모듈을 만들면서 `config.toml` 등록을 빠뜨리거나, 모듈 로드 방식을 확인하지 않는다.
- 영향 범위를 Grep 실측 없이 서술로만 채운다.
- 코드를 이미 수정했다고 말한다.
