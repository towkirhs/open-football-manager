extends Control
## A player picture. Shows the player's photo when one is available; otherwise draws a
## template portrait: one of 4 skin tones, 3 builds and several hairstyles, wearing the
## club's shirt. The look is picked from the player's id, so it never changes.

const SKIN := ["#f1c9a5", "#d9a37a", "#a8714a", "#6b4429"]
const HAIR := ["#1c1410", "#3b2516", "#6a4527", "#c9a15a", "#8c8c8c"]
const STYLES := ["short", "curly", "buzz", "long", "bald"]

var player = null
var shirt: Color = Color("#1f7a4d")
var trim: Color = Color("#ffffff")
var backdrop: Color = Color("#1e3226")

var _photo: Texture2D = null


func setup(p, colours: Array, bg: Color) -> void:
	player = p
	shirt = Color(colours[0])
	trim = Color(colours[1])
	backdrop = bg
	_photo = null
	if p != null and p.photo != "" and FileAccess.file_exists(p.photo):
		var img := Image.load_from_file(p.photo)
		if img != null:
			_photo = ImageTexture.create_from_image(img)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), backdrop)
	if player == null:
		return
	if _photo != null:
		draw_texture_rect(_photo, Rect2(Vector2.ZERO, size), false)
		return

	var seed_value: int = absi(hash(player.id))
	var skin := Color(SKIN[seed_value % SKIN.size()])
	var hair := Color(HAIR[(seed_value / 7) % HAIR.size()])
	var style: String = STYLES[(seed_value / 53) % STYLES.size()]
	if player.age < 30 and style == "bald":
		style = "buzz"
	if player.age < 30 and hair == Color(HAIR[4]):
		hair = Color(HAIR[0])
	var physical: float = player.attr("physical")
	var build := 0.0  # slim
	if physical >= 75.0:
		build = 1.0  # strong
	elif physical >= 60.0:
		build = 0.5  # average

	var cx := w * 0.5
	# Shoulders and shirt
	var shoulder := w * (0.36 + 0.07 * build)
	var top_y := h * 0.68
	var shirt_pts := PackedVector2Array([
		Vector2(cx - shoulder, h), Vector2(cx - shoulder, top_y + h * 0.08),
		Vector2(cx - shoulder * 0.75, top_y), Vector2(cx + shoulder * 0.75, top_y),
		Vector2(cx + shoulder, top_y + h * 0.08), Vector2(cx + shoulder, h),
	])
	draw_colored_polygon(shirt_pts, shirt)
	# Neck
	var neck_w := w * (0.11 + 0.03 * build)
	draw_rect(Rect2(cx - neck_w * 0.5, h * 0.55, neck_w, h * 0.16), skin.darkened(0.08))
	# Collar
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - neck_w * 0.85, top_y), Vector2(cx + neck_w * 0.85, top_y), Vector2(cx, top_y + h * 0.07),
	]), trim)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - neck_w * 0.55, top_y), Vector2(cx + neck_w * 0.55, top_y), Vector2(cx, top_y + h * 0.045),
	]), skin.darkened(0.08))
	# Shirt stripes on the sleeves
	draw_line(Vector2(cx - shoulder * 0.9, top_y + h * 0.05), Vector2(cx - shoulder * 0.9, h), trim, maxf(2.0, w * 0.02))
	draw_line(Vector2(cx + shoulder * 0.9, top_y + h * 0.05), Vector2(cx + shoulder * 0.9, h), trim, maxf(2.0, w * 0.02))

	# Head
	var head_c := Vector2(cx, h * 0.38)
	var rx := w * (0.17 + 0.015 * build)
	var ry := h * 0.2
	if style == "long":
		_ellipse(head_c + Vector2(0, ry * 0.35), rx * 1.18, ry * 1.05, hair)
	# Ears
	draw_circle(Vector2(cx - rx * 0.98, head_c.y + ry * 0.05), rx * 0.2, skin.darkened(0.05))
	draw_circle(Vector2(cx + rx * 0.98, head_c.y + ry * 0.05), rx * 0.2, skin.darkened(0.05))
	_ellipse(head_c, rx, ry, skin)

	match style:
		"short", "long":
			var cap := PackedVector2Array()
			for i in 21:
				var a := PI + PI * i / 20.0
				cap.append(head_c + Vector2(cos(a) * rx * 1.04, sin(a) * ry * 1.06 - ry * 0.05))
			cap.append(head_c + Vector2(rx * 1.02, -ry * 0.15))
			cap.append(head_c + Vector2(-rx * 1.02, -ry * 0.15))
			draw_colored_polygon(cap, hair)
		"curly":
			for i in 9:
				var a := PI + PI * i / 8.0
				draw_circle(head_c + Vector2(cos(a) * rx * 0.85, sin(a) * ry * 0.8 - ry * 0.12), rx * 0.34, hair)
		"buzz":
			var cap2 := PackedVector2Array()
			for i in 21:
				var a := PI + PI * i / 20.0
				cap2.append(head_c + Vector2(cos(a) * rx * 1.0, sin(a) * ry * 1.0))
			cap2.append(head_c + Vector2(rx, -ry * 0.35))
			cap2.append(head_c + Vector2(-rx, -ry * 0.35))
			draw_colored_polygon(cap2, Color(hair, 0.75))

	# A simple face: eyes and a hint of a mouth.
	var eye_y := head_c.y + ry * 0.08
	var eye_dx := rx * 0.38
	var eye_r := maxf(1.5, w * 0.018)
	draw_circle(Vector2(cx - eye_dx, eye_y), eye_r, Color("#1b1b1b"))
	draw_circle(Vector2(cx + eye_dx, eye_y), eye_r, Color("#1b1b1b"))
	draw_line(Vector2(cx - rx * 0.22, head_c.y + ry * 0.52), Vector2(cx + rx * 0.22, head_c.y + ry * 0.52), skin.darkened(0.3), maxf(1.5, w * 0.012))


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
