extends Control
## Root of the game. Owns the career (Season) and switches between screens:
## title -> club hub -> live match -> club hub ...

const UiTheme = preload("res://src/ui/ui_theme.gd")
const W = preload("res://src/ui/widgets.gd")
const Season = preload("res://src/sim/season.gd")
const WorldGen = preload("res://src/sim/world_gen.gd")
const WorldLoader = preload("res://src/data/world_loader.gd")
const NewGameScreen = preload("res://src/ui/new_game_screen.gd")
const HubScreen = preload("res://src/ui/hub_screen.gd")
const MatchScreen = preload("res://src/ui/match_screen.gd")

var season = null
var rng := RandomNumberGenerator.new()
var hub_tab: String = "home"
var busy: bool = false

var _bg: ColorRect
var _screen: Control = null
var _overlay: Control = null
var _overlay_label: Label


func _ready() -> void:
	rng.randomize()
	UiTheme.load_settings()
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_apply_theme()
	if Season.has_save():
		var s = Season.new()
		if s.load_from():
			season = s
	show_new_game()


func _apply_theme() -> void:
	theme = UiTheme.build()
	_bg.color = UiTheme.c("bg")


func _show(screen: Control) -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()
	_screen = screen
	add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _overlay != null:
		move_child(_overlay, -1)


# ---------------------------------------------------------------- navigation

func show_new_game() -> void:
	var s = NewGameScreen.new()
	s.app = self
	_show(s)


func show_hub(tab: String = "") -> void:
	if tab != "":
		hub_tab = tab
	var s = HubScreen.new()
	s.app = self
	_show(s)


## The world for a new career: the custom world file when chosen, else a fresh fictional one.
func make_world(use_custom: bool) -> Dictionary:
	if use_custom and WorldLoader.has_custom_world():
		var w := WorldLoader.load_world(WorldLoader.CUSTOM_PATH)
		if not w.has("error"):
			return w
	return WorldGen.make_world(rng)


func start_career(world: Dictionary, club_id: String, manager_name: String) -> void:
	season = Season.new()
	season.new_game(world, club_id, rng, manager_name if manager_name.strip_edges() != "" else "You")
	save()
	show_hub("home")


func continue_career() -> void:
	if season != null:
		show_hub("home" if hub_tab == "" else hub_tab)


func delete_career() -> void:
	season = null
	if Season.has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Season.SAVE_PATH))
	show_new_game()


func save() -> void:
	if season != null:
		season.save()


# ---------------------------------------------------------------- playing

## Watch today's match live.
func play_match() -> void:
	var engine = season.prepare_user_match(rng)
	if engine == null:
		return
	var f: Dictionary = season.today_user_fixture()
	var s = MatchScreen.new()
	s.app = self
	s.engine = engine
	s.user_side = 0 if f["fixture"]["home"] == season.user_club_id else 1
	s.comp_name = season.comp(f["comp"]).name + "  ·  " + season.comp(f["comp"]).round_name(f["round"])
	_show(s)


## Called by the match screen at full-time.
func finish_match(engine) -> void:
	await _run_days([engine])
	show_hub("home")


## Simulate today's match with the saved tactics.
func quick_sim() -> void:
	await _run_days([null])
	show_hub("home")


## Plays days until the human's next match day (or the end of the season).
func advance() -> void:
	if busy or season == null:
		return
	var days: Array = []
	var d: int = season.day
	while d < season.calendar.size():
		if not season.user_fixture_on(d).is_empty():
			break
		days.append(null)
		d += 1
	if days.is_empty():
		days.append(null)
	await _run_days(days)
	show_hub("home")


## Plays one day per entry (an entry is the live engine for that day, or null).
## Stops early if the season ends, the manager is sacked, or a human match comes up.
func _run_days(engines: Array) -> void:
	busy = true
	_show_overlay("Playing...")
	for i in engines.size():
		if season.is_finished() or season.sacked:
			break
		if i > 0 and not season.today_user_fixture().is_empty():
			break
		_overlay_label.text = "%s  ·  %s" % [season.today().get("label", ""), _items_text(season.today())]
		await get_tree().process_frame
		await get_tree().process_frame
		season.play_day(rng, engines[i])
	_overlay_label.text = "Saving..."
	await get_tree().process_frame
	save()
	_hide_overlay()
	busy = false


func _items_text(day: Dictionary) -> String:
	match day.get("kind", ""):
		"europe": return "European matches"
		"cup": return "Cup ties"
		"preseason": return "Pre-season"
	return "League matches"


func next_season() -> void:
	busy = true
	_show_overlay("Preparing the new season...")
	await get_tree().process_frame
	await get_tree().process_frame
	season.next_season(rng)
	save()
	_hide_overlay()
	busy = false
	show_hub("home")


func accept_job(club_id: String) -> void:
	season.accept_job(club_id, rng)
	save()
	show_hub("home")


func set_theme_name(theme_name: String) -> void:
	UiTheme.current = theme_name
	UiTheme.save_settings()
	_apply_theme()
	if season != null and _screen is HubScreen:
		show_hub()
	else:
		show_new_game()


# ---------------------------------------------------------------- overlay

func _show_overlay(text: String) -> void:
	if _overlay == null:
		_overlay = Control.new()
		_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.45)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_overlay.add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_overlay.add_child(center)
		var card := W.panel()
		card.custom_minimum_size = Vector2(380, 0)
		center.add_child(card)
		_overlay_label = W.label(text, 17)
		_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(_overlay_label)
		add_child(_overlay)
	_overlay_label.text = text
	_overlay.visible = true
	move_child(_overlay, -1)


func _hide_overlay() -> void:
	if _overlay != null:
		_overlay.visible = false
