extends RefCounted

# Force militaire et mobilisation (v0.3.41, savoir combat v0.3.42) : même moteur pour le joueur et les clans.
# Pas de raid dans cette étape : on sait seulement MOBILISER des combattants
# (temporairement, sans nouveau métier) et CALCULER la force d'attaque et la défense.
#  - combattant : adulte de 16 à 49 ans, en santé (50 ou plus), pas déjà occupé ;
#  - vigueur = santé x (0,6 si le clan a faim) x expérience du savoir « combat » (0,85 à 1,15) ;
#  - protecteurs : rôle secondaire (jusqu'à un tiers des adultes aptes) ; il prend 25 % du temps du métier
#    principal et fait progresser le combat ; on ne produit pas et ne défend pas en même temps ;
#  - armes réellement possédées : lance 1,0 ; arc 0,8 ; sans arme 0,4 ;
#  - défense = force de tous les combattants présents x (1 + protection de la clôture du village) ;
#  - on ne mobilise jamais plus de la moitié des combattants, et il en reste 2 au moins.

signal evenement(texte)

const AGE_MIN := 16
const AGE_MAX := 49
const SANTE_MIN := 50
const ARMES := {"lance": 1.0, "arc": 0.8}
const SANS_ARME := 0.4
const PART_MAX := 0.5
const RESTE_MIN := 2
const PART_PROTECTEURS := 0.34

var mobilises := {}      # id habitant -> jour de retour

func _vigueur(h: Dictionary, res) -> float:
    var v: float = float(h["sante"]) / 100.0 * (0.85 + 0.3 * float(h.get("savoirs", {}).get("combat", 0.0)) / 100.0)
    return v * (0.6 if res.faim else 1.0)

# Combattants disponibles (ni mobilisés, ni occupés), les plus vigoureux d'abord.
func combattants(pop, res, jour: int) -> Array:
    var l: Array = []
    for h in pop.habitants:
        var a: int = pop.age(h, jour)
        if a < AGE_MIN or a > AGE_MAX or int(h["sante"]) < SANTE_MIN:
            continue
        if h.get("occupe", false) or mobilises.has(int(h["id"])):
            continue
        l.append(h)
    l.sort_custom(func(x, y): return _vigueur(x, res) > _vigueur(y, res))
    return l

# Force d'un groupe (déjà trié) : les armes vont aux plus vigoureux.
# deja = armes déjà emportées par les mobilisés (lances d'abord, puis arcs) : elles ne comptent qu'une fois.
func force_groupe(groupe: Array, equip, res, deja := 0) -> float:
    var lances: int = equip.nombre("lance") if equip != null else 0
    var arcs: int = equip.nombre("arc") if equip != null else 0
    var pris_l: int = mini(deja, lances)
    lances -= pris_l
    arcs = maxi(0, arcs - (deja - pris_l))
    var t := 0.0
    for h in groupe:
        var arme: float = SANS_ARME
        if lances > 0:
            lances -= 1
            arme = float(ARMES["lance"])
        elif arcs > 0:
            arcs -= 1
            arme = float(ARMES["arc"])
        t += _vigueur(h, res) * arme
    return t

func defense(pop, equip, clotures, res, jour: int) -> float:
    var presents: Array = combattants(pop, res, jour)
    var p: float = clotures.protection("village") if clotures != null else 0.0
    return force_groupe(presents, equip, res, mobilises.size()) * (1.0 + p)

# Combien on peut mobiliser sans mettre le clan en danger.
func plafond(pop, res, jour: int) -> int:
    var n: int = combattants(pop, res, jour).size()
    return maxi(0, mini(int(floor(n * PART_MAX)), n - RESTE_MIN))

# Mobilise n combattants pour `duree` jours ; renvoie leurs identifiants (vide si impossible).
func mobiliser(pop, res, jour: int, n: int, duree: int) -> Array:
    n = mini(n, plafond(pop, res, jour))
    var ids: Array = []
    if n <= 0:
        return ids
    var l: Array = combattants(pop, res, jour)
    for i in range(n):
        var h: Dictionary = l[i]
        mobilises[int(h["id"])] = jour + duree
        h["occupe"] = true
        ids.append(int(h["id"]))
    return ids

# Adultes aptes à devenir protecteurs (hors chef, enfants et anciens).
func _aptes(pop, jour: int) -> Array:
    var l: Array = []
    for h in pop.habitants:
        var a: int = pop.age(h, jour)
        if a < AGE_MIN or a > AGE_MAX or int(h["sante"]) < SANTE_MIN:
            continue
        if ["chef", "enfant", "ancien"].has(h["metier"]):
            continue
        l.append(h)
    return l

func nb_protecteurs(pop) -> int:
    return pop.habitants.filter(func(h): return h.get("role", "") == "protecteur").size()

func max_protecteurs(pop, jour: int) -> int:
    return int(floor(_aptes(pop, jour).size() * PART_PROTECTEURS))

# Désigne n protecteurs : les plus expérimentés au combat d'abord. Renvoie le nombre réel.
func fixer_protecteurs(pop, jour: int, n: int) -> int:
    var l: Array = _aptes(pop, jour)
    # Plus de combat d'abord ; à égalité, ceux qui sont déjà protecteurs gardent leur place.
    l.sort_custom(func(x, y):
        var cx: float = float(x.get("savoirs", {}).get("combat", 0.0))
        var cy: float = float(y.get("savoirs", {}).get("combat", 0.0))
        if cx != cy:
            return cx > cy
        var rx: bool = x.get("role", "") == "protecteur"
        var ry: bool = y.get("role", "") == "protecteur"
        if rx != ry:
            return rx
        return int(x["id"]) < int(y["id"]))
    for h in pop.habitants:
        h.erase("role")
    n = clampi(n, 0, max_protecteurs(pop, jour))
    for i in range(n):
        l[i]["role"] = "protecteur"
    return n

func groupe_mobilise(pop) -> Array:
    return pop.habitants.filter(func(h): return mobilises.has(int(h["id"])))

# Chaque jour, AVANT la production : les mobilisés ne travaillent pas, puis rentrent.
func jour_passe(pop, jour: int) -> void:
    if mobilises.is_empty():
        return
    var presents := {}
    for h in pop.habitants:
        presents[int(h["id"])] = h
    for id in mobilises.keys():
        if not presents.has(id) or jour >= int(mobilises[id]):
            mobilises.erase(id)
        else:
            presents[id]["occupe"] = true

func texte(pop, equip, clotures, res, jour: int) -> String:
    var l: Array = combattants(pop, res, jour)
    var s := "Combattants : %d disponibles (%d mobilisés), force %.1f, défense %.1f, mobilisation possible : %d." % [l.size(), mobilises.size(), force_groupe(l, equip, res, mobilises.size()), defense(pop, equip, clotures, res, jour), plafond(pop, res, jour)]
    return s

func vers_dict() -> Dictionary:
    return {"mobilises": mobilises}

func depuis_dict(d: Dictionary) -> void:
    mobilises = {}
    for id in d.get("mobilises", {}):
        mobilises[int(id)] = int(d["mobilises"][id])
