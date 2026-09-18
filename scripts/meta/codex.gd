## The Codex: the story you assemble by playing.
##
## Each Champion has a five-chapter arc whose fourth chapter is the twist and
## whose fifth is the shared truth, which only opens once every arc has
## reached chapter four. Unlock conditions are evaluated against the profile,
## so the Codex never needs its own bookkeeping.
class_name Codex
extends RefCounted

const FINAL_CHAPTER := 5


## Every arc with its unlock state, for the Codex screen.
## Each entry is {"arc": Dictionary, "unlocked": int, "next": Dictionary}.
static func overview() -> Array:
	var out: Array = []
	for arc_id in Cards.story_ids():
		var arc := Cards.get_story(str(arc_id))
		var unlocked := Player.codex_chapter(str(arc_id))
		out.append({
			"arc": arc,
			"unlocked": unlocked,
			"next": next_requirement(arc, unlocked),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str((a["arc"] as Dictionary).get("id", "")) < str((b["arc"] as Dictionary).get("id", "")))
	return out


## Checks every arc and unlocks whatever the profile now qualifies for.
## Returns the chapters opened by this call, newest progress first.
static func refresh() -> Array:
	var opened: Array = []
	# Two passes: the final chapter depends on every other arc's progress, so
	# the ordinary chapters have to settle first.
	for pass_index in 2:
		for arc_id in Cards.story_ids():
			var arc := Cards.get_story(str(arc_id))
			var chapters := arc.get("chapters", []) as Array
			var unlocked := Player.codex_chapter(str(arc_id))
			for i in chapters.size():
				var chapter_number := i + 1
				if chapter_number <= unlocked:
					continue
				if not _is_satisfied(arc, (chapters[i] as Dictionary).get("unlock", {}) as Dictionary):
					break  # Chapters unlock in order.
				if Player.unlock_codex(str(arc_id), chapter_number):
					opened.append({"arc": str(arc_id), "chapter": chapter_number,
							"title": str((chapters[i] as Dictionary).get("title_ko", ""))})
				unlocked = chapter_number
	return opened


## What the player still has to do for the next chapter of this arc.
static func next_requirement(arc: Dictionary, unlocked: int) -> Dictionary:
	var chapters := arc.get("chapters", []) as Array
	if unlocked >= chapters.size():
		return {}
	var chapter := chapters[unlocked] as Dictionary
	var unlock := chapter.get("unlock", {}) as Dictionary
	return {
		"chapter": unlocked + 1,
		"condition": unlock,
		"description_ko": describe(arc, unlock),
	}


static func describe(arc: Dictionary, unlock: Dictionary) -> String:
	var faction := str(arc.get("faction", ""))
	match str(unlock.get("type", "")):
		"own_faction_cards":
			var have := _faction_cards_owned(faction)
			var need := int(unlock.get("count", 1))
			return "%s 진영 카드 %d종 수집 (%d/%d)" % [_faction_name(faction), need, have, need]
		"clear_region":
			return "항해에서 %d구역까지 클리어" % (int(unlock.get("region", 1)) + 1)
		"clear_voyage":
			return "%s(으)로 항해 완주" % str(arc.get("name_ko", ""))
		"all_arcs":
			return "모든 영웅의 %d장 해금" % int(unlock.get("chapter", 4))
		_:
			return "?"


static func _is_satisfied(arc: Dictionary, unlock: Dictionary) -> bool:
	var faction := str(arc.get("faction", ""))
	match str(unlock.get("type", "")):
		"own_faction_cards":
			return _faction_cards_owned(faction) >= int(unlock.get("count", 1))

		"clear_region":
			return _deepest_region_cleared() > int(unlock.get("region", 1))

		"clear_voyage":
			# The run has to be finished, and if the chapter asks for it, the
			# Champion has to be in the collection.
			if not _has_cleared_voyage():
				return false
			if bool(unlock.get("champion", false)):
				return Player.collection.has_card(str(arc.get("champion", "")))
			return true

		"all_arcs":
			var need := int(unlock.get("chapter", 4))
			for other_id in Cards.story_ids():
				if str(other_id) == str(arc.get("id", "")):
					continue
				if Player.codex_chapter(str(other_id)) < need:
					return false
			return Player.codex_chapter(str(arc.get("id", ""))) >= need - 1

		_:
			return false


static func _faction_cards_owned(faction: String) -> int:
	var completion := Player.collection.completion()
	var row := (completion["by_faction"] as Dictionary).get(faction, {}) as Dictionary
	return int(row.get("owned", 0))


static func _deepest_region_cleared() -> int:
	return int(Player.voyage_state.get("deepest_region", 0))


static func _has_cleared_voyage() -> bool:
	return bool(Player.voyage_state.get("ever_completed", false))


static func _faction_name(faction: String) -> String:
	match faction:
		"coral": return "산호 성단"
		"conclave": return "심연 학회"
		"drowned": return "침몰자"
		"corsair": return "해적 선단"
		"brood": return "거대군"
		_: return faction
