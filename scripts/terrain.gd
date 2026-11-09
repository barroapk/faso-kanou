extends MeshInstance3D

const TAILLE := 120.0
const RESOLUTION := 160
const HAUTEUR_MAX := 8.0

var bruit := FastNoiseLite.new()

func _ready() -> void:
	bruit.seed = 7
	bruit.frequency = 0.02
	bruit.fractal_octaves = 4
	mesh = _generer()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	material_override = mat

func hauteur(x: float, z: float) -> float:
	var dist := Vector2(x, z).length() / (TAILLE * 0.45)
	var forme := 1.0 - clampf(dist, 0.0, 1.0)
	forme = forme * forme * (3.0 - 2.0 * forme)
	var collines := (bruit.get_noise_2d(x, z) + 1.0) * 0.5
	return forme * (1.0 + collines * HAUTEUR_MAX) - 1.0

func _couleur(h: float) -> Color:
	var sable := Color(0.82, 0.72, 0.50)
	var savane := Color(0.38, 0.48, 0.20)
	var laterite := Color(0.66, 0.36, 0.20)
	var roche := Color(0.50, 0.44, 0.38)
	if h < 0.3:
		return sable
	elif h < 1.0:
		return sable.lerp(savane, (h - 0.3) / 0.7)
	elif h < 2.5:
		return savane
	elif h < 3.5:
		return savane.lerp(laterite, h - 2.5)
	elif h < 5.5:
		return laterite
	elif h < 6.5:
		return laterite.lerp(roche, h - 5.5)
	return roche

func _point(x: float, z: float) -> Vector3:
	return Vector3(x, hauteur(x, z), z)

func _ajouter(st: SurfaceTool, p: Vector3) -> void:
	st.set_color(_couleur(p.y))
	st.add_vertex(p)

func _generer() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pas := TAILLE / RESOLUTION
	var debut := -TAILLE / 2.0
	for i in RESOLUTION:
		for j in RESOLUTION:
			var x0 := debut + i * pas
			var z0 := debut + j * pas
			var a := _point(x0, z0)
			var b := _point(x0 + pas, z0)
			var c := _point(x0, z0 + pas)
			var d := _point(x0 + pas, z0 + pas)
			_ajouter(st, a)
			_ajouter(st, b)
			_ajouter(st, c)
			_ajouter(st, b)
			_ajouter(st, d)
			_ajouter(st, c)
	st.index()
	st.generate_normals()
	return st.commit()
