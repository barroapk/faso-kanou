extends Node3D

const TAILLE := 2000.0
const MORCEAUX := 8
const RES := 48
const NIVEAUX := [[1, 0.0, 450.0], [2, 450.0, 1100.0], [4, 1100.0, 0.0]]
const JUPE := 6.0
const HAUTEUR_VILLAGE := 8.0
const MARE := Vector2(-160.0, 90.0)

var bruit := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var cote := FastNoiseLite.new()
var collines := FastNoiseLite.new()
var zone := FastNoiseLite.new()
var climat := FastNoiseLite.new()
var materiau: ShaderMaterial
var morceaux: Array = []
var mare: MeshInstance3D

var _g: PackedFloat32Array
var _c: PackedColorArray
var _n := 0
var _w := 0
var _pas := 0.0
var _x0 := 0.0
var _z0 := 0.0
var _cx := 0.0
var _cz := 0.0

func _ready() -> void:
	bruit.seed = 7
	bruit.frequency = 0.004
	bruit.fractal_octaves = 4
	detail.seed = 19
	detail.frequency = 0.03
	cote.seed = 3
	cote.frequency = 0.0015
	cote.fractal_octaves = 3
	collines.seed = 11
	collines.frequency = 0.006
	collines.fractal_octaves = 4
	zone.seed = 29
	zone.frequency = 0.002
	climat.seed = 23
	climat.frequency = 0.002
	materiau = _materiau_sol()
	var cote_m := TAILLE / MORCEAUX
	for i in MORCEAUX:
		for j in MORCEAUX:
			_creer_morceau(-TAILLE / 2.0 + i * cote_m, -TAILLE / 2.0 + j * cote_m, cote_m)
	_creer_riviere()
	_creer_mare()

# ---------- RELIEF ET EAU ----------

func riviere_x(z: float) -> float:
	return -350.0 + 90.0 * sin(z * 0.004) + 35.0 * sin(z * 0.011 + 1.3)

func niveau_vallee(z: float) -> float:
	return lerpf(9.0, 0.3, clampf((z + 550.0) / 1450.0, 0.0, 1.0))

func distance_riviere(x: float, z: float) -> float:
	if z < -560.0:
		return 9999.0
	return absf(x - riviere_x(z))

func dans_eau(x: float, z: float) -> bool:
	return distance_riviere(x, z) < 16.0 or Vector2(x - MARE.x, z - MARE.y).length() < 55.0

func _masque(x: float, z: float) -> float:
	var r := Vector2(x, z).length() / 900.0
	return 1.0 - smoothstep(0.8, 1.05, r + cote.get_noise_2d(x, z) * 0.18)

func hauteur(x: float, z: float) -> float:
	var m := _masque(x, z)
	var h := 7.0 + bruit.get_noise_2d(x, z) * 2.0 + detail.get_noise_2d(x, z) * 0.5
	var zc := smoothstep(0.05, 0.4, zone.get_noise_2d(x, z))
	var c := (collines.get_noise_2d(x, z) + 1.0) * 0.5
	h += zc * c * c * 45.0
	var dm := Vector2(x * 0.8, z + 560.0).length()
	h += (1.0 - smoothstep(60.0, 320.0, dm)) * (110.0 + detail.get_noise_2d(x * 0.5, z * 0.5) * 35.0)

	var d := distance_riviere(x, z)
	if d < 120.0:
		var fond := niveau_vallee(z)
		h = lerpf(h, fond + 1.5, 1.0 - smoothstep(20.0, 120.0, d))
		h -= (1.0 - smoothstep(8.0, 15.0, d)) * 3.0

	var dmare := Vector2(x - MARE.x, z - MARE.y).length()
	if dmare < 110.0:
		h = maxf(h, lerpf(6.0, h, smoothstep(70.0, 110.0, dmare)))
		h = lerpf(h, 3.5, 1.0 - smoothstep(25.0, 65.0, dmare))
	var rx := riviere_x(MARE.y)
	if absf(z - MARE.y) < 6.0 and x > rx and x < MARE.x:
		h = minf(h, 5.0 + absf(z - MARE.y) * 0.4)

	h = lerpf(h, HAUTEUR_VILLAGE, 1.0 - smoothstep(45.0, 90.0, Vector2(x, z).length()))
	return h * m - 8.0 * (1.0 - m)

func humide(x: float, z: float) -> float:
	var dm := Vector2(x - MARE.x, z - MARE.y).length()
	return maxf(1.0 - smoothstep(10.0, 90.0, distance_riviere(x, z)), 1.0 - smoothstep(40.0, 100.0, dm))

func desert(x: float, z: float) -> float:
	var nord := clampf((-z - 620.0 + climat.get_noise_2d(x, z) * 120.0) / 200.0, 0.0, 1.0)
	return nord * (1.0 - humide(x, z))

func foret(x: float, z: float) -> float:
	var sud := smoothstep(250.0, 650.0, z + climat.get_noise_2d(x, z) * 150.0)
	return maxf(sud, humide(x, z) * 0.9)

# ---------- MORCEAUX DE TERRAIN ----------

func _creer_morceau(x0: float, z0: float, cote_m: float) -> void:
	_n = RES
	_w = RES + 3
	_pas = cote_m / RES
	_x0 = x0
	_z0 = z0
	_cx = x0 + cote_m / 2.0
	_cz = z0 + cote_m / 2.0
	_g = PackedFloat32Array()
	_g.resize(_w * _w)
	var plus_haut := -100.0
	for i in _w:
		for j in _w:
			var h := hauteur(x0 + (i - 1) * _pas, z0 + (j - 1) * _pas)
			_g[i * _w + j] = h
			plus_haut = maxf(plus_haut, h)
	if plus_haut < -1.0:
		return
	_c = PackedColorArray()
	_c.resize((_n + 1) * (_n + 1))
	for i in _n + 1:
		for j in _n + 1:
			var x := x0 + i * _pas
			var z := z0 + j * _pas
			_c[i * (_n + 1) + j] = Color(desert(x, z), foret(x, z), humide(x, z), climat.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5)
	for niveau in NIVEAUX:
		var mi := MeshInstance3D.new()
		mi.mesh = _maillage(niveau[0])
		mi.material_override = materiau
		mi.position = Vector3(_cx, 0.0, _cz)
		mi.visibility_range_begin = niveau[1]
		mi.visibility_range_end = niveau[2]
		mi.visibility_range_begin_margin = 25.0
		mi.visibility_range_end_margin = 25.0
		add_child(mi)
		morceaux.append(mi)

func _sommet(st: SurfaceTool, i: int, j: int, decalage: float) -> void:
	var h := _g[(i + 1) * _w + (j + 1)]
	var nx := _g[i * _w + (j + 1)] - _g[(i + 2) * _w + (j + 1)]
	var nz := _g[(i + 1) * _w + j] - _g[(i + 1) * _w + (j + 2)]
	st.set_normal(Vector3(nx, 2.0 * _pas, nz).normalized())
	st.set_color(_c[i * (_n + 1) + j])
	var wx := _x0 + i * _pas
	var wz := _z0 + j * _pas
	st.set_uv(Vector2(wx, wz) * 0.12)
	st.add_vertex(Vector3(wx - _cx, h + decalage, wz - _cz))

func _maillage(s: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m := _n / s + 1
	for a in m:
		for b in m:
			_sommet(st, a * s, b * s, 0.0)
	for a in m - 1:
		for b in m - 1:
			var p := a * m + b
			var q := p + m
			for v in [p, q, p + 1, q, q + 1, p + 1]:
				st.add_index(v)
	var prochain := m * m
	var bas := {}
	for e in 4:
		var liste: Array[int] = []
		for k in m:
			var a := k
			var b := k
			if e == 0:
				a = 0
			elif e == 1:
				a = m - 1
			elif e == 2:
				b = 0
			else:
				b = m - 1
			var idx := a * m + b
			if not bas.has(idx):
				_sommet(st, a * s, b * s, -JUPE)
				bas[idx] = prochain
				prochain += 1
			liste.append(idx)
		for k in m - 1:
			var e1 := liste[k]
			var e2 := liste[k + 1]
			var l1: int = bas[e1]
			var l2: int = bas[e2]
			for v in [e1, l1, e2, e2, l1, l2, e1, e2, l1, e2, l2, l1]:
				st.add_index(v)
	st.generate_tangents()
	return st.commit()

func utiliser_materiau(mat: Material) -> void:
	for mi in morceaux:
		mi.material_override = mat

# ---------- EAU VISIBLE ----------

func _materiau_eau() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.28, 0.30, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _creer_riviere() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := -560.0
	var lignes := 0
	while z <= 960.0 and _masque(riviere_x(z), z) > 0.3:
		var x := riviere_x(z)
		var y := niveau_vallee(z) + 0.3
		st.add_vertex(Vector3(x - 14.0, y, z))
		st.add_vertex(Vector3(x + 14.0, y, z))
		z += 8.0
		lignes += 1
	for k in lignes - 1:
		var a := k * 2
		for v in [a, a + 1, a + 2, a + 1, a + 3, a + 2]:
			st.add_index(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _materiau_eau()
	add_child(mi)

func niveau_mare() -> float:
	return 5.5 if Civilisation.temps.saison_des_pluies() else 3.8

func _creer_mare() -> void:
	mare = MeshInstance3D.new()
	var disque := CylinderMesh.new()
	disque.top_radius = 60.0
	disque.bottom_radius = 60.0
	disque.height = 0.05
	disque.radial_segments = 48
	mare.mesh = disque
	mare.material_override = _materiau_eau()
	mare.position = Vector3(MARE.x, niveau_mare(), MARE.y)
	add_child(mare)

func _process(delta: float) -> void:
	if mare:
		mare.position.y = move_toward(mare.position.y, niveau_mare(), delta * 0.05)

func _materiau_sol() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("herbe_couleur", load("res://assets/sol/herbe_couleur.jpg"))
	mat.set_shader_parameter("herbe_relief", load("res://assets/sol/herbe_relief.jpg"))
	mat.set_shader_parameter("roche_couleur", load("res://assets/sol/roche_couleur.jpg"))
	mat.set_shader_parameter("roche_relief", load("res://assets/sol/roche_relief.jpg"))
	return mat
