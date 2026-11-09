extends MeshInstance3D

const TAILLE := 120.0
const RESOLUTION := 220
const HAUTEUR_MAX := 18.0
const HAUTEUR_VILLAGE := 1.5

var bruit := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var erosion := FastNoiseLite.new()

func _ready() -> void:
    _configurer_bruits()
    mesh = _generer()
    material_override = _materiau_sol()

func _configurer_bruits() -> void:
    bruit.seed = 7
    bruit.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    bruit.frequency = 0.018
    bruit.fractal_octaves = 5
    bruit.fractal_gain = 0.48
    detail.seed = 19
    detail.frequency = 0.075
    detail.fractal_octaves = 3
    erosion.seed = 31
    erosion.noise_type = FastNoiseLite.TYPE_PERLIN
    erosion.frequency = 0.035
    erosion.fractal_octaves = 3

func hauteur(x: float, z: float) -> float:
    var n1 := bruit.get_noise_2d(x, z)
    var montagnes := pow(maxf(0.0, n1), 1.7) * HAUTEUR_MAX
    var collines := n1 * 2.0
    var micro := detail.get_noise_2d(x, z) * 1.3
    var variation := erosion.get_noise_2d(x, z) * 2.0
    var vallee := absf(bruit.get_noise_2d(x * 0.45 + 400.0, z * 0.45))
    var h := montagnes + collines + micro + variation - pow(vallee, 2.0) * 4.0
    var r := Vector2(x, z).length()
    var bord := 1.0 - smoothstep(0.72, 1.0, r / (TAILLE * 0.5))
    h = h * bord - 0.8
    var plat := 1.0 - smoothstep(12.0, 20.0, r)
    return lerpf(h, HAUTEUR_VILLAGE, plat)

func _point(x: float, z: float) -> Vector3:
    return Vector3(x, hauteur(x, z), z)

func _ajouter(st: SurfaceTool, p: Vector3) -> void:
    st.set_uv(Vector2(p.x, p.z) * 0.12)
    st.add_vertex(p)

func _generer() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var pas := TAILLE / float(RESOLUTION)
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
