## Mana costs, mana pools, and automatic payment planning.
##
## Costs are written the way Magic writes them, as a run of generic and
## colored symbols: "2UU" is two generic plus two blue, "X1R" is X plus one
## generic plus one red, "0" is free.
class_name Mana
extends RefCounted


## A parsed mana cost. Immutable once built.
class Cost:
	extends RefCounted

	var generic: int = 0
	var x_count: int = 0
	## Symbol -> required amount, e.g. {"U": 2}.
	var symbols: Dictionary = {}

	func _init(p_generic: int = 0, p_symbols: Dictionary = {}, p_x: int = 0) -> void:
		generic = p_generic
		symbols = p_symbols.duplicate()
		x_count = p_x

	## Parses "2UU" style text. Unknown characters are ignored so that a typo
	## in a card file degrades to a cheaper cost instead of crashing the game.
	static func parse(text: String) -> Cost:
		var cost := Cost.new()
		var digits := ""
		for i in text.length():
			var c := text[i].to_upper()
			if c.is_valid_int():
				digits += c
			else:
				if not digits.is_empty():
					cost.generic += int(digits)
					digits = ""
				if c == "X":
					cost.x_count += 1
				elif c in GameEnums.MANA_SYMBOLS:
					cost.symbols[c] = int(cost.symbols.get(c, 0)) + 1
		if not digits.is_empty():
			cost.generic += int(digits)
		return cost

	## Total mana value (converted mana cost). X counts as zero on the stack
	## unless a chosen value is supplied.
	func mana_value(x_value: int = 0) -> int:
		var total := generic + x_count * x_value
		for sym in symbols:
			total += int(symbols[sym])
		return total

	## Number of individual mana that must actually be produced to pay this.
	func total_required(x_value: int = 0) -> int:
		return mana_value(x_value)

	## The colors this cost requires, one entry per required symbol.
	func colored_requirements() -> Array[String]:
		var out: Array[String] = []
		for sym in symbols:
			for _i in int(symbols[sym]):
				out.append(String(sym))
		return out

	func is_free() -> bool:
		return generic == 0 and x_count == 0 and symbols.is_empty()

	func duplicate_cost() -> Cost:
		return Cost.new(generic, symbols, x_count)

	func _to_string() -> String:
		var out := ""
		for _i in x_count:
			out += "X"
		if generic > 0:
			out += str(generic)
		for sym in GameEnums.MANA_SYMBOLS:
			for _i in int(symbols.get(sym, 0)):
				out += String(sym)
		return out if not out.is_empty() else "0"


## A player's floating mana. Emptied at the end of every step and phase.
class Pool:
	extends RefCounted

	var amounts: Dictionary = {}

	func _init() -> void:
		clear()

	func clear() -> void:
		amounts = {}
		for sym in GameEnums.MANA_SYMBOLS:
			amounts[sym] = 0

	func add(symbol: String, count: int = 1) -> void:
		if symbol in GameEnums.MANA_SYMBOLS:
			amounts[symbol] = int(amounts[symbol]) + count

	func get_amount(symbol: String) -> int:
		return int(amounts.get(symbol, 0))

	func total() -> int:
		var n := 0
		for sym in amounts:
			n += int(amounts[sym])
		return n

	func is_empty() -> bool:
		return total() == 0

	## Can this pool pay the cost exactly as it stands?
	func can_pay(cost: Cost, x_value: int = 0) -> bool:
		var work := amounts.duplicate()
		for sym in cost.symbols:
			var need := int(cost.symbols[sym])
			if int(work.get(sym, 0)) < need:
				return false
			work[sym] = int(work[sym]) - need
		var generic_left := cost.generic + cost.x_count * x_value
		var available := 0
		for sym in work:
			available += int(work[sym])
		return available >= generic_left

	## Spends the cost from this pool. Returns false and changes nothing when
	## the pool cannot cover it.
	func pay(cost: Cost, x_value: int = 0) -> bool:
		if not can_pay(cost, x_value):
			return false
		for sym in cost.symbols:
			amounts[sym] = int(amounts[sym]) - int(cost.symbols[sym])
		var generic_left := cost.generic + cost.x_count * x_value
		# Spend colorless first, then colors this cost does not itself demand,
		# so that a following spell in the same step still finds its colors.
		var order: Array[String] = ["C"]
		for sym in GameEnums.COLORS:
			if not cost.symbols.has(sym):
				order.append(sym)
		for sym in GameEnums.COLORS:
			if cost.symbols.has(sym):
				order.append(sym)
		for sym in order:
			if generic_left <= 0:
				break
			var take: int = min(generic_left, int(amounts.get(sym, 0)))
			amounts[sym] = int(amounts[sym]) - take
			generic_left -= take
		return true

	func _to_string() -> String:
		var parts: Array[String] = []
		for sym in GameEnums.MANA_SYMBOLS:
			var n := int(amounts.get(sym, 0))
			if n > 0:
				parts.append("%d%s" % [n, sym])
		return "/".join(parts) if not parts.is_empty() else "empty"


## Works out which mana sources to tap for a cost.
##
## [param sources] is one entry per untapped source, each entry being the list
## of symbols that source could produce (a plain Island is ["U"], a dual is
## ["W", "U"]). Returns one {"index": i, "symbol": "U"} per mana to produce,
## or an empty array when the cost cannot be paid. Sources are assumed to
## produce exactly one mana.
static func plan_payment(sources: Array, cost: Cost, x_value: int = 0) -> Array:
	var needed := cost.total_required(x_value)
	if needed == 0:
		return []
	if sources.size() < needed:
		return []

	var requirements := cost.colored_requirements()
	var used: Array[bool] = []
	used.resize(sources.size())
	used.fill(false)
	var picked: Array = []

	if not _assign_colors(sources, requirements, 0, used, picked):
		return []

	# Fill the generic portion with whatever is left, preferring sources that
	# produce the fewest colors so flexible lands stay open.
	var generic_left := cost.generic + cost.x_count * x_value
	if generic_left > 0:
		var leftovers: Array[int] = []
		for i in sources.size():
			if not used[i]:
				leftovers.append(i)
		leftovers.sort_custom(func(a: int, b: int) -> bool:
			return (sources[a] as Array).size() < (sources[b] as Array).size())
		if leftovers.size() < generic_left:
			return []
		for i in generic_left:
			var idx: int = leftovers[i]
			var symbols := sources[idx] as Array
			picked.append({"index": idx, "symbol": str(symbols[0]) if not symbols.is_empty() else "C"})

	return picked


## Backtracking assignment of one source per colored symbol required.
static func _assign_colors(
	sources: Array,
	requirements: Array[String],
	index: int,
	used: Array[bool],
	picked: Array
) -> bool:
	if index >= requirements.size():
		return true
	var want := requirements[index]
	for i in sources.size():
		if used[i]:
			continue
		if want in (sources[i] as Array):
			used[i] = true
			picked.append({"index": i, "symbol": want})
			if _assign_colors(sources, requirements, index + 1, used, picked):
				return true
			picked.pop_back()
			used[i] = false
	return false
