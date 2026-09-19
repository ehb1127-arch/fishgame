class_name CardArtRegistry
extends RefCounted

const ART := {
	&"thalassa_spire_of_coral": "res://assets/card_art/champions/thalassa.png",
	&"nereus_reader_of_the_deep": "res://assets/card_art/champions/nereus.png",
	&"morgaine_the_drowned_queen": "res://assets/card_art/champions/morgaine.png",
	&"captain_kai_the_last_sailor": "res://assets/card_art/champions/kai.png",
	&"orca_warden_of_the_heart": "res://assets/card_art/champions/orca.png",
}


static func texture_for(card_id: StringName) -> Texture2D:
	var path := str(ART.get(card_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


