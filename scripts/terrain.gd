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
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.vertex_color_is_srgb = true
    mat.roughness = 1.0
    material_override = mat

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

func _couleur(h: float, x: float, z: float) -> Color:
    var sable := Color(0.78, 0.66, 0.43)
    var herbe := Color(0.43, 0.49, 0.24)
    var savane := Color(0.34, 0.42, 0.19)
    var laterite := Color(0.60, 0.31, 0.18)
    var roche := Color(0.43, 0.40, 0.35)
    var pierre := Color(0.58, 0.54, 0.48)
    var v := detail.get_noise_2d(x * 3.0, z * 3.0) * 0.05
    var c: Color
    if h < 0.4:
        c = sable
    elif h < 1.2:
        c = sable.lerp(herbe, (h - 0.4) / 0.8)
    elif h < 3.0:
        c = herbe.lerp(savane, (h - 1.2) / 1.8)
    elif h < 6.0:
        c = savane.lerp(laterite, (h - 3.0) / 3.0)
    elif h < 10.0:
        c = laterite.lerp(roche, (h - 6.0) / 4.0)
    else:
        c = roche.lerp(pierre, clampf((h - 10.0) / 8.0, 0.0, 1.0))
    return c.lightened(v) if v > 0.0 else c.darkened(-v)

func _point(x: float, z: float) -> Vector3:
    return Vector3(x, hauteur(x, z), z)

func _ajouter(st: SurfaceTool, p: Vector3) -> void:
    st.set_color(_couleur(p.y, p.x, p.z))
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
    return st.commit()
