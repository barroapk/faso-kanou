extends RefCounted

# Territoire du clan (v0.3.19 T1).
# L'île est découpée en parcelles carrées de 1 km² (100 ha). Le clan possède
# seulement les parcelles qu'il a acquises ; le reste est la nature libre de son
# île (visible, mais marquée comme non acquise).
# On ne stocke que les parcelles possédées : une île de 12 000 parcelles ne
# coûte rien en mémoire. La part cultivable d'une parcelle est tirée de sa
# position (même résultat à chaque partie pour une même île).
# Acquérir une parcelle = la borner (bois et pierres) et la faire reconnaître
# par le chef de terre (offrande de grain). Elle doit toucher le territoire
# déjà possédé : le territoire grandit de proche en proche jusqu'à toute l'île.
# Posséder une parcelle ne la rend pas productive : il faut ensuite défricher
# et cultiver (agriculture.gd). Le contrôle des accès viendra plus tard (T5).

signal evenement(texte)

const HA_PARCELLE := 100.0
const COUT_BASE := {"bois": 10.0, "pierre": 5.0, "nourriture": 20.0}
const HAUSSE_PAR_PARCELLE := 0.05    # chaque parcelle de plus coûte 5 % de plus
const HAUSSE_PAR_KM := 0.10          # et 10 % de plus par km loin du village

var ile_id := ""
var ile := {}
var cote := 1                        # nombre de parcelles par côté
var centre := Vector2i.ZERO          # parcelle du village
var possedees := {}                  # "x,z" -> {"jour": j, "cloture": 0}

func installer(id: String, ile_dict: Dictionary, nb: int, jour: int) -> void:
    ile_id = id
    ile = ile_dict
    cote = maxi(1, int(ceil(sqrt(float(ile.get("surface_ha", 100.0)) / HA_PARCELLE))))
    centre = Vector2i(int(cote / 2.0), int(cote / 2.0))
    if possedees.is_empty():
        possedees[_cle(centre)] = {"jour": jour, "cloture": 0}
        while possedees.size() < nb:
            var v := voisines_libres()
            if v.is_empty():
                break
            v.sort_custom(func(a, b): return _distance(a) < _distance(b))
            possedees[_cle(v[0])] = {"jour": jour, "cloture": 0}

func _cle(p: Vector2i) -> String:
    return "%d,%d" % [p.x, p.y]

func _pos(cle: String) -> Vector2i:
    var t := cle.split(",")
    return Vector2i(int(t[0]), int(t[1]))

func _distance(p: Vector2i) -> float:
    return Vector2(p - centre).length()

# Part cultivable d'une parcelle : autour de la moyenne de l'île, variable selon
# l'endroit (rochers, marais, bonnes terres).
func cultivable(p: Vector2i) -> float:
    var moyenne := float(ile.get("cultivable_ha", 0.0)) / maxf(1.0, float(ile.get("surface_ha", 1.0)))
    var h: int = hash("%s:%d:%d" % [ile_id, p.x, p.y])
    var bruit := float(absi(h) % 1000) / 1000.0            # 0 à 1
    return HA_PARCELLE * clampf(moyenne * (0.4 + 1.2 * bruit), 0.0, 0.95)

func surface_possedee() -> float:
    return possedees.size() * HA_PARCELLE

func cultivable_possede() -> float:
    var s := 0.0
    for k in possedees:
        s += cultivable(_pos(k))
    return s

func voisines_libres() -> Array:
    var l: Array = []
    var vu := {}
    for k in possedees:
        var p := _pos(k)
        for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
            var q: Vector2i = p + d
            if q.x < 0 or q.y < 0 or q.x >= cote or q.y >= cote:
                continue
            var c := _cle(q)
            if possedees.has(c) or vu.has(c):
                continue
            vu[c] = true
            l.append(q)
    return l

func cout(p: Vector2i) -> Dictionary:
    var f := 1.0 + HAUSSE_PAR_PARCELLE * possedees.size() + HAUSSE_PAR_KM * _distance(p)
    var c := {}
    for r in COUT_BASE:
        c[r] = COUT_BASE[r] * f
    return c

func texte_cout(c: Dictionary) -> String:
    return "%d bois, %d pierres, %d kg de grain" % [int(c["bois"]), int(c["pierre"]), int(c["nourriture"])]

# Retire la nourriture en prenant dans chaque aliment selon sa part (kg équivalent mil).
func _payer_nourriture(res, kgem: float) -> void:
    var total: float = res.total_aliments()
    if total <= 0.0:
        return
    for a in res.aliments.keys():
        var part: float = float(res.aliments[a]) * res.facteur(a) / total
        res.retirer(a, kgem * part / res.facteur(a), "foncier")

func acheter(p: Vector2i, res, jour: int) -> String:
    if possedees.has(_cle(p)):
        return "Cette parcelle est déjà à nous."
    if not voisines_libres().has(p):
        return "La parcelle doit toucher notre territoire."
    var c := cout(p)
    if res.quantite("bois") < c["bois"] or res.quantite("pierre") < c["pierre"] or res.total_aliments() < c["nourriture"]:
        return "Il faut %s." % texte_cout(c)
    res.retirer("bois", c["bois"], "foncier")
    res.retirer("pierre", c["pierre"], "foncier")
    _payer_nourriture(res, c["nourriture"])
    possedees[_cle(p)] = {"jour": jour, "cloture": 0}
    evenement.emit("Nouvelle parcelle acquise (%d ha, dont %d cultivables). Territoire : %d ha." % [int(HA_PARCELLE), int(cultivable(p)), int(surface_possedee())])
    return ""

# Les meilleures parcelles à acquérir : les plus cultivables, puis les moins chères.
func meilleures(n: int) -> Array:
    var v := voisines_libres()
    v.sort_custom(func(a, b): return cultivable(a) / cout(a)["nourriture"] > cultivable(b) / cout(b)["nourriture"])
    return v.slice(0, n)

# Ordinateur (et joueur en mode automatique) : acquiert une parcelle quand la
# terre cultivable libre ne suffit plus.
func gerer_auto(agriculture, res, jour: int, besoin_ha: float) -> void:
    if agriculture.terre_libre() >= besoin_ha:
        return
    var m := meilleures(1)
    if not m.is_empty():
        acheter(m[0], res, jour)

func vers_dict() -> Dictionary:
    return {"ile": ile_id, "possedees": possedees}

func depuis_dict(d: Dictionary) -> void:
    possedees = {}
    for k in d.get("possedees", {}):
        possedees[str(k)] = d["possedees"][k]
