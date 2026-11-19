extends Node3D
# BLACKLINE - Godot 4.3, Mobile renderer. The whole game is generated from code.

const H := 3.2
const CS_STYLE := true  # CS-like look: bright clean lighting, no bodycam post-process, green crosshair. Set false for the bodycam look.
const BODYCAM := """
shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear;
void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 c = uv - 0.5;
    float r2 = dot(c, c);
    vec2 p = clamp(0.5 + c * (1.0 + 0.34 * r2), vec2(0.002), vec2(0.998));
    vec2 o = c * 0.05 * r2;
    vec3 col = vec3(texture(scr, clamp(p + o, vec2(0.002), vec2(0.998))).r, texture(scr, p).g, texture(scr, clamp(p - o, vec2(0.002), vec2(0.998))).b);
    col *= 1.0 - 0.5 * smoothstep(0.1, 0.5, r2);
    col += (fract(sin(dot(uv * vec2(1731.0, 977.0) + TIME, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.035;
    col *= 1.0 + 0.02 * sin(TIME * 0.8) * sin(TIME * 2.3);
    float l = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(l), col, 0.88) * vec3(0.97, 1.03, 0.94);
    COLOR = vec4(col, 1.0);
}
"""
const SCOPE := """
shader_type canvas_item;
uniform float aspect = 2.0;
void fragment() {
    vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
    float r = length(p);
    float a = smoothstep(0.405, 0.42, r);
    float vg = smoothstep(0.3, 0.41, r) * 0.55;
    float ln = 0.0;
    if (r < 0.4) {
        if ((abs(p.y) < 0.0009 && abs(p.x) > 0.012) || (abs(p.x) < 0.0009 && abs(p.y) > 0.012)) { ln = 1.0; }
        if ((abs(p.y) < 0.004 && abs(p.x) > 0.25) || (abs(p.x) < 0.004 && abs(p.y) > 0.25)) { ln = 1.0; }
        for (int i = 1; i < 4; i++) {
            float f = float(i) * 0.05;
            if (length(p - vec2(f, 0.0)) < 0.003 || length(p + vec2(f, 0.0)) < 0.003 || length(p - vec2(0.0, f)) < 0.003 || length(p + vec2(0.0, f)) < 0.003) { ln = 1.0; }
        }
    }
    float cdot = step(length(p), 0.0016);
    COLOR = vec4(mix(vec3(0.0), vec3(0.85, 0.1, 0.1), cdot), max(max(a, vg), max(ln * 0.9, cdot)));
}
"""

var cam: Camera3D
var player: CharacterBody3D
var vm: Node3D
var vm_ak: Node3D
var vm_aw: Node3D
var flash: OmniLight3D
var flashm: MeshInstance3D
var wlbl: Label3D
var mats := {}
var astar := AStar3D.new()
var enemies: Array = []
var ui := {}
var rects := {}
var touches := {}
var move_v := Vector2.ZERO
var yaw := 0.0
var pitch := 0.0
var hp := 100.0
var stam := 1.0
var held := 0.0
var wk := 0
var ammo := [[30, 90], [5, 15]]
var cd := 0.0
var reload_t := 0.0
var ads := 0.0
var ads_on := false
var scoped := false
var crouch := false
var fire_held := false
var kills := 0
var total := 0
var started := false
var over := false
var t_rec := 0.0
var bob := 0.0
var kick := 0.0
var shot_pos := Vector3.ZERO
var shot_t := -99.0
var vel_h := Vector3.ZERO
var adapt_t := 0.0
var vcmat: StandardMaterial3D


func _ready() -> void:
    randomize()
    Engine.max_fps = 60
    var vp0 := get_viewport()
    vp0.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
    vp0.scaling_3d_scale = 0.75
    _env()
    _materials()
    _world()
    _details()
    _forest()
    _player()
    _ui()
    await get_tree().physics_frame
    await get_tree().physics_frame
    _graph()
    _spawn()


# ---------------------------------------------------------------- environment
func _env() -> void:
    var e := Environment.new()
    var sky := Sky.new()
    var sm := ProceduralSkyMaterial.new()
    sm.sky_top_color = Color(0.32, 0.5, 0.82) if CS_STYLE else Color(0.45, 0.55, 0.55)
    sm.sky_horizon_color = Color(0.75, 0.85, 0.95) if CS_STYLE else Color(0.72, 0.78, 0.68)
    sm.ground_horizon_color = Color(0.5, 0.55, 0.45)
    sm.ground_bottom_color = Color(0.25, 0.3, 0.22)
    sky.sky_material = sm
    e.sky = sky
    e.background_mode = Environment.BG_SKY
    e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    e.ambient_light_energy = 1.25 if CS_STYLE else 0.9
    e.tonemap_mode = Environment.TONE_MAPPER_LINEAR if CS_STYLE else Environment.TONE_MAPPER_ACES
    e.tonemap_exposure = 1.05
    e.glow_enabled = false
    e.glow_intensity = 0.5
    e.glow_bloom = 0.05
    e.fog_enabled = not CS_STYLE
    e.fog_light_color = Color(0.64, 0.7, 0.6)
    e.fog_density = 0.012
    e.adjustment_enabled = true
    e.adjustment_saturation = 1.1 if CS_STYLE else 0.85
    e.adjustment_contrast = 1.0 if CS_STYLE else 1.08
    var we := WorldEnvironment.new()
    we.environment = e
    add_child(we)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52, -30, 0)
    sun.light_energy = 1.7 if CS_STYLE else 1.25
    sun.light_color = Color(1, 0.94, 0.82)
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 45.0
    sun.shadow_blur = 0.4 if CS_STYLE else 1.0
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
    add_child(sun)


# ---------------------------------------------------------------- materials
func _tex(id: String, kind: String) -> Texture2D:
    var p := "res://tex/%s_1K-JPG_%s.jpg" % [id, kind]
    if id != "" and ResourceLoader.exists(p):
        return load(p)
    return null


func _noise(c1: Color, c2: Color, freq: float, sd: int, normal: bool) -> NoiseTexture2D:
    var n := FastNoiseLite.new()
    n.frequency = freq
    n.seed = sd
    n.fractal_octaves = 3
    var t := NoiseTexture2D.new()
    t.noise = n
    t.width = 256
    t.height = 256
    t.seamless = true
    if normal:
        t.as_normal_map = true
        t.bump_strength = 6.0
    else:
        var g := Gradient.new()
        g.colors = PackedColorArray([c1, c2])
        g.offsets = PackedFloat32Array([0.0, 1.0])
        t.color_ramp = g
    return t


func _mat(key: String, id: String, c1: Color, c2: Color, freq: float, sc: float, rough: float = 0.85, nrm: bool = false) -> void:
    var m := StandardMaterial3D.new()
    var col := _tex(id, "Color")
    if col != null:
        m.albedo_texture = col
        var nm: Texture2D = _tex(id, "NormalGL") if nrm else null
        if nm != null:
            m.normal_enabled = true
            m.normal_texture = nm
        var rg := _tex(id, "Roughness")
        if rg != null:
            m.roughness_texture = rg
    else:
        var sd := absi(key.hash()) % 9999
        m.albedo_texture = _noise(c1, c2, freq, sd, false)
        if nrm:
            m.normal_enabled = true
            m.normal_texture = _noise(c1, c2, freq * 2.0, sd + 1, true)
            m.normal_scale = 0.8
    m.roughness = rough
    m.uv1_triplanar = true
    m.uv1_world_triplanar = true
    m.uv1_scale = Vector3(sc, sc, sc)
    mats[key] = m


func _materials() -> void:
    _mat("wall", "PaintedPlaster017", Color(0.6, 0.57, 0.5), Color(0.85, 0.82, 0.72), 0.01, 0.3, 0.85, true)
    _mat("floor", "WoodFloor041", Color(0.2, 0.12, 0.06), Color(0.45, 0.3, 0.17), 0.02, 0.45, 0.6, true)
    _mat("ground", "Ground037", Color(0.16, 0.2, 0.09), Color(0.4, 0.36, 0.2), 0.006, 0.1, 0.95, true)
    _mat("bark", "Bark001", Color(0.12, 0.09, 0.06), Color(0.32, 0.24, 0.16), 0.03, 0.5)
    _mat("leaf", "", Color(0.1, 0.2, 0.06), Color(0.3, 0.45, 0.14), 0.05, 0.4, 0.9)
    _mat("conc", "Concrete034", Color(0.4, 0.4, 0.38), Color(0.62, 0.62, 0.58), 0.02, 0.25)
    _mat("wood", "", Color(0.2, 0.12, 0.07), Color(0.4, 0.26, 0.15), 0.03, 0.6, 0.6)
    _mat("fabric", "", Color(0.25, 0.3, 0.22), Color(0.4, 0.45, 0.33), 0.08, 0.8, 0.95)
    _mat("metal", "", Color(0.5, 0.52, 0.54), Color(0.7, 0.72, 0.74), 0.02, 0.6, 0.35)
    mats["metal"].metallic = 0.6
    _mat("trim", "", Color(0.78, 0.76, 0.7), Color(0.95, 0.93, 0.88), 0.02, 0.6, 0.45)
    var gm := StandardMaterial3D.new()
    gm.albedo_color = Color(0.7, 0.85, 0.9, 0.16)
    gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    gm.roughness = 0.05
    mats["glass"] = gm
    vcmat = StandardMaterial3D.new()
    vcmat.vertex_color_use_as_albedo = true
    vcmat.roughness = 0.75
    vcmat.cull_mode = BaseMaterial3D.CULL_DISABLED


# ---------------------------------------------------------------- world
func box(p: Vector3, s: Vector3, m: String, col: bool = true) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = s
    mi.mesh = bm
    mi.material_override = mats[m]
    mi.position = p
    add_child(mi)
    if col:
        var sb := StaticBody3D.new()
        var cs := CollisionShape3D.new()
        var sh := BoxShape3D.new()
        sh.size = s
        cs.shape = sh
        sb.add_child(cs)
        mi.add_child(sb)
    return mi


func _seg(p: Vector2, q: Vector2, y0: float, y1: float) -> void:
    if p.distance_to(q) < 0.05 or y1 - y0 < 0.05:
        return
    var c := (p + q) / 2.0
    var sx := maxf(absf(q.x - p.x), 0.3)
    var sz := maxf(absf(q.y - p.y), 0.3)
    box(Vector3(c.x, (y0 + y1) / 2.0, c.y), Vector3(sx, y1 - y0, sz), "wall")
    if y0 < 0.01:
        box(Vector3(c.x, 0.07, c.y), Vector3(sx + 0.05, 0.14, sz + 0.05), "trim", false)
    if y1 > H - 0.01:
        box(Vector3(c.x, H - 0.06, c.y), Vector3(sx + 0.05, 0.12, sz + 0.05), "trim", false)


# gaps: [center_along_wall, width, y_bottom, y_top]  (doors: y_bottom 0, windows: y_bottom 1.0)
func wall(a: Vector2, b: Vector2, gaps: Array = []) -> void:
    var ln := a.distance_to(b)
    var dir := (b - a) / ln
    var cuts: Array = [0.0]
    for g in gaps:
        cuts.append(g[0] - g[1] / 2.0)
        cuts.append(g[0] + g[1] / 2.0)
    cuts.append(ln)
    for i in range(0, cuts.size(), 2):
        _seg(a + dir * cuts[i], a + dir * cuts[i + 1], 0.0, H)
    for g in gaps:
        var c: Vector2 = a + dir * g[0]
        var hw: Vector2 = dir * g[1] / 2.0
        if g[2] > 0.0:
            _seg(c - hw, c + hw, 0.0, g[2])
        _seg(c - hw, c + hw, g[3], H)
        _frame(c, dir, g)


func _world() -> void:
    box(Vector3(0, -0.5, 0), Vector3(260, 1, 260), "ground")
    box(Vector3(0, -0.08, 0), Vector3(32, 0.2, 24), "floor")
    box(Vector3(0, H + 0.2, 0), Vector3(33, 0.4, 25), "conc")
    # exterior shell
    wall(Vector2(-16, 12), Vector2(16, 12), [[6, 2, 1.0, 2.5], [16, 2.8, 0, 2.5], [26, 2, 1.0, 2.5]])
    wall(Vector2(-16, -12), Vector2(16, -12), [[6, 2, 1.0, 2.5], [16, 2.4, 0, 2.5], [26, 2, 1.0, 2.5]])
    wall(Vector2(-16, -12), Vector2(-16, 12), [[5, 2, 1.0, 2.5], [12, 2, 1.0, 2.5], [19, 2, 1.0, 2.5]])
    wall(Vector2(16, -12), Vector2(16, 12), [[5, 2, 1.0, 2.5], [12, 2, 1.0, 2.5], [19, 2, 1.0, 2.5]])
    # hall walls (kitchen / living on the west, dining / office on the east)
    wall(Vector2(-3, -12), Vector2(-3, 8), [[6, 1.6, 0, 2.2], [14, 2.2, 0, 2.2]])
    wall(Vector2(3, -12), Vector2(3, 8), [[6, 1.6, 0, 2.2], [14, 2.2, 0, 2.2]])
    # front partition: foyer + two front rooms
    wall(Vector2(-16, 8), Vector2(16, 8), [[6.5, 1.4, 0, 2.2], [16, 2.8, 0, 2.5], [25.5, 1.4, 0, 2.2]])
    # wing dividers
    wall(Vector2(-16, -2), Vector2(-3, -2), [[6.5, 1.8, 0, 2.2]])
    wall(Vector2(3, -2), Vector2(16, -2), [[6.5, 1.8, 0, 2.2]])
    # furniture and tactical cover: [x, z, sx, sy, sz, material]
    var props := [
        [-11, 5, 3.0, 0.8, 1.1, "fabric"], [-11, 2.8, 1.4, 0.4, 0.8, "wood"], [-15.2, 2, 0.5, 2.0, 2.5, "wood"],
        [-13, -11.3, 6.0, 0.9, 0.6, "conc"], [-9, -7, 2.4, 0.9, 1.0, "wood"], [-15.3, -8, 0.7, 1.9, 0.7, "metal"],
        [9.5, -7, 4.0, 0.78, 1.3, "wood"], [8, -5.6, 0.5, 0.5, 0.5, "wood"], [11, -5.6, 0.5, 0.5, 0.5, "wood"],
        [8, -8.4, 0.5, 0.5, 0.5, "wood"], [11, -8.4, 0.5, 0.5, 0.5, "wood"], [15.3, -8, 0.6, 2.0, 3.0, "wood"],
        [13, 3, 2.0, 0.76, 0.9, "wood"], [15.5, 0, 0.4, 2.2, 4.0, "wood"], [8, 5, 2.4, 0.8, 1.0, "fabric"],
        [-13, 10, 2.0, 0.5, 1.8, "fabric"], [13, 10, 2.0, 0.5, 1.8, "fabric"], [0, 10.6, 2.0, 0.8, 0.5, "wood"],
        [0, -1.5, 1.8, 0.9, 0.2, "wood"], [-1.6, 5.5, 0.9, 1.0, 0.9, "wood"], [1.8, -6.5, 1.0, 1.0, 1.0, "wood"]
    ]
    for p in props:
        box(Vector3(p[0], p[3] / 2.0, p[1]), Vector3(p[2], p[3], p[4]), p[5])
    for l in [Vector2(-9.5, -7), Vector2(-9.5, 3), Vector2(9.5, -7), Vector2(9.5, 3), Vector2(0, -4), Vector2(0, 9)]:
        var o := OmniLight3D.new()
        o.position = Vector3(l.x, H - 0.4, l.y)
        o.omni_range = 11.0
        o.light_energy = 1.3
        o.light_color = Color(1, 0.88, 0.7)
        add_child(o)


func _mm(mesh: Mesh, xf: Array, shadows: bool = true) -> void:
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = mesh
    mm.instance_count = xf.size()
    for i in xf.size():
        mm.set_instance_transform(i, xf[i])
    var mi := MultiMeshInstance3D.new()
    mi.multimesh = mm
    if not shadows:
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mi)


func _forest() -> void:
    var trunks: Array = []
    var crowns: Array = []
    var tries := 0
    var count := 0
    while count < 45 and tries < 900:
        tries += 1
        var a := randf() * TAU
        var r := randf_range(24.0, 95.0)
        var p := Vector2(cos(a) * r * 1.2, sin(a) * r)
        if absf(p.x) < 5.0 and p.y > 12.0:
            continue
        count += 1
        trunks.append(Transform3D(Basis.IDENTITY, Vector3(p.x, 3.5, p.y)))
        crowns.append(Transform3D(Basis.IDENTITY.scaled(Vector3(5.0, 4.2, 5.0)), Vector3(p.x, 8.0, p.y)))
        crowns.append(Transform3D(Basis.IDENTITY.scaled(Vector3(3.6, 3.2, 3.6)), Vector3(p.x, 10.2, p.y)))
        var sb := StaticBody3D.new()
        var cs := CollisionShape3D.new()
        var sh := CylinderShape3D.new()
        sh.radius = 0.3
        sh.height = 7.0
        cs.shape = sh
        cs.position.y = 3.5
        sb.add_child(cs)
        sb.position = Vector3(p.x, 0, p.y)
        add_child(sb)
    var cyl := CylinderMesh.new()
    cyl.top_radius = 0.18
    cyl.bottom_radius = 0.3
    cyl.height = 7.0
    cyl.radial_segments = 7
    cyl.rings = 1
    cyl.material = mats["bark"]
    _mm(cyl, trunks)
    var sp := SphereMesh.new()
    sp.radius = 0.5
    sp.height = 1.0
    sp.radial_segments = 10
    sp.rings = 6
    sp.material = mats["leaf"]
    _mm(sp, crowns)
    var bushes: Array = []
    var rocks: Array = []
    for i in 120:
        var p := Vector2(randf_range(-100, 100), randf_range(-100, 100))
        if absf(p.x) < 17.5 and absf(p.y) < 13.5:
            continue
        if absf(p.x) < 4.0 and p.y > 12.0:
            continue
        if i < 90:
            bushes.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.8, 1.1, 1.8)), Vector3(p.x, 0.4, p.y)))
        else:
            rocks.append(Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(1.3, 0.8, 1.6)), Vector3(p.x, 0.2, p.y)))
    _mm(sp, bushes)
    var rm := SphereMesh.new()
    rm.radius = 0.5
    rm.height = 1.0
    rm.radial_segments = 8
    rm.rings = 5
    rm.material = mats["conc"]
    _mm(rm, rocks)


# ---------------------------------------------------------------- detail pass (frames, glass, art, ivy, grass)
func _frame(c: Vector2, dir: Vector2, g: Array) -> void:
    var w: float = g[1]
    var y0: float = g[2]
    var y1: float = g[3]
    var along := absf(dir.x) > 0.5
    var t := 0.06
    var parts: Array = [
        [-(w - t) / 2.0, (y0 + y1) / 2.0, t, y1 - y0],
        [(w - t) / 2.0, (y0 + y1) / 2.0, t, y1 - y0],
        [0.0, y1 - t / 2.0, w, t]
    ]
    if y0 > 0.0:
        parts.append([0.0, y0 + t / 2.0, w, t])
        parts.append([0.0, (y0 + y1) / 2.0, t * 0.6, y1 - y0])
    for pt in parts:
        var off: Vector2 = dir * pt[0]
        var sz := Vector3(pt[2], pt[3], 0.36) if along else Vector3(0.36, pt[3], pt[2])
        box(Vector3(c.x + off.x, pt[1], c.y + off.y), sz, "trim", false)
    if y0 > 0.0:
        var gl := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(w, y1 - y0, 0.02) if along else Vector3(0.02, y1 - y0, w)
        gl.mesh = bm
        gl.material_override = mats["glass"]
        gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        gl.position = Vector3(c.x, (y0 + y1) / 2.0, c.y)
        add_child(gl)


func _alpha_mat(tx: Texture2D) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_texture = tx
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
    m.alpha_scissor_threshold = 0.5
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    m.roughness = 0.9
    return m


func _ivy_tex() -> ImageTexture:
    var im := Image.create(128, 128, false, Image.FORMAT_RGBA8)
    im.fill(Color(0, 0, 0, 0))
    for i in 70:
        var cx := randi_range(8, 120)
        var cy := randi_range(8, 120)
        var rr := randi_range(4, 8)
        var col := Color(randf_range(0.1, 0.22), randf_range(0.28, 0.5), randf_range(0.06, 0.14), 1.0)
        for x in range(cx - rr, cx + rr + 1):
            for y in range(cy - rr, cy + rr + 1):
                if x >= 0 and x < 128 and y >= 0 and y < 128:
                    var dx := float(x - cx) / rr
                    var dy := float(y - cy) / (rr * 0.65)
                    if dx * dx + dy * dy < 1.0:
                        im.set_pixel(x, y, col)
    return ImageTexture.create_from_image(im)


func _grass_tex() -> ImageTexture:
    var im := Image.create(64, 64, false, Image.FORMAT_RGBA8)
    im.fill(Color(0, 0, 0, 0))
    for i in 16:
        var x0 := randf_range(8.0, 56.0)
        var hgt := randi_range(26, 62)
        var lean := randf_range(-0.35, 0.35)
        var col := Color(randf_range(0.18, 0.32), randf_range(0.38, 0.6), randf_range(0.08, 0.16), 1.0)
        for s in hgt:
            var t := float(s) / hgt
            var px := int(x0 + lean * s)
            var w := 2 if t < 0.6 else 1
            for k in w:
                if px + k >= 0 and px + k < 64:
                    im.set_pixel(px + k, 63 - s, col.darkened(0.3 * (1.0 - t)))
    return ImageTexture.create_from_image(im)


func _art(p: Vector3, on_x: bool, w: float, h: float, c: Color) -> void:
    var fs := Vector3(0.05, h, w) if on_x else Vector3(w, h, 0.05)
    box(p, fs, "wood", false)
    var inn := Vector3(0.07, h - 0.12, w - 0.12) if on_x else Vector3(w - 0.12, h - 0.12, 0.07)
    _vp(self, p, inn, c, 0.8)


func _details() -> void:
    for a in [[-2.83, -8.0, 0.5], [-2.83, 6.0, 0.45], [2.83, -8.0, 0.4], [2.83, 6.0, 0.35]]:
        _art(Vector3(a[0], 1.75, a[1]), true, 1.0, 0.7, Color(a[2], a[2] * 0.75, a[2] * 0.5))
    _art(Vector3(-15.83, 1.75, 5.0), true, 1.8, 1.1, Color(0.22, 0.3, 0.26))
    _art(Vector3(9.5, 1.8, -11.83), false, 2.2, 1.0, Color(0.32, 0.26, 0.2))
    _art(Vector3(-9.5, 1.8, -11.83), false, 1.2, 0.8, Color(0.28, 0.3, 0.36))
    var ivy := _alpha_mat(_ivy_tex())
    var ixf: Array = []
    for i in 26:
        var side := randi() % 4
        var along := randf_range(-14.5, 14.5)
        if side < 2 and absf(along) < 1.8:
            continue
        var pos := Vector3(along, 0.0, 12.18)
        var yaw := 0.0
        if side == 1:
            pos = Vector3(along, 0.0, -12.18)
            yaw = PI
        elif side == 2:
            pos = Vector3(-16.18, 0.0, along * 0.8)
            yaw = -PI / 2.0
        elif side == 3:
            pos = Vector3(16.18, 0.0, along * 0.8)
            yaw = PI / 2.0
        var sw := randf_range(1.6, 2.6)
        var sh := randf_range(1.4, 3.0)
        ixf.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sw, sh, 1.0)), pos + Vector3(0.0, sh / 2.0, 0.0)))
    var iq := QuadMesh.new()
    iq.size = Vector2(1.0, 1.0)
    iq.material = ivy
    _mm(iq, ixf, false)
    var gmat := _alpha_mat(_grass_tex())
    for rot in [0.0, PI / 2.0]:
        var xf: Array = []
        for i in 220:
            var p := Vector2(randf_range(-45.0, 45.0), randf_range(-45.0, 45.0))
            if absf(p.x) < 18.5 and absf(p.y) < 14.5:
                continue
            if absf(p.x) < 2.5 and p.y > 12.0:
                continue
            xf.append(Transform3D(Basis(Vector3.UP, rot + randf() * 0.4), Vector3(p.x, 0.0, p.y)))
        var qm := QuadMesh.new()
        qm.size = Vector2(1.2, 0.8)
        qm.center_offset = Vector3(0.0, 0.4, 0.0)
        qm.material = gmat
        _mm(qm, xf, false)


# ---------------------------------------------------------------- merged vertex-colour meshes
func _sbox(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
    var h := s / 2.0
    var faces := [
        [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
        [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
        [Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
        [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
        [Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
        [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]
    ]
    for f in faces:
        var n: Vector3 = f[0]
        var u: Vector3 = f[1] * h
        var v: Vector3 = f[2] * h
        var o: Vector3 = n * h
        var p0 := c + o - u - v
        var p1 := c + o + u - v
        var p2 := c + o + u + v
        var p3 := c + o - u + v
        for p in [p0, p1, p2, p0, p2, p3]:
            st.set_color(col)
            st.set_normal(n)
            st.add_vertex(p)


func _vmesh(parts: Array) -> MeshInstance3D:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for p in parts:
        _sbox(st, p[0], p[1], p[2])
    var mi := MeshInstance3D.new()
    mi.mesh = st.commit()
    mi.material_override = vcmat
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return mi


# ---------------------------------------------------------------- player + viewmodel
func _vp(par: Node3D, p: Vector3, s: Vector3, c: Color, rough: float = 0.5, metal: float = 0.0) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = s
    mi.mesh = bm
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = rough
    m.metallic = metal
    mi.material_override = m
    mi.position = p
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    par.add_child(mi)
    return mi


func _player() -> void:
    player = CharacterBody3D.new()
    player.position = Vector3(0, 0.05, 28)
    add_child(player)
    var cs := CollisionShape3D.new()
    var cap := CapsuleShape3D.new()
    cap.radius = 0.32
    cap.height = 1.8
    cs.shape = cap
    cs.position.y = 0.9
    player.add_child(cs)
    cam = Camera3D.new()
    cam.position = Vector3(0, 1.62, 0)
    cam.fov = 78.0
    cam.near = 0.04
    cam.far = 160.0
    player.add_child(cam)
    cam.current = true
    vm = Node3D.new()
    cam.add_child(vm)
    var dark := Color(0.1, 0.1, 0.11)
    var wood := Color(0.33, 0.19, 0.1)
    var glove := Color(0.05, 0.05, 0.05)
    var fa := Node3D.new()
    fa.position = Vector3(-0.1, -0.13, -0.1)
    fa.rotation_degrees = Vector3(8, -18, 0)
    vm.add_child(fa)
    fa.add_child(_vmesh([
        [Vector3.ZERO, Vector3(0.07, 0.07, 0.36), Color(0.2, 0.22, 0.17)],
        [Vector3(0, 0, 0.07), Vector3(0.078, 0.078, 0.03), glove],
        [Vector3(0, 0.042, 0.07), Vector3(0.056, 0.014, 0.062), Color(0.16, 0.17, 0.18)],
        [Vector3(0, 0.05, 0.07), Vector3(0.04, 0.003, 0.03), Color(0.3, 0.8, 0.35)]
    ]))
    wlbl = Label3D.new()
    wlbl.text = "00:00"
    wlbl.pixel_size = 0.0006
    wlbl.font_size = 36
    wlbl.modulate = Color(0.65, 1.0, 0.55)
    wlbl.shaded = false
    wlbl.position = Vector3(0, 0.052, 0.07)
    wlbl.rotation_degrees = Vector3(-90, 0, 0)
    fa.add_child(wlbl)
    vm_ak = Node3D.new()
    vm.add_child(vm_ak)
    vm_ak.add_child(_vmesh([
        [Vector3(0, 0, 0), Vector3(0.05, 0.07, 0.46), dark],
        [Vector3(0, 0.045, 0.02), Vector3(0.045, 0.02, 0.4), dark],
        [Vector3(0, 0.012, -0.42), Vector3(0.022, 0.022, 0.4), dark],
        [Vector3(0, 0.04, -0.6), Vector3(0.012, 0.04, 0.012), dark],
        [Vector3(0, 0.04, -0.28), Vector3(0.02, 0.02, 0.3), dark],
        [Vector3(0, -0.005, -0.27), Vector3(0.06, 0.065, 0.26), wood],
        [Vector3(0, -0.12, 0.04), Vector3(0.04, 0.17, 0.08), dark],
        [Vector3(0, -0.03, 0.34), Vector3(0.045, 0.09, 0.24), wood],
        [Vector3(0, -0.09, 0.14), Vector3(0.04, 0.1, 0.05), wood],
        [Vector3(0, -0.1, 0.17), Vector3(0.07, 0.08, 0.1), glove],
        [Vector3(0, -0.03, -0.27), Vector3(0.075, 0.075, 0.14), glove]
    ]))
    vm_aw = Node3D.new()
    vm_aw.visible = false
    vm.add_child(vm_aw)
    vm_aw.add_child(_vmesh([
        [Vector3(0, 0, 0), Vector3(0.055, 0.075, 0.62), Color(0.12, 0.14, 0.11)],
        [Vector3(0, 0.01, -0.62), Vector3(0.026, 0.026, 0.62), dark],
        [Vector3(0, 0.012, -0.96), Vector3(0.04, 0.04, 0.1), dark],
        [Vector3(0, 0.085, -0.02), Vector3(0.05, 0.05, 0.3), dark],
        [Vector3(0, 0.085, 0.14), Vector3(0.062, 0.062, 0.05), dark],
        [Vector3(0, 0.085, -0.18), Vector3(0.062, 0.062, 0.05), dark],
        [Vector3(0, -0.04, 0.42), Vector3(0.05, 0.12, 0.3), Color(0.12, 0.14, 0.11)],
        [Vector3(0, -0.1, 0.04), Vector3(0.04, 0.1, 0.08), dark],
        [Vector3(0, -0.1, 0.2), Vector3(0.07, 0.08, 0.1), glove],
        [Vector3(0, -0.03, -0.3), Vector3(0.075, 0.075, 0.14), glove]
    ]))
    flash = OmniLight3D.new()
    flash.omni_range = 7.0
    flash.light_energy = 0.0
    flash.light_color = Color(1, 0.8, 0.5)
    vm.add_child(flash)
    flashm = MeshInstance3D.new()
    var fm := SphereMesh.new()
    fm.radius = 0.04
    fm.height = 0.08
    var fmat := StandardMaterial3D.new()
    fmat.albedo_color = Color(1, 0.85, 0.4)
    fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    fm.material = fmat
    flashm.mesh = fm
    flashm.visible = false
    flashm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    vm.add_child(flashm)


# ---------------------------------------------------------------- UI (touch HUD + bodycam)
func _lbl(txt: String, pos: Vector2, size: int, col: Color = Color.WHITE) -> Label:
    var l := Label.new()
    l.text = txt
    l.position = pos
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", col)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l


func _rect(c: Color) -> ColorRect:
    var r := ColorRect.new()
    r.color = c
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return r


func _ui() -> void:
    var sz := get_viewport().get_visible_rect().size
    var u := sz.y / 1080.0
    var post := CanvasLayer.new()
    post.layer = 1
    add_child(post)
    var sh := Shader.new()
    sh.code = BODYCAM
    var sm := ShaderMaterial.new()
    sm.shader = sh
    var cr := _rect(Color.WHITE)
    cr.set_anchors_preset(Control.PRESET_FULL_RECT)
    cr.material = sm
    cr.visible = not CS_STYLE
    post.add_child(cr)
    var sh2 := Shader.new()
    sh2.code = SCOPE
    var sm2 := ShaderMaterial.new()
    sm2.shader = sh2
    sm2.set_shader_parameter("aspect", sz.x / sz.y)
    var sc := _rect(Color.WHITE)
    sc.set_anchors_preset(Control.PRESET_FULL_RECT)
    sc.material = sm2
    sc.visible = false
    post.add_child(sc)
    ui["scope"] = sc
    var hud := CanvasLayer.new()
    hud.layer = 2
    add_child(hud)
    ui["rec"] = _lbl("● REC", Vector2(46, 30) * u, int(30 * u), Color(0.95, 0.15, 0.12))
    ui["tc"] = _lbl("00:00:00", Vector2(190, 30) * u, int(30 * u))
    ui["hp"] = _lbl("HP 100", Vector2(46, 78) * u, int(28 * u), Color(0.7, 1.0, 0.7))
    ui["obj"] = _lbl("", Vector2(sz.x / 2.0 - 190 * u, 30 * u), int(28 * u))
    ui["ammo"] = _lbl("", Vector2(sz.x - 420 * u, 30 * u), int(40 * u))
    ui["fps"] = _lbl("", Vector2(sz.x - 420 * u, 84 * u), int(24 * u), Color(0.7, 1.0, 0.7))
    ui["gain"] = _lbl("", Vector2(sz.x / 2.0 - 120 * u, sz.y * 0.72), int(30 * u), Color(0.72, 0.92, 0.75))
    ui["hit"] = _lbl("X", Vector2(sz.x / 2.0 - 12 * u, sz.y / 2.0 - 22 * u), int(34 * u), Color(1, 0.3, 0.2))
    ui["hit"].modulate.a = 0.0
    if CS_STYLE:
        ui["hp"].position = Vector2(46, sz.y - 150 * u)
        ui["hp"].add_theme_font_size_override("font_size", int(44 * u))
    for k in ["rec", "tc", "hp", "obj", "ammo", "fps", "gain", "hit"]:
        hud.add_child(ui[k])
    var dot := _rect(Color(1, 1, 1, 0.8))
    dot.size = Vector2(5, 5) * u
    dot.position = sz / 2.0 - dot.size / 2.0
    hud.add_child(dot)
    ui["dot"] = dot
    if CS_STYLE:
        dot.color = Color(0, 0, 0, 0)
        ui["rec"].visible = false
        ui["tc"].visible = false
        for b in [[-16.0, 1.5, 10.0, 2.0], [11.0, 1.5, 10.0, 2.0], [1.5, -16.0, 2.0, 10.0], [1.5, 11.0, 2.0, 10.0]]:
            var bar := _rect(Color(0.2, 1.0, 0.3, 0.95))
            bar.position = Vector2(b[0], b[1]) * u
            bar.size = Vector2(b[2], b[3]) * u
            dot.add_child(bar)
    var dm := _rect(Color(0.7, 0, 0, 0.0))
    dm.set_anchors_preset(Control.PRESET_FULL_RECT)
    hud.add_child(dm)
    ui["dmg"] = dm
    var bs := 150.0 * u
    var defs := {
        "fire": [sz.x - bs * 1.3, sz.y - bs * 1.5, "FIRE"],
        "ads": [sz.x - bs * 2.6, sz.y - bs * 1.2, "AIM"],
        "reload": [sz.x - bs * 1.3, sz.y - bs * 3.0, "RELOAD"],
        "swap": [sz.x - bs * 2.7, sz.y - bs * 2.5, "SWAP"],
        "crouch": [sz.x - bs * 4.0, sz.y - bs * 1.2, "CROUCH"]
    }
    for k in defs:
        var r := Rect2(defs[k][0], defs[k][1], bs, bs)
        rects[k] = r
        var b := _rect(Color(1, 1, 1, 0.13))
        b.position = r.position
        b.size = r.size
        hud.add_child(b)
        b.add_child(_lbl(defs[k][2], Vector2(8, bs * 0.38), int(26 * u)))
    var st := _rect(Color.BLACK)
    st.set_anchors_preset(Control.PRESET_FULL_RECT)
    st.add_child(_lbl("BLACKLINE\nTAP TO DEPLOY", Vector2(sz.x / 2.0 - 230 * u, sz.y / 2.0 - 80 * u), int(56 * u)))
    hud.add_child(st)
    ui["start"] = st
    ui["msg"] = _lbl("", Vector2(sz.x / 2.0 - 380 * u, sz.y / 2.0 - 60 * u), int(52 * u), Color(1, 0.4, 0.3))
    hud.add_child(ui["msg"])


func _gain(t: String) -> void:
    ui["gain"].text = t
    ui["gain"].modulate.a = 1.0
    create_tween().tween_property(ui["gain"], "modulate:a", 0.0, 1.8)


# ---------------------------------------------------------------- touch input
func _input(ev: InputEvent) -> void:
    if ev is InputEventScreenTouch:
        var t := ev as InputEventScreenTouch
        if t.pressed:
            if not started:
                started = true
                ui["start"].visible = false
                return
            if over:
                get_tree().reload_current_scene()
                return
            var role := ""
            for k in rects:
                if rects[k].has_point(t.position):
                    role = k
            if role == "":
                role = "move" if t.position.x < get_viewport().get_visible_rect().size.x * 0.4 else "look"
            touches[t.index] = {"r": role, "o": t.position}
            _btn_down(role)
        elif touches.has(t.index):
            var rr: String = touches[t.index].r
            if rr == "move":
                move_v = Vector2.ZERO
            elif rr == "fire":
                fire_held = false
            touches.erase(t.index)
    elif ev is InputEventScreenDrag:
        var d := ev as InputEventScreenDrag
        if touches.has(d.index):
            var tc: Dictionary = touches[d.index]
            if tc.r == "move":
                move_v = ((d.position - tc.o) / 90.0).limit_length(1.0)
            elif tc.r == "look":
                var k := 0.0042 * (0.22 if scoped else (0.6 if ads > 0.5 else 1.0))
                yaw -= d.relative.x * k
                pitch = clampf(pitch - d.relative.y * k, -1.4, 1.4)


func _btn_down(role: String) -> void:
    if role == "fire":
        fire_held = true
        if wk == 1:
            _fire()
    elif role == "ads":
        if wk == 1:
            scoped = not scoped
        else:
            ads_on = not ads_on
    elif role == "reload":
        _reload()
    elif role == "swap":
        wk = 1 - wk
        vm_ak.visible = wk == 0
        vm_aw.visible = wk == 1
        scoped = false
        ads_on = false
        reload_t = 0.0
    elif role == "crouch":
        crouch = not crouch


# ---------------------------------------------------------------- weapons
func _reload() -> void:
    var a: Array = ammo[wk]
    var mx := 30 if wk == 0 else 5
    if reload_t > 0.0 or a[0] >= mx or a[1] <= 0:
        return
    reload_t = 2.2 if wk == 0 else 3.4
    scoped = false


func _fire() -> void:
    if reload_t > 0.0 or cd > 0.0 or over:
        return
    var a: Array = ammo[wk]
    if a[0] <= 0:
        _reload()
        return
    a[0] -= 1
    cd = 0.1 if wk == 0 else 1.5
    kick = 1.0
    pitch += (randf_range(0.004, 0.009) if wk == 0 else 0.035)
    yaw += randf_range(-0.004, 0.004)
    shot_pos = player.global_position
    shot_t = Time.get_ticks_msec() / 1000.0
    var sp := (0.012 if (ads > 0.5 or scoped) else 0.03) + (0.02 if move_v.length() > 0.1 else 0.0)
    var bs := cam.global_transform.basis
    var dir := (-bs.z + bs.x * randf_range(-sp, sp) + bs.y * randf_range(-sp, sp)).normalized()
    var org := cam.global_position
    var q := PhysicsRayQueryParameters3D.create(org, org + dir * 150.0)
    q.exclude = [player.get_rid()]
    var r := get_world_3d().direct_space_state.intersect_ray(q)
    if not r.is_empty():
        _hit(r)
    _flash()


func _flash() -> void:
    flash.position = Vector3(0, 0.012, -0.68 if wk == 0 else -1.05)
    flashm.position = flash.position
    flash.light_energy = 4.0
    flashm.visible = true
    await get_tree().create_timer(0.04).timeout
    flash.light_energy = 0.0
    flashm.visible = false


func _hit(r: Dictionary) -> void:
    var c = r.collider
    if c.is_in_group("enemy"):
        var d: Dictionary = c.get_meta("d")
        if d.dead:
            return
        var head: bool = r.position.y - c.global_position.y > 1.5
        d.hp -= (34.0 if wk == 0 else 150.0) * (2.2 if head else 1.0)
        d.st = 2
        d.last = player.global_position
        ui["hit"].modulate.a = 1.0
        create_tween().tween_property(ui["hit"], "modulate:a", 0.0, 0.25)
        if d.hp <= 0.0:
            _kill(c, d)


func _kill(e: CharacterBody3D, d: Dictionary) -> void:
    d.dead = true
    kills += 1
    e.get_child(0).set_deferred("disabled", true)
    create_tween().tween_property(d.body, "rotation:x", -1.5, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    var idx := 1 if d.sn else 0
    var n := 2 if d.sn else 15
    ammo[idx][1] += n
    _gain("+%d %s" % [n, ".338" if d.sn else "7.62"])
    get_tree().create_timer(40.0).timeout.connect(e.queue_free)


func _hurt(n: float) -> void:
    if over:
        return
    hp -= n
    ui["dmg"].color.a = 0.35
    create_tween().tween_property(ui["dmg"], "color:a", 0.0, 0.4)
    if hp <= 0.0:
        over = true
        ui["msg"].text = "KIA - TAP TO RESTART"


# ---------------------------------------------------------------- enemies + AI
func _graph() -> void:
    var pts := [
        Vector2(0, 10), Vector2(0, 4), Vector2(0, -3), Vector2(0, -9), Vector2(-9.5, 10), Vector2(9.5, 10),
        Vector2(-9.5, 3), Vector2(-9.5, -7), Vector2(9.5, 3), Vector2(9.5, -7), Vector2(-3, 2), Vector2(3, 2),
        Vector2(-3, -6), Vector2(3, -6), Vector2(-9.5, -2), Vector2(9.5, -2), Vector2(-9.5, 8), Vector2(9.5, 8),
        Vector2(0, 8), Vector2(0, 12), Vector2(0, 16), Vector2(-8, 18), Vector2(8, 18), Vector2(-21, 6),
        Vector2(21, 6), Vector2(-21, -8), Vector2(21, -8), Vector2(0, -16), Vector2(0, -12), Vector2(0, 26)
    ]
    for i in pts.size():
        astar.add_point(i, Vector3(pts[i].x, 0.1, pts[i].y))
    var sp := get_world_3d().direct_space_state
    for i in pts.size():
        for j in range(i + 1, pts.size()):
            var a := astar.get_point_position(i)
            var b := astar.get_point_position(j)
            if a.distance_to(b) < 13.0:
                var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 0.9, 0), b + Vector3(0, 0.9, 0))
                if sp.intersect_ray(q).is_empty():
                    astar.connect_points(i, j)


func _spawn() -> void:
    for p in [Vector3(-12, 0, -8), Vector3(11, 0, -8), Vector3(-9, 0, 4), Vector3(12, 0, 4), Vector3(0, 0, -8), Vector3(0, 0, 9), Vector3(-12, 0, 10), Vector3(12, 0, 10), Vector3(14, 0, 18)]:
        _enemy(p, false)
    _enemy(Vector3(-21, 0, -9), true)
    total = enemies.size()


func _face_mat() -> StandardMaterial3D:
    var im := Image.create(6, 6, false, Image.FORMAT_RGB8)
    for x in 6:
        for y in 6:
            var v := randf_range(0.28, 0.62)
            im.set_pixel(x, y, Color(v, v * 0.85, v * 0.75))
    var m := StandardMaterial3D.new()
    m.albedo_texture = ImageTexture.create_from_image(im)
    m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    return m


func _enemy(pos: Vector3, sniper: bool) -> void:
    var e := CharacterBody3D.new()
    e.position = pos
    e.add_to_group("enemy")
    add_child(e)
    var cs := CollisionShape3D.new()
    var cap := CapsuleShape3D.new()
    cap.radius = 0.32
    cap.height = 1.75
    cs.shape = cap
    cs.position.y = 0.875
    e.add_child(cs)
    var body := Node3D.new()
    e.add_child(body)
    var cm := Color(0.28, 0.3, 0.22) if not sniper else Color(0.24, 0.28, 0.18)
    var tn := Color(0.42, 0.36, 0.26)
    var blk := Color(0.1, 0.1, 0.11)
    var oli := Color(0.2, 0.23, 0.17)
    var gl := 0.7 if not sniper else 1.25
    var parts: Array = [
        [Vector3(0, 1.2, 0), Vector3(0.42, 0.5, 0.24), cm],
        [Vector3(0, 1.22, -0.03), Vector3(0.46, 0.44, 0.3), tn],
        [Vector3(0, 1.22, 0.1), Vector3(0.44, 0.42, 0.08), tn],
        [Vector3(0, 0.98, 0), Vector3(0.5, 0.14, 0.3), oli],
        [Vector3(-0.12, 1.1, -0.18), Vector3(0.09, 0.14, 0.07), oli],
        [Vector3(0, 1.1, -0.18), Vector3(0.09, 0.14, 0.07), oli],
        [Vector3(0.12, 1.1, -0.18), Vector3(0.09, 0.14, 0.07), oli],
        [Vector3(0.2, 1.42, 0.06), Vector3(0.07, 0.16, 0.08), blk],
        [Vector3(0, 1.2, 0.2), Vector3(0.36, 0.42, 0.16), oli],
        [Vector3(0, 1.43, 0), Vector3(0.14, 0.08, 0.14), blk],
        [Vector3(0, 1.56, 0), Vector3(0.19, 0.22, 0.2), Color(0.5, 0.4, 0.33)],
        [Vector3(0, 1.5, 0), Vector3(0.2, 0.11, 0.21), blk],
        [Vector3(0, 1.68, 0), Vector3(0.27, 0.13, 0.29), Color(0.13, 0.14, 0.12)],
        [Vector3(0, 1.64, -0.14), Vector3(0.25, 0.04, 0.06), Color(0.13, 0.14, 0.12)],
        [Vector3(0, 1.7, -0.16), Vector3(0.1, 0.06, 0.07), blk],
        [Vector3(0, 1.62, -0.13), Vector3(0.22, 0.05, 0.04), blk],
        [Vector3(-0.14, 1.58, 0), Vector3(0.05, 0.1, 0.1), tn],
        [Vector3(0.14, 1.58, 0), Vector3(0.05, 0.1, 0.1), tn],
        [Vector3(-0.31, 1.28, -0.02), Vector3(0.11, 0.34, 0.13), cm],
        [Vector3(0.31, 1.3, -0.1), Vector3(0.11, 0.3, 0.13), cm],
        [Vector3(0.28, 1.15, -0.32), Vector3(0.1, 0.1, 0.42), cm],
        [Vector3(-0.14, 1.18, -0.4), Vector3(0.1, 0.1, 0.48), cm],
        [Vector3(0.28, 1.15, -0.55), Vector3(0.1, 0.1, 0.12), blk],
        [Vector3(-0.12, 1.2, -0.66), Vector3(0.1, 0.1, 0.12), blk],
        [Vector3(0.1, 1.2, -0.5), Vector3(0.06, 0.09, 0.36), blk],
        [Vector3(0.1, 1.22, -0.5 - gl * 0.5), Vector3(0.03, 0.03, gl), blk],
        [Vector3(0.1, 1.2, -0.2), Vector3(0.06, 0.1, 0.2), blk],
        [Vector3(0.1, 1.08, -0.5), Vector3(0.04, 0.16, 0.08), blk],
        [Vector3(0.1, 1.29, -0.5), Vector3(0.05, 0.06, 0.12 if not sniper else 0.3), blk]
    ]
    var bm := _vmesh(parts)
    bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    body.add_child(bm)
    var face := MeshInstance3D.new()
    var qm := QuadMesh.new()
    qm.size = Vector2(0.15, 0.08)
    face.mesh = qm
    face.material_override = _face_mat()
    face.position = Vector3(0, 1.56, -0.102)
    face.rotation.y = PI
    body.add_child(face)
    var legs: Array = []
    for s in [-1.0, 1.0]:
        var pv := Node3D.new()
        pv.position = Vector3(s * 0.11, 0.9, 0)
        body.add_child(pv)
        var lm := _vmesh([
            [Vector3(0, -0.45, 0), Vector3(0.17, 0.9, 0.19), cm.darkened(0.15)],
            [Vector3(0, -0.5, -0.1), Vector3(0.15, 0.14, 0.06), blk],
            [Vector3(0, -0.84, -0.03), Vector3(0.17, 0.14, 0.27), blk],
            [Vector3(s * 0.09, -0.25, 0), Vector3(0.06, 0.14, 0.12), tn]
        ])
        lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        pv.add_child(lm)
        legs.append(pv)
    e.set_meta("d", {"hp": 100.0, "st": 0, "path": [], "t": 0.0, "rep": 0.0, "vel": Vector3.ZERO, "last": pos, "exp": 0.0, "lost": 0.0, "cd": 1.0, "burst": 0, "dead": false, "sn": sniper, "ph": 0.0, "legs": legs, "body": body, "hear": -9.0})
    enemies.append(e)


func _clear(a: Vector3, b: Vector3, ex: CharacterBody3D) -> bool:
    var q := PhysicsRayQueryParameters3D.create(a, b)
    q.exclude = [ex.get_rid()]
    var r := get_world_3d().direct_space_state.intersect_ray(q)
    return r.is_empty() or r.collider == player


func _path(e: CharacterBody3D, d: Dictionary, target: Vector3) -> void:
    var a := astar.get_closest_point(e.global_position)
    var b := astar.get_closest_point(target)
    d.path = Array(astar.get_point_path(a, b))


func _cover(e: CharacterBody3D) -> Vector3:
    var best := e.global_position
    var bd := 1e9
    var pe := player.global_position + Vector3(0, 1.4, 0)
    for i in astar.get_point_count():
        var p := astar.get_point_position(i)
        var dd := p.distance_to(e.global_position)
        if dd < 3.0 or dd > 16.0 or dd >= bd:
            continue
        var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.4, 0), pe)
        if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
            best = p
            bd = dd
    return best


func _shoot(d: Dictionary, dt: float, dist: float, e: CharacterBody3D) -> void:
    d.cd -= dt
    if d.cd > 0.0:
        return
    if d.burst > 0:
        d.burst -= 1
        d.cd = 0.5 if d.sn else 0.11
    else:
        d.burst = 0 if d.sn else 3
        d.cd = randf_range(2.2, 3.2) if d.sn else randf_range(0.8, 1.4)
    shot_pos = e.global_position
    shot_t = Time.get_ticks_msec() / 1000.0
    if randf() < clampf(0.5 - dist * 0.009, 0.1, 0.5):
        _hurt(26.0 if d.sn else 5.0)


func _ai(e: CharacterBody3D, dt: float) -> void:
    var d: Dictionary = e.get_meta("d")
    if d.dead:
        return
    d.t += dt
    var eye := e.global_position + Vector3(0, 1.5, 0)
    var pe := player.global_position + Vector3(0, 1.4, 0)
    var to_p := pe - eye
    var fwd := -e.global_transform.basis.z
    var sees := to_p.length() < 55.0 and fwd.dot(to_p.normalized()) > 0.2 and _clear(eye, pe, e)
    var now := Time.get_ticks_msec() / 1000.0
    if sees:
        d.st = 2
        d.last = player.global_position
        d.lost = 0.0
    elif d.st < 2 and now - shot_t < 1.2 and now - d.hear > 1.5 and e.global_position.distance_to(shot_pos) < 45.0:
        d.hear = now
        d.st = 1
        d.last = shot_pos
        d.rep = d.t + 20.0
        d.path = []
    var spd := 0.0
    var face := Vector3.ZERO
    if d.st == 0:
        if d.path.is_empty() or d.t > d.rep:
            d.rep = d.t + 14.0
            _path(e, d, astar.get_point_position(randi() % astar.get_point_count()))
        spd = 1.5
    elif d.st == 1:
        if d.path.is_empty():
            if e.global_position.distance_to(d.last) > 2.5 and d.t < d.rep:
                _path(e, d, d.last)
            else:
                d.st = 0
                d.rep = 0.0
        spd = 2.4
    else:
        face = to_p
        if d.exp < 0.0:
            d.exp += dt
            spd = 3.0
        elif sees:
            d.exp += dt
            if d.exp < 2.8:
                _shoot(d, dt, to_p.length(), e)
            else:
                d.exp = -3.0
                _path(e, d, _cover(e))
        else:
            d.lost += dt
            if d.path.is_empty() and d.lost > 1.2:
                _path(e, d, d.last)
            spd = 2.6
            if d.lost > 9.0:
                d.st = 0
                d.rep = 0.0
    var mv := Vector3.ZERO
    if spd > 0.0 and not d.path.is_empty():
        var df: Vector3 = d.path[0] - e.global_position
        df.y = 0.0
        if df.length() < 0.6:
            d.path.remove_at(0)
        else:
            mv = df.normalized()
    d.vel = d.vel.move_toward(mv * spd, 9.0 * dt)
    e.velocity.x = d.vel.x
    e.velocity.z = d.vel.z
    e.velocity.y = -2.0 if e.is_on_floor() else e.velocity.y - 20.0 * dt
    e.move_and_slide()
    var ty: Vector3 = face if face != Vector3.ZERO else d.vel
    if ty.length() > 0.2:
        e.rotation.y = lerp_angle(e.rotation.y, atan2(-ty.x, -ty.z), 7.0 * dt)
    var sp: float = d.vel.length()
    d.ph += sp * dt * 2.6
    var sw := sin(d.ph) * 0.7 * clampf(sp / 2.5, 0.0, 1.0)
    d.legs[0].rotation.x = sw
    d.legs[1].rotation.x = -sw


# ---------------------------------------------------------------- player update
func _move_player(dt: float) -> void:
    var full := move_v.length() > 0.92
    held = held + dt if full else 0.0
    var sprinting := full and held > 1.0 and stam > 0.0 and not crouch and ads < 0.2 and not scoped
    stam = clampf(stam + (-dt / 3.0 if sprinting else dt / 8.0), 0.0, 1.0)
    if stam <= 0.0:
        held = 0.0
    var spd := 1.6 if crouch else (5.2 if sprinting else (3.4 if full else 3.0))
    if wk == 1:
        spd *= 0.92
    spd *= 1.0 - 0.5 * ads
    if scoped:
        spd *= 0.3
    var dirv := Basis(Vector3.UP, yaw) * Vector3(move_v.x, 0.0, move_v.y)
    var tgt := dirv * spd
    vel_h = vel_h.move_toward(tgt, (14.0 if tgt.length() > 0.1 else 18.0) * dt)
    player.velocity.x = vel_h.x
    player.velocity.z = vel_h.z
    player.velocity.y = -2.0 if player.is_on_floor() else player.velocity.y - 20.0 * dt
    player.move_and_slide()
    player.rotation.y = yaw
    cam.rotation.x = pitch
    bob += vel_h.length() * dt * 2.4
    var hy := 1.05 if crouch else 1.62
    cam.position.y = lerpf(cam.position.y, hy + sin(bob) * 0.012 * minf(vel_h.length(), 4.0) * 0.4, minf(1.0, 8.0 * dt))
    cam.rotation.z = sin(t_rec * 1.7) * 0.003 + sin(bob * 0.5) * 0.004 * minf(vel_h.length(), 4.0) * 0.3


func _physics_process(dt: float) -> void:
    if not started or over:
        return
    _move_player(dt)
    for e in enemies:
        if is_instance_valid(e):
            _ai(e, dt)


func _process(dt: float) -> void:
    t_rec += dt
    adapt_t += dt
    ui["fps"].text = "%d FPS" % int(Engine.get_frames_per_second())
    if adapt_t > 2.0:
        adapt_t = 0.0
        var vp := get_viewport()
        var fr := Engine.get_frames_per_second()
        if fr < 52.0 and vp.scaling_3d_scale > 0.5:
            vp.scaling_3d_scale -= 0.05
        elif fr > 59.0 and vp.scaling_3d_scale < 0.85:
            vp.scaling_3d_scale += 0.03
    cd = maxf(0.0, cd - dt)
    var mx := 30 if wk == 0 else 5
    var a: Array = ammo[wk]
    if reload_t > 0.0:
        reload_t -= dt
        if reload_t <= 0.0:
            var take := mini(mx - a[0], a[1])
            a[0] += take
            a[1] -= take
    if fire_held and wk == 0 and started and not over:
        _fire()
    ads = move_toward(ads, 1.0 if (ads_on and wk == 0 and reload_t <= 0.0) else 0.0, dt * 6.0)
    var tf := 15.4 if scoped else lerpf(78.0, 62.0, ads)
    cam.fov = lerpf(cam.fov, tf, minf(1.0, 14.0 * dt))
    ui["scope"].visible = scoped
    vm.visible = not scoped
    ui["dot"].visible = not scoped
    var base := Vector3(0.17, -0.19, -0.42) if wk == 0 else Vector3(0.19, -0.21, -0.4)
    var tgt := base.lerp(Vector3(0.0, -0.115, -0.3), ads) if wk == 0 else base
    var rl := 0.0
    if reload_t > 0.0:
        rl = sin(clampf(1.0 - reload_t / (2.2 if wk == 0 else 3.4), 0.0, 1.0) * PI)
    var sp := minf(vel_h.length(), 4.0) * 0.25
    vm.position = tgt + Vector3(sin(bob * 0.5) * 0.004 * sp, absf(sin(bob)) * 0.006 * sp, 0.0) + Vector3(0, -rl * 0.12, rl * 0.08 + kick * 0.03)
    vm.rotation = Vector3(-kick * 0.05 - rl * 0.5, 0.0, rl * 0.3)
    kick = maxf(0.0, kick - dt * 8.0)
    var secs := int(t_rec)
    ui["tc"].text = "%02d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60]
    wlbl.text = "%02d:%02d" % [(secs / 60) % 60, secs % 60]
    ui["rec"].modulate.a = 1.0 if int(t_rec * 1.4) % 2 == 0 else 0.35
    ui["hp"].text = "HP %d" % int(maxf(hp, 0.0))
    ui["ammo"].text = "%s  %d / %d" % ["AK" if wk == 0 else "AWM", a[0], a[1]]
    ui["obj"].text = "HOSTILES  %d / %d" % [kills, total]
    if total > 0 and kills >= total and not over:
        over = true
        ui["msg"].text = "MISSION COMPLETE - TAP TO RESTART"
