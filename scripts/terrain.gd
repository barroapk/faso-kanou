extends MeshInstance3D

const TAILLE := 400.0
const RESOLUTION := 256
const HAUTEUR_MAX := 30.0
const HAUTEUR_VILLAGE := 2.0

var bruit := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var cote := FastNoiseLite.new()
var montagne := FastNoiseLite.new()
var climat := FastNoiseLite.new()

func _ready() -> void:
	bruit.seed = 7
	bruit.frequency = 0.008
	bruit.fractal_octaves = 5
	detail.seed = 19
	detail.frequency = 0.05
	cote.seed = 3
	cote.frequency = 0.004
	cote.fractal_octaves = 3
	montagne.seed = 11
	montagne.frequency = 0.005
	climat.seed = 23
	climat.frequency = 0.006
	mesh = _generer()
	material_override = _materiau_sol()

func _masque(x: float, z: float) -> float:
	var r := Vector2(x, z).length() / (TAILLE * 0.45)
	return 1.0 - smoothstep(0.7, 1.0, r + cote.get_noise_2d(x, z) * 0.35)

func _humidite(x: float, z: float) -> float:
	return clampf(0.5 + z / TAILLE * 1.6 + climat.get_noise_2d(x, z) * 0.35, 0.0, 1.0)

func desert(x: float, z: float) -> float:
	return 1.0 - smoothstep(0.15, 0.32, _humidite(x, z))

func foret(x: float, z: float) -> float:
	return smoothstep(0.68, 0.85, _humidite(x, z))

func hauteur(x: float, z: float) -> float:
	var m := _masque(x, z)
	var plaine := 1.2 + detail.get_noise_2d(x, z) * 0.6
	var collines := (bruit.get_noise_2d(x, z) + 1.0) * 2.0
	var zone := smoothstep(0.1, 0.45, montagne.get_noise_2d(x, z))
	var crete := 1.0 - absf(bruit.get_noise_2d(x * 0.8, z * 0.8))
	var montagnes := zone * pow(crete, 2.0) * HAUTEUR_MAX
	var vague := sin(x * 0.12 + detail.get_noise_2d(x, z) * 4.0) * 0.5 + 0.5
	var dunes := desert(x, z) * vague * 2.0
	var h := (plaine + collines + montagnes + dunes) * m - 2.5 * (1.0 - m)
	var plat := 1.0 - smoothstep(14.0, 24.0, Vector2(x, z).length())
	return lerpf(h, HAUTEUR_VILLAGE, plat)

func _generer() -> ArrayMesh:
	var n := RESOLUTION + 1
	var pas := TAILLE / float(RESOLUTION)
	var debut := -TAILLE / 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for j in n:
			var x := debut + i * pas
			var z := debut + j * pas
			st.set_color(Color(desert(x, z), foret(x, z), 0.0))
			st.set_uv(Vector2(x, z) * 0.12)
			st.add_vertex(Vector3(x, hauteur(x, z), z))
	for i in RESOLUTION:
		for j in RESOLUTION:
			var a := i * n + j
			var b := (i + 1) * n + j
			var c := a + 1
			var d := b + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

func _materiau_sol() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("herbe_couleur", load("res://assets/sol/herbe_couleur.jpg"))
	mat.set_shader_parameter("herbe_relief", load("res://assets/sol/herbe_relief.jpg"))
	mat.set_shader_parameter("roche_couleur", load("res://assets/sol/roche_couleur.jpg"))
	mat.set_shader_parameter("roche_relief", load("res://assets/sol/roche_relief.jpg"))
	return mat
