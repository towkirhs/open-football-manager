extends VBoxContainer
## Settings: colour theme, your world file (real players, kept on your device),
## career options and about.

const W = preload("res://src/ui/widgets.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const WorldLoader = preload("res://src/data/world_loader.gd")

var hub = null
var season = null
var _web_callback = null
var _status: Label


func _ready() -> void:
	season = hub.season
	var sb: Array = W.scroll_box()
	add_child(sb[0])
	var body: VBoxContainer = sb[1]

	var card := W.panel()
	body.add_child(card)
	var v := W.vbox(12)
	card.add_child(v)
	v.add_child(W.heading("Colour theme"))
	var swatches := W.hbox(10)
	v.add_child(swatches)
	for theme_name in UiTheme.names():
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = theme_name == UiTheme.current
		b.text = theme_name
		b.custom_minimum_size = Vector2(150, 64)
		var sbx := StyleBoxFlat.new()
		sbx.bg_color = Color(UiTheme.THEMES[theme_name]["panel"])
		sbx.border_color = Color(UiTheme.THEMES[theme_name]["accent"])
		sbx.set_border_width_all(4 if theme_name == UiTheme.current else 2)
		sbx.set_corner_radius_all(10)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, sbx)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, Color(UiTheme.THEMES[theme_name]["text"]))
		var tn: String = theme_name
		b.pressed.connect(func(): hub.app.set_theme_name(tn))
		swatches.add_child(b)

	var wcard := W.panel()
	body.add_child(wcard)
	var wv := W.vbox(10)
	wcard.add_child(wv)
	wv.add_child(W.heading("World"))
	wv.add_child(W.wrap_label("This career: %s (%d clubs)%s." % [season.world_name, season.clubs.size(), ", fictional" if season.fictional else ""], 14, "text"))
	wv.add_child(W.wrap_label("To play with real clubs and players, build a world file on your own computer with tools/build_world.py (see the README), then load it here. It is stored only on this device and is never uploaded anywhere. New careers can then use it.", 13))
	var row := W.hbox(10)
	wv.add_child(row)
	var load_btn := W.button("Load a world file", true)
	load_btn.custom_minimum_size = Vector2(200, 42)
	load_btn.pressed.connect(_pick_file)
	row.add_child(load_btn)
	if WorldLoader.has_custom_world():
		var rm := W.button("Remove my world file")
		rm.pressed.connect(func():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(WorldLoader.CUSTOM_PATH))
			hub.open_tab.call_deferred("settings"))
		row.add_child(rm)
	_status = W.wrap_label("A world file is loaded on this device." if WorldLoader.has_custom_world() else "No world file loaded: new careers use the fictional world.", 13, "muted")
	wv.add_child(_status)

	var ccard := W.panel()
	body.add_child(ccard)
	var cv := W.vbox(10)
	ccard.add_child(cv)
	cv.add_child(W.heading("Career"))
	cv.add_child(W.wrap_label("Your career saves automatically after every match day.", 14))
	var crow := W.hbox(10)
	cv.add_child(crow)
	var menu := W.button("Main menu")
	menu.custom_minimum_size = Vector2(140, 40)
	menu.pressed.connect(hub.app.show_new_game)
	crow.add_child(menu)
	var del := W.button("Delete career")
	del.custom_minimum_size = Vector2(140, 40)
	del.add_theme_color_override("font_color", UiTheme.c("bad"))
	del.pressed.connect(func(): hub.confirm("Delete this career? This cannot be undone.", hub.app.delete_career))
	crow.add_child(del)

	var acard := W.panel()
	body.add_child(acard)
	var av := W.vbox(8)
	acard.add_child(av)
	av.add_child(W.heading("About"))
	av.add_child(W.wrap_label("Open Football Manager is free and open source. No payments, ever: every club, yours and the AI's, plays by the same rules. Source code: github.com/towkirhs/open-football-manager", 14))


# ---------------------------------------------------------------- loading a world file

func _pick_file() -> void:
	if OS.has_feature("web"):
		_pick_file_web()
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.json ; World files"])
	dlg.title = "Choose a world file"
	dlg.size = Vector2i(900, 600)
	dlg.file_selected.connect(func(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			_use_text(f.get_as_text()))
	add_child(dlg)
	dlg.popup_centered()


func _pick_file_web() -> void:
	_web_callback = JavaScriptBridge.create_callback(_on_web_file)
	JavaScriptBridge.eval("""
		window.ofmPickFile = function (cb) {
			var input = document.createElement('input');
			input.type = 'file';
			input.accept = '.json,application/json';
			input.onchange = function () {
				var file = input.files[0];
				if (!file) { return; }
				var reader = new FileReader();
				reader.onload = function () { cb(reader.result); };
				reader.readAsText(file);
			};
			input.click();
		};
	""", true)
	var window = JavaScriptBridge.get_interface("window")
	window.ofmPickFile(_web_callback)


func _on_web_file(args: Array) -> void:
	if args.is_empty():
		return
	_use_text(str(args[0]))


func _use_text(text: String) -> void:
	var w := WorldLoader.parse_world(text)
	if w.has("error"):
		hub.message("World file", "That file can't be used: %s" % w["error"])
		return
	var f := FileAccess.open(WorldLoader.CUSTOM_PATH, FileAccess.WRITE)
	if f == null:
		hub.message("World file", "Could not store the file on this device.")
		return
	f.store_string(text)
	f.close()
	hub.message("World file", "Loaded %s: %d clubs in %d leagues. Start a new career from the main menu and tick \"Use my world file\"." % [w["name"], w["clubs"].size(), w["leagues"].size()])
	hub.open_tab.call_deferred("settings")
