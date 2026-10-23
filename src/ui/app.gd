extends Control
## Root of the game. Owns the career (Season) and switches between screens:
## new game -> club hub -> live match -> club hub ...

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Season = preload("res://src/sim/season.gd")
const WorldLoader = preload("res://src/data/world_loader.gd")
const NewGameScreen = preload("res://src/ui/new_game_screen.gd")
const HubScreen = preload("res://src/ui/hub_screen.gd")
const MatchScreen = preload("res://src/ui/match_screen.gd")

const SAMPLE := "res://data/sample/sample_league.json"

var season = null
var rng := RandomNumberGenerator.new()
var hub_tab: String = "home"

var _bg: ColorRect
var _screen: Control = null


func _ready() -> void:
	rng.randomize()
	UiTheme.load_settings()
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)


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


func load_league() -> Dictionary:
	return WorldLoader.load_league(SAMPLE)


func start_career(club_id: String) -> void:
	season = Season.new()
	season.new_game(load_league(), club_id, rng)
	save()
	show_hub("home")


func continue_career() -> void:
	if season != null:
		show_hub("home")


func delete_career() -> void:
	season = null
	if Season.has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Season.SAVE_PATH))
	show_new_game()


func save() -> void:
	if season != null:
		season.save()


## Watch this week's game live.
func play_match() -> void:
	var engine = season.prepare_user_match(rng)
	if engine == null:
		return
	var s = MatchScreen.new()
	s.app = self
	s.engine = engine
	s.user_side = 0 if season.user_fixture()["user_home"] else 1
	_show(s)


## Called by the match screen at full-time (or when skipped).
func finish_match(engine) -> void:
	season.play_week(rng, engine)
	save()
	show_hub("home")


## Simulate this week's game with the saved tactics.
func quick_sim() -> void:
	season.play_week(rng, null)
	save()
	show_hub("home")


func next_season() -> void:
	season.next_season(rng)
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
