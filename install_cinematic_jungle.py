from pathlib import Path
import sys

root = Path.cwd()
main_path = root / "scripts" / "main.gd"
if not (root / "project.godot").is_file() or not main_path.is_file():
    sys.exit("FEJL: Kør scriptet fra CrashLocalPrototype-mappen.")

source = main_path.read_text(encoding="utf-8")
start = source.find("func _create_world() -> void:")
end = source.find("func _goal(", start)
if start < 0 or end < 0:
    sys.exit("FEJL: Fandt ikke grafikområdet i main.gd. Ingen ændringer foretaget.")

backup = root / "scripts" / "main.gd.before_cinematic_jungle"
if not backup.exists():
    backup.write_text(source, encoding="utf-8")

art = r'''
func _create_world() -> void:
    if is_instance_valid(world):
        world.queue_free()
    world = Node2D.new()
    world.name = "GameWorld"
    add_child(world)

    var sky := ColorRect.new()
    sky.position = Vector2(-100, -100)
    sky.size = Vector2(WORLD_WIDTH + 200, 920)
    sky.color = Color("#49a9ef") if game_mode == "RACE" else Color("#514779")
    world.add_child(sky)

    _art_ellipse(world, Vector2(1220, 235), Vector2(560, 240), Color("#b9e8e9", 0.18))
    _art_ellipse(world, Vector2(1250, 320), Vector2(700, 170), Color("#e5ffff", 0.10))

    var palette := [Color("#a4c8c1"), Color("#6fa99a"), Color("#398b70"), Color("#23664e")]
    for layer_index in range(4):
        var step := 125.0 + float(layer_index) * 24.0
        var base_y := 420.0 + float(layer_index) * 48.0
        for i in range(23):
            var x := float(i) * step - 90.0
            var peak := base_y - float((i * 67 + layer_index * 29) % (105 + layer_index * 16))
            _art_poly(world, Vector2.ZERO, [
                Vector2(x, 740), Vector2(x, base_y),
                Vector2(x + step * 0.44, peak),
                Vector2(x + step * 0.78, base_y + 18),
                Vector2(x + step, 740)
            ], palette[layer_index])

    for i in range(13):
        _art_cloud(world, Vector2(75 + i * 195, 85 + (i % 4) * 37), 0.60 + float(i % 3) * 0.18)
    for item in [[410.0, 360.0, 74.0, 275.0], [1030.0, 330.0, 105.0, 330.0],
                 [1740.0, 365.0, 88.0, 260.0], [2110.0, 395.0, 70.0, 235.0]]:
        _art_waterfall(world, Vector2(item[0], item[1]), item[2], item[3])

    for i in range(7):
        _art_temple(world, Vector2(130 + i * 340, 390 - (i % 3) * 28), 0.58 + float(i % 3) * 0.14)
    for i in range(18):
        _art_palm(world, Vector2(15 + i * 142, 610), 0.54 + float((i * 3) % 5) * 0.11)
    for i in range(52):
        _art_leaf_cluster(world, Vector2(float(i) * 47.0, 605 + float(i % 4) * 8), 0.55 + float(i % 3) * 0.16)

    _platform(Vector2(0, FLOOR_Y), Vector2(WORLD_WIDTH, 110), Color("#76503a"), Color("#9bd65c"))
    if game_mode == "RACE":
        for i in range(11):
            var px := 250.0 + i * 175.0
            var py := 500.0 - float((i % 3) * 45)
            _platform(Vector2(px, py), Vector2(100, 22), Color("#9a6338"), Color("#c2df78"))
            if i % 3 == 1:
                _art_crate(world, Vector2(px + 30, py - 43), 38.0, false)
            if i % 4 == 2:
                _art_fruit(world, Vector2(px + 65, py - 65), 13.0)
        _goal(Vector2(WORLD_WIDTH - 100, 480))
    else:
        for item in [[300.0, 500.0], [800.0, 445.0], [1300.0, 500.0], [1750.0, 460.0]]:
            _platform(Vector2(item[0], item[1]), Vector2(170, 22), Color("#9a6338"), Color("#c2df78"))
        for x in [520.0, 1000.0, 1500.0, 1950.0]:
            _hazard(Vector2(x, FLOOR_Y - 20))
        _art_crate(world, Vector2(670, 555), 46.0, true)
        _art_crate(world, Vector2(1450, 555), 46.0, false)

    for i in range(90):
        var x := float(i) * 27.0
        var h := 8.0 + float((i * 17) % 28)
        var c := Color("#247342") if i % 2 == 0 else Color("#4a9e45")
        _art_poly(world, Vector2.ZERO, [Vector2(x, FLOOR_Y + 2), Vector2(x + 8, FLOOR_Y - h), Vector2(x + 15, FLOOR_Y + 3)], c)
    for i in range(20):
        _art_flower(world, Vector2(45 + i * 117, FLOOR_Y - 9), 0.65 + float(i % 3) * 0.15)

    var layer := CanvasLayer.new()
    layer.name = "HUD"
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(22, 15)
    hud.add_theme_font_size_override("font_size", 24)
    hud.add_theme_color_override("font_color", Color.WHITE)
    hud.add_theme_color_override("font_shadow_color", Color("#15251d"))
    hud.add_theme_constant_override("shadow_offset_x", 2)
    hud.add_theme_constant_override("shadow_offset_y", 2)
    layer.add_child(hud)
    _touch_button(layer, "◀", Vector2(24, 610), "left")
    _touch_button(layer, "▶", Vector2(112, 610), "right")
    _touch_button(layer, "JUMP", Vector2(1010, 590), "jump")
    _touch_button(layer, "SPIN", Vector2(1110, 590), "spin")

    camera = Camera2D.new()
    camera.position = Vector2(640, 360)
    camera.limit_left = 0
    camera.limit_right = int(WORLD_WIDTH)
    world.add_child(camera)
    camera.make_current()


func _art_poly(parent: Node2D, at: Vector2, points: Array, color: Color) -> void:
    var shape := Polygon2D.new()
    shape.position = at
    shape.polygon = PackedVector2Array(points)
    shape.color = color
    parent.add_child(shape)


func _art_ellipse(parent: Node2D, at: Vector2, radii: Vector2, color: Color) -> void:
    var points := PackedVector2Array()
    for i in range(36):
        var a := TAU * float(i) / 36.0
        points.append(Vector2(cos(a) * radii.x, sin(a) * radii.y))
    _art_poly(parent, at, points, color)


func _art_cloud(parent: Node2D, at: Vector2, scale_factor: float) -> void:
    var cloud := Node2D.new()
    cloud.position = at
    cloud.scale = Vector2.ONE * scale_factor
    parent.add_child(cloud)
    _art_ellipse(cloud, Vector2(-26, 4), Vector2(31, 17), Color("#d7f1f4", 0.83))
    _art_ellipse(cloud, Vector2(-4, -8), Vector2(29, 25), Color("#ffffff", 0.94))
    _art_ellipse(cloud, Vector2(23, 0), Vector2(34, 20), Color("#effcff", 0.90))
    _art_ellipse(cloud, Vector2(2, 8), Vector2(40, 13), Color("#f7ffff", 0.86))


func _art_waterfall(parent: Node2D, at: Vector2, width: float, height: float) -> void:
    _art_poly(parent, at, [Vector2(0, 0), Vector2(width, 0), Vector2(width - 13, height), Vector2(10, height)], Color("#d2fbff", 0.48))
    _art_poly(parent, at + Vector2(width * 0.22, 0), [Vector2(0, 0), Vector2(width * 0.17, 0), Vector2(width * 0.22, height), Vector2(5, height)], Color("#f0ffff", 0.50))
    for i in range(8):
        var x := 4.0 + float(i) * width / 8.0
        _art_poly(parent, at, [Vector2(x, 0), Vector2(x + 2, 0), Vector2(x + 7, height), Vector2(x + 4, height)], Color("#ffffff", 0.28))
    _art_ellipse(parent, at + Vector2(width * 0.5, height), Vector2(width * 0.9, 12), Color("#e4ffff", 0.36))


func _art_palm(parent: Node2D, at: Vector2, scale_factor: float) -> void:
    var tree := Node2D.new()
    tree.position = at
    tree.scale = Vector2.ONE * scale_factor
    parent.add_child(tree)
    _art_poly(tree, Vector2.ZERO, [Vector2(-9, 0), Vector2(-7, -40), Vector2(-1, -82), Vector2(5, -113), Vector2(14, -109), Vector2(7, -69), Vector2(9, -35), Vector2(14, 0)], Color("#70472e"))
    _art_poly(tree, Vector2.ZERO, [Vector2(-5, -20), Vector2(-2, -76), Vector2(3, -107), Vector2(7, -106), Vector2(3, -70), Vector2(5, -20)], Color("#a36b3d"))
    var crown := Vector2(6, -108)
    for i in range(9):
        var a := -PI + float(i) * PI / 8.0
        var tip := crown + Vector2(cos(a) * 88, sin(a) * 46 - 5)
        _art_poly(tree, Vector2.ZERO, [crown, crown + Vector2(cos(a - 0.22) * 27, -15), tip, crown + Vector2(cos(a + 0.14) * 30, 6)], Color("#187846") if i % 2 == 0 else Color("#3eaa4c"))
        _art_poly(tree, Vector2.ZERO, [crown, crown + Vector2(cos(a) * 48, sin(a) * 22 - 4), tip], Color("#70c84c", 0.72))
    _art_ellipse(tree, crown, Vector2(10, 8), Color("#8a633a"))


func _art_temple(parent: Node2D, at: Vector2, scale_factor: float) -> void:
    var temple := Node2D.new()
    temple.position = at
    temple.scale = Vector2.ONE * scale_factor
    parent.add_child(temple)
    _art_poly(temple, Vector2.ZERO, [Vector2(-62, 0), Vector2(-62, -62), Vector2(-42, -76), Vector2(62, -68), Vector2(62, 0)], Color("#65513d"))
    _art_poly(temple, Vector2.ZERO, [Vector2(-60, 0), Vector2(-60, -67), Vector2(53, -67), Vector2(53, 0)], Color("#a08a68"))
    _art_poly(temple, Vector2.ZERO, [Vector2(-73, -65), Vector2(-8, -121), Vector2(69, -65)], Color("#5a4938"))
    _art_poly(temple, Vector2.ZERO, [Vector2(-58, -68), Vector2(-8, -108), Vector2(53, -68)], Color("#b29a6d"))
    for x in [-42.0, -12.0, 18.0, 42.0]:
        _art_poly(temple, Vector2.ZERO, [Vector2(x, -6), Vector2(x, -54), Vector2(x + 10, -54), Vector2(x + 10, -6)], Color("#544438"))
    for y in [-48.0, -28.0]:
        _art_poly(temple, Vector2.ZERO, [Vector2(-60, y), Vector2(53, y), Vector2(53, y + 5), Vector2(-60, y + 5)], Color("#c0a77a"))
    for i in range(5):
        _art_ellipse(temple, Vector2(-42 + i * 22, -76), Vector2(3, 3), Color("#574936"))


func _art_leaf_cluster(parent: Node2D, at: Vector2, scale_factor: float) -> void:
    var leaves := Node2D.new()
    leaves.position = at
    leaves.scale = Vector2.ONE * scale_factor
    parent.add_child(leaves)
    for i in range(5):
        var side := -1.0 if i % 2 == 0 else 1.0
        var y := -float((i * 13) % 25)
        _art_poly(leaves, Vector2.ZERO, [Vector2(0, 0), Vector2(side * (17 + i * 3), y - 23), Vector2(side * (30 + i * 2), y - 28), Vector2(side * 7, y + 4)], Color("#176c3b") if i % 2 == 0 else Color("#36a34a"))


func _art_flower(parent: Node2D, at: Vector2, scale_factor: float) -> void:
    var flower := Node2D.new()
    flower.position = at
    flower.scale = Vector2.ONE * scale_factor
    parent.add_child(flower)
    _art_poly(flower, Vector2.ZERO, [Vector2(0, 0), Vector2(-2, -14), Vector2(2, -23), Vector2(5, 0)], Color("#246b36"))
    var petal_color := Color("#ef4b87") if int(at.x) % 2 == 0 else Color("#f6c84d")
    for i in range(5):
        var a := TAU * float(i) / 5.0
        _art_ellipse(flower, Vector2(cos(a) * 5, -22 + sin(a) * 5), Vector2(4, 5), petal_color)
    _art_ellipse(flower, Vector2(0, -22), Vector2(3, 3), Color("#ffeaa2"))


func _art_crate(parent: Node2D, at: Vector2, size: float, explosive: bool) -> void:
    var box := Node2D.new()
    box.position = at
    parent.add_child(box)
    var base := Color("#a74432") if explosive else Color("#c48743")
    _art_poly(box, Vector2.ZERO, [Vector2.ZERO, Vector2(size, 0), Vector2(size, size), Vector2(0, size)], Color("#593a27"))
    _art_poly(box, Vector2(3, 3), [Vector2.ZERO, Vector2(size - 6, 0), Vector2(size - 6, size - 6), Vector2(0, size - 6)], base)
    _art_poly(box, Vector2.ZERO, [Vector2(5, 5), Vector2(size - 5, size - 5), Vector2(size - 10, size - 5), Vector2(5, 10)], Color("#edc16d"))
    _art_poly(box, Vector2.ZERO, [Vector2(size - 5, 5), Vector2(5, size - 5), Vector2(10, size - 5), Vector2(size - 5, 10)], Color("#edc16d"))
    _art_poly(box, Vector2.ZERO, [Vector2(5, 5), Vector2(size - 5, 5), Vector2(size - 8, 9), Vector2(8, 9)], Color("#f5d28a", 0.7))
    if explosive:
        var label := Label.new()
        label.text = "TNT"
        label.position = Vector2(1, size * 0.24)
        label.size = Vector2(size - 2, size * 0.5)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.add_theme_font_size_override("font_size", int(size * 0.34))
        label.add_theme_color_override("font_color", Color.WHITE)
        box.add_child(label)


func _art_fruit(parent: Node2D, at: Vector2, radius: float) -> void:
    _art_ellipse(parent, at + Vector2(0, 4), Vector2(radius + 2, radius + 1), Color("#b65a20"))
    _art_ellipse(parent, at, Vector2(radius, radius), Color("#ffbd20"))
    _art_ellipse(parent, at + Vector2(-3, -3), Vector2(radius * 0.55, radius * 0.62), Color("#fff078"))
    _art_poly(parent, at, [Vector2(0, -radius), Vector2(2, -radius - 8), Vector2(7, -radius - 9), Vector2(5, -radius - 3)], Color("#477d35"))


func _platform(pos: Vector2, size: Vector2, body_color: Color, top_color: Color) -> void:
    var body := StaticBody2D.new()
    body.position = pos + size / 2.0
    var collision := CollisionShape2D.new()
    var rectangle := RectangleShape2D.new()
    rectangle.size = size
    collision.shape = rectangle
    body.add_child(collision)
    var stone := ColorRect.new()
    stone.position = -size / 2.0
    stone.size = size
    stone.color = body_color
    body.add_child(stone)
    var moss := ColorRect.new()
    moss.position = Vector2(-size.x / 2.0, -size.y / 2.0)
    moss.size = Vector2(size.x, minf(12.0, size.y))
    moss.color = Color("#4d873c")
    body.add_child(moss)
    var grass := ColorRect.new()
    grass.position = Vector2(-size.x / 2.0, -size.y / 2.0)
    grass.size = Vector2(size.x, minf(7.0, size.y))
    grass.color = top_color
    body.add_child(grass)
    if size.x < 500.0:
        for x in range(7, int(size.x), 22):
            var seam := ColorRect.new()
            seam.position = Vector2(-size.x / 2.0 + x, -size.y / 2.0 + 12)
            seam.size = Vector2(2, maxf(2, size.y - 12))
            seam.color = Color("#51372b", 0.55)
            body.add_child(seam)
        for x in range(12, int(size.x), 34):
            _art_poly(body, Vector2(-size.x / 2.0 + x, -size.y / 2.0), [Vector2(0, 2), Vector2(7, -3), Vector2(15, 2)], Color("#c6b078", 0.65))
    world.add_child(body)

'''

source = source[:start] + art + "\n" + source[end:]
main_path.write_text(source, encoding="utf-8")
print("Installeret: jungle, vandfald, palmer, ruiner, detaljerede platforme, frugter og kasser.")
print(f"Backup: {backup.name}")
print("Genindlæs Godot og tryk Run Project.")
