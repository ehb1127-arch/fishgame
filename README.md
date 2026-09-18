# Abyss TCG — 「마지막 조류」

Godot 4로 만드는 안드로이드 수집형 카드 게임. Magic 계열의 깊이(마나, 스택,
우선권, 즉발 응수)를 유지하면서, 바다라는 소재가 있어야만 성립하는 규칙을
얹었다.

> 지상은 사라졌다. 물이 모든 대륙을 삼킨 뒤 남은 건 바다뿐이고, 심해
> 밑바닥에는 조류를 만들어내는 고대의 **심장**이 잠들어 있다.
> 다섯 진영이 그것을 두고 싸운다.

---

## 이 게임만의 규칙

**수심대** — 전장이 수면/중층/심해 3층으로 나뉘고, **방어는 같은 층에서만
가능하다.** 턴마다 생물 하나만 층을 옮길 수 있어서, 매 턴 상대가 어느 층을
비울지 읽는 싸움이 된다. 비행·도달 같은 회피 키워드를 위치 전략으로 대체한다.

**조류** — 한 라운드마다 밀물과 썰물이 교대하며 수면 또는 심해를 강화한다.
주기가 예측 가능하므로 몇 턴 뒤를 보고 미리 층을 옮겨둘 수 있다.

**난파선** — 양쪽 무덤이 하나로 합쳐진 공유 더미. **인양** 비용은 여기서
지불한다. 상대의 생물을 죽이는 것은 상대에게 연료를 주는 일이기도 하다.

**시계** — 턴 제한 시간이 규칙의 일부다. 모드에 따라 90초에서 10초까지 가고,
**압박수심** 같은 카드는 상대를 8초로 묶는다.

그 밖에 주사위 도박, 턴 되돌리기, 턴 건너뛰기, 손패 훔치기, 보조덱(보관고),
영웅(Champion) 타입이 있다. 전체 규칙은 [docs/rules.md](docs/rules.md).

---

## 구조

```
scripts/core/     룰 엔진. 씬 트리에 의존하지 않는 순수 GDScript
scripts/ai/       AI 상대
scripts/meta/     재화·상점·컬렉션·레이팅·항해·코덱스
scripts/ui/       최소 기능 UI (디자인 교체 예정)
scripts/data/     카드 데이터베이스 (autoload)
data/sets/        카드 정의 JSON
data/decks/       덱 정의
data/story/       영웅 서사 아크
tests/            헤드리스 테스트
docs/             규칙, 카드 스키마, 세계관
```

엔진은 **입력을 요청하지 않는다.** 컨트롤러(UI든 AI든 테스트든)가
`get_legal_actions()`로 가능한 행동을 받아 `perform()`으로 돌려준다. 덕분에
UI 없이도 전체 게임을 헤드리스로 돌릴 수 있고, AI가 규칙을 어길 방법이 없다.

---

## 실행

### 에디터에서
1. [Godot 4.3](https://godotengine.org/download) 설치
2. 프로젝트 폴더를 열고 F5

### 테스트
```bash
godot --headless --path . res://tests/test_runner.tscn
```
AI끼리 실제 덱으로 풀게임을 여러 판 돌려서 엔진 전체를 검증한다.

### 안드로이드 APK
GitHub Actions의 **Android build** 워크플로우가 디버그 APK를 아티팩트로 뽑는다.
실제로 돌려서 24MB짜리 APK가 나오는 것까지 확인했다. 방법은 세 가지다.

- **수동 실행** — Actions 탭 → Android build → Run workflow
- **빌드 브랜치** — `build/` 로 시작하는 브랜치를 밀면 릴리스를 끊지 않고 APK가 나온다.
  `git push -f origin HEAD:refs/heads/build/apk-check`
- **태그** — `v` 로 시작하는 태그를 밀면 그 커밋으로 빌드된다.
  `git tag v0.1.0 && git push origin v0.1.0`

릴리스 빌드는 저장소 시크릿 `ANDROID_KEYSTORE_BASE64`가 필요하다. 없으면
서명 없는 APK를 조용히 내놓는 대신 빌드가 실패한다.

로컬에서 빌드하려면:

1. Godot 에디터 → 편집기 설정 → 내보내기 → Android에서 SDK 경로 지정
2. 프로젝트 → 내보내기 → Android 프리셋 선택 → 내보내기

---

## 새 카드 추가

`data/sets/last_tide/cards/` 안의 JSON에 항목을 하나 넣으면 끝이다. 코드
수정은 없다. 쓸 수 있는 효과와 조건은 [docs/card_schema.md](docs/card_schema.md)에
전부 정리돼 있다.

```json
{
  "id": "ink_cloud", "name": "Ink Cloud", "name_ko": "먹물 구름",
  "faction": "conclave", "cost": "1U", "types": ["Instant"], "rarity": "coral",
  "text_ko": "목표 생물은 턴 종료까지 먹물을 얻는다.",
  "abilities": [
    {"kind": "spell",
     "targets": [{"id": "t1", "kind": "creature", "controller": "you"}],
     "effects": [{"op": "pump", "keywords": ["Ink"], "to": "t1"}]}
  ]
}
```

---

## 세계관 확장

[docs/worldbuilding.md](docs/worldbuilding.md)에 확장 축을 미리 고정해 뒀다.
세계는 깊이에 따라 **일곱 해역**으로 나뉘고, 세트가 하나 나올 때마다 한 층씩
내려간다. 시간축(세 번의 범람)과 차원축도 열려 있어서, 나중에 나올 세트가
이미 나온 카드의 의미를 깨뜨리지 않는다.

---

## 저작권

규칙과 메커니즘은 저작권 보호 대상이 아니지만, 카드 이름·텍스트·아트·상표는
보호된다. 이 프로젝트의 카드 이름, 키워드, 세계관, 플레이버 텍스트는 전부
독자 창작물이다. 기존 카드 게임의 카드명·룰 텍스트·아트·상표를 가져다 쓰지 말 것.
