# 카드 JSON 스키마

카드는 전부 데이터다. 새 카드를 만드는 데 GDScript를 건드릴 일은 없다.

파일 위치: `data/sets/<세트>/cards/<진영>.json` (배열)

---

## 기본 필드

```json
{
  "id": "reef_scout",
  "name": "Reef Scout",
  "name_ko": "암초 정찰병",
  "faction": "conclave",
  "cost": "1U",
  "types": ["Creature"],
  "supertypes": ["Legendary"],
  "subtypes": ["Merfolk", "Scout"],
  "power": 2,
  "toughness": 1,
  "depth": "surface",
  "keywords": ["Amphibious"],
  "rarity": "coral",
  "salvage": 2,
  "fathom": 4,
  "text": "...",
  "text_ko": "...",
  "flavor": "...",
  "flavor_ko": "...",
  "abilities": []
}
```

| 필드 | 값 |
|---|---|
| `cost` | `"2UU"`, `"X1R"`, `"0"` 형식. W/U/B/R/G/C와 X |
| `types` | Creature, Instant, Sorcery, Enchantment, Artifact, Land, Champion |
| `depth` | `surface` / `midwater` / `abyss` (기본 midwater) |
| `rarity` | driftwood / coral / pearl / gold / relic / leviathan |
| `salvage` | 추가 비용. 난파선에서 이만큼 추방해야 발동 가능 |
| `fathom` | 영웅이 시작하는 인장 수 |
| `colors` | 생략하면 마나 비용에서 자동 추론. 대지·무색은 `[]` 명시 |

---

## 능력 (abilities)

각 항목은 `kind`로 구분한다.

### spell — 즉발/집중마법의 본문
```json
{"kind": "spell",
 "targets": [{"id": "t1", "kind": "creature", "controller": "any"}],
 "effects": [{"op": "damage", "amount": 3, "to": "t1"}]}
```

### triggered — 유발 능력
```json
{"kind": "triggered", "trigger": "self_etb",
 "trigger_filter": {"controller": "you", "subtypes": ["Pirate"]},
 "condition": {"type": "tide", "value": "low"},
 "targets": [], "effects": []}
```

`trigger` 값: `self_etb`, `other_etb`, `self_dies`, `other_dies`, `self_attacks`,
`self_blocks`, `self_deals_combat_damage_to_player`, `upkeep`, `opponent_upkeep`,
`end_step`, `draw_step`, `you_cast_spell`, `opponent_cast_spell`, `you_gain_life`,
`tide_changed`

### activated — 기동 능력
```json
{"kind": "activated",
 "cost": {"mana": "2", "tap": true, "sacrifice": false, "discard": false},
 "timing": "sorcery",
 "text": "Salvage 1: draw",
 "effects": []}
```

### static — 지속 효과
```json
{"kind": "static", "effect": {
  "type": "pt_boost", "power": 1, "toughness": 1, "include_self": false,
  "affects": {"kind": "creature", "controller": "you",
              "filter": {"subtypes": ["Fish"], "depth": "abyss"}}}}
```

`effect.type`: `pt_boost`, `grant_keyword`, `cost_reduction`, `enters_tapped`,
`dice_bonus`, `turn_timer`

### mana — 마나 능력 (스택을 쓰지 않는다)
```json
{"kind": "mana", "cost": {"tap": true}, "produces": ["U", "B"]}
```

### champion — 영웅 능력
```json
{"kind": "champion", "cost": -2, "text": "Rally the reef",
 "targets": [], "effects": []}
```
`cost`가 양수면 인장을 더하고, 음수면 그만큼 소모한다.

---

## 효과 (effects)

`{"op": "...", ...}` 형태. `to`는 목표 슬롯 id(`"t1"`)나 선택자다.

### 피해와 제거
`damage` · `destroy` · `exile` · `bounce` · `sacrifice` · `counter_spell`

### 카드
`draw` · `discard` · `discard_hand` · `mill` · `search_basic_land` · `scry` ·
`return_from_graveyard` · `recover` (난파선에서, 상대 카드 포함) ·
`vault_fetch` (보관고에서) · `steal_hand` · `steal_library` · `swap_hands` ·
`reveal_hand`

### 생명과 마나
`gain_life` · `lose_life` · `add_mana`

### 보드
`pump` · `counters` · `tap` · `untap` · `token` · `clone` · `gain_control` ·
`swap_control` · `move_depth`

### 시간과 턴
`skip_turn` · `extra_turn` · `set_timer` · `scale_timer` · `timeout_penalty` ·
`rewind` (턴 시작 시점으로 되돌린다)

### 기타
`salvage` (난파선 소모) · `roll` (주사위)

### 주사위 분기
```json
{"op": "roll", "sides": 6, "count": 1, "per_star": 1, "outcomes": [
  {"min": 5, "label": "jackpot", "effects": []},
  {"min": 3, "effects": []},
  {"min": 1, "effects": []}]}
```
위에서부터 검사하므로 **좋은 결과를 먼저** 쓴다. 전장의 `dice_bonus` 효과가
굴림에 더해진다.

---

## 수치 (amount)

정수를 쓰거나, 동적 값을 쓴다.

```json
{"dynamic": "x"}
{"dynamic": "count", "filter": {"types": ["Creature"]}, "controller": "you"}
{"dynamic": "spells_cast_this_turn"}
{"dynamic": "wreck_size"}
{"dynamic": "half_life"}
{"dynamic": "cards_in_hand"}
{"dynamic": "creatures_in_band", "band": "abyss"}
{"dynamic": "source_power"}
```

`per_star`를 함께 쓰면 강화 단계마다 수치가 오른다.
`"amount": 3, "per_star": 1` → ★1에 3, ★5에 7.

---

## 선택자 (to)

`self` · `controller` · `each_opponent` · `each_player` · `each_ally` ·
`teammates` · `all_creatures` · `creatures_you_control` ·
`creatures_opponent_controls` · `other_creatures_you_control` ·
`attacking_creatures` · `surface_creatures` · `abyss_creatures` ·
`creatures_in_my_band` · `opponent_creatures_in_my_band`

또는 그룹 객체:
```json
{"kind": "creature", "controller": "opponent", "filter": {"max_power": 3}}
```

---

## 목표 (targets)

```json
{"id": "t1", "kind": "creature", "controller": "opponent",
 "optional": true, "filter": {"max_power": 3}}
```

`kind`: `creature`, `permanent`, `land`, `artifact`, `enchantment`, `player`,
`any`(생물 또는 플레이어), `spell`, `card_in_graveyard`

`controller`: `you`, `ally`, `opponent`, `any`

`filter` 키: `types`, `not_types`, `subtypes`, `colors`, `keywords`,
`without_keywords`, `depth`, `max_power`, `min_power`, `max_toughness`,
`max_mana_value`, `min_mana_value`, `tapped`, `attacking`, `blocking`, `is_token`

**목표가 하나도 없으면 그 주문은 발동 자체가 불가능하다.** 해결 시점에 모든
목표가 불법이 되면 주문은 해결되지 않고 난파선으로 간다.

---

## 조건 (condition)

```json
{"type": "tide", "value": "low"}
{"type": "controls", "filter": {"subtypes": ["Fish"]}, "at_least": 3}
{"type": "life_at_most", "value": 10}
{"type": "source_in_band", "band": "abyss"}
{"type": "spells_cast_at_least", "value": 3}
{"type": "wreck_at_least", "value": 10}
```

---

## 강화 (upgrade)

```json
"upgrade": {
  "milestones": {"3": {"keywords": ["Venomous"]}, "5": {"keywords": ["Breach"]}},
  "spell_bonus_per_star": 1
}
```

성급에 따른 기본 스탯 상승은 전역 테이블(`GameEnums.STAR_POWER_BONUS`)이
처리한다. `milestones`는 **새 키워드를 얻는 지점**이라 카드의 성격 자체가
바뀐다 — 수집과 강화의 동기가 여기서 나온다.
