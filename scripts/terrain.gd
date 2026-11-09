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
    mat.roughness = 1.0
    material_override = mat

func hauteur(x: float, z: float) -> float:
    var dist := Vector2(x, z).length() / (TAILLE * 0.45)
    var forme := 1.0 - clamp(dist, 0.0, 1.0)
    forme = forme * forme * (3.0 - 2.0 * forme)
    var collines := (bruit.get_noise_2d(x, z) + 1.0) * 0.5
    return forme * (1.0 + collines * HAUTEUR_MAX) - 1.0

func _couleur(h: float) -> Color:
    if h < 0.4:
        return Color(0.86, 0.76, 0.52)
    elif h < 2.5:
        return Color(0.45, 0.55, 0.24)
    elif h < 5.0:
        return Color(0.70, 0.42, 0.24)
    return Color(0.55, 0.47, 0.40)

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
