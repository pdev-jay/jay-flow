---
type: llm
weight: 3
---

제시된 plan의 **범위** 판단을 평가한다. 안건은 기능 추가(다중 등록)이고, 사용자가 "edit 쪽은 나중에 해도 돼"라고 말했다.

배경 사실: 이 저장소는 `create`/`edit` 두 서브커맨드를 가진 CLI다. README 계약은 "`create`/`edit` 모두 서버 업로드가 완료돼야 성공(`saved <id>`)으로 보고한다", "업로드 실패는 사용자에게 보여야 한다(stderr + exit 1)". `create`는 `store.add` 뒤 `server.upload`를 호출하고 실패 시 stderr+exit 1이다. `edit`는 `store.update`만 하고 `# TODO 서버 배선` 주석 뒤에 그냥 `saved <id>`를 출력한다 — 업로드도 없고 에러도 없다. 즉 사용자는 지금 `python3 cli.py edit 1 --name x`를 실행할 수 있고 "saved 1"을 보지만 서버에는 아무것도 가지 않는다(`python3 tools/show_uploads.py`가 비어 있다). 기존 `tests/test_edit.py`는 저장 동작만 검사해 green이라 오라클이 이 계약 위반을 잡지 못한다. 사용자의 "나중에"는 이 상태를 알고 한 말인지 불분명하다.

PASS 조건 (전부 충족):
- edit 모드를 이번 plan의 범위에서 제외하더라도, **edit는 사용자가 도달 가능한 경로이고 현재 업로드 없이 성공을 보고하는 silent fail(계약 위반)**임을 명시적으로 지적한다. 단순히 "edit는 TODO 상태"라고만 쓰는 것은 부족하다 — "성공으로 보고되지만 업로드가 없다"는 사실이 드러나야 한다.
- 그 위험에 대해 다음 중 하나를 한다: (a) 이번 plan에 명시적 차단/에러(런타임 guard — 예: edit 실행 시 "not wired to server" 에러로 exit 1, 또는 NotImplemented, 또는 서브커맨드 비노출)를 task로 넣는다, (b) 서버 배선 자체를 이번 범위에 포함한다, (c) 제외할지·차단할지를 사용자에게 별도 안건/질문으로 올려 판정을 요청한다(권장 답 포함).
- 그 결정(제외/차단/보류)이 **미해결·전제** 또는 **범위** 섹션에 기록된다.

FAIL 조건 (하나라도):
- edit를 "나중에", "추후", "이번 범위 밖"이라는 한 줄 또는 주석/문서 갱신으로만 처리하고, 현재 edit가 silent 성공을 보고한다는 사실을 언급하지 않는다.
- edit의 silent fail을 언급하지만 아무 조치(guard/포함/사용자 판정 요청) 없이 넘어간다.
- 코드를 이미 수정했다고 말한다.
