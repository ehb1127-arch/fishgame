class_name CardArtRegistry
extends RefCounted

const ART := {
	&"thalassa_spire_of_coral": "res://assets/card_art/champions/thalassa.png",
	&"nereus_reader_of_the_deep": "res://assets/card_art/champions/nereus.png",
	&"morgaine_the_drowned_queen": "res://assets/card_art/champions/morgaine.png",
	&"captain_kai_the_last_sailor": "res://assets/card_art/champions/kai.png",
	&"orca_warden_of_the_heart": "res://assets/card_art/champions/orca.png",
}

const FACTION_ART := {
	"coral": "res://assets/card_art/factions/coral.webp",
	"conclave": "res://assets/card_art/factions/conclave.webp",
	"drowned": "res://assets/card_art/factions/drowned.webp",
	"corsair": "res://assets/card_art/factions/corsair.webp",
	"brood": "res://assets/card_art/factions/brood.webp",
	"shard": "res://assets/card_art/factions/shard.webp",
}


static func texture_for(card_id: StringName, faction: String = "") -> Texture2D:
	# Named champions keep their portrait. Every other card inherits the key art
	# of its faction so a deck never falls back to an empty placeholder.
	var path := str(ART.get(card_id, FACTION_ART.get(faction, "")))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


