extends RefCounted

# Sous-sol de l'île (v0.3.21 E5) : prospecter, ouvrir, extraire.
# Chaque île a ses richesses (data/iles.json) : fer, or, sel gemme, pierre.
# Un clan n'exploite que SON île. Une île sans fer devra en acheter ailleurs.
# Connaître son île ne veut pas dire connaître son sous-sol : la pierre se voit,
# mais le fer, l'or et le sel gemme se trouvent en PROSPECTANT (un adulte,
# 15 jours, et la prospection peut échouer).
# Pour extraire : gisement trouvé + route terminée jusqu'au site + ouverture
# (bois et pierres) + mineurs. Production = base × savoir et outil (pioche)
# × richesse de l'île × teneur.
# Pas d'épuisement brutal (règle du cahier des charges) : plus on extrait, plus
# la teneur baisse doucement ; on creuse plus profond, ça rend moins.

signal evenement(texte)

const TYPES := {
    "pierre": {"nom": "Carrière de pierre", "produit": "pierre", "base": 40.0, "echelle": 400000.0, "route": "carriere", "visible": true},
    "fer": {"nom": "Gisement de fer", "produit": "minerai_fer", "base": 8.0, "echelle": 150000.0, "route": "mine", "visible": false},
    "or": {"nom": "Or alluvionnaire", "produit": "or_alluvionnaire", "base": 0.004, "echelle": 60.0, "route": "eau", "visible": false},
    "sel": {"nom": "Sel gemme", "produit": "sel", "base": 5.0, "echelle": 80000.0, "route": "carriere", "visible": false},
}
const RICHESSE_MIN := 0.3        # en dessous, pas de gisement exploitable
const COUT_OUVERTURE := {"bois": 50.0, "pierre": 20.0}
const PROSPECTION_JOURS := 15

var ile := {}
var connus := {}                 # type -> {"ouvert": bool, "extrait": kg}
var prospection := {}            # {"membre": id, "fin": jour}

func installer(ile_dict: Dictionary) -> void:
    ile = ile_dict
    for t in TYPES:
        if TYPES[t]["visible"] and existe(t) and not connus.has(t):
            connus[t] = {"ouvert": false, "extrait": 0.0}

func existe(t: String) -> bool:
    return float(ile.get("richesse", {}).get(t, 0.0)) >= RICHESSE_MIN

func a_decouvrir() -> int:
    var n := 0
    for t in TYPES:
        if existe(t) and not connus.has(t):
            n += 1
    return n

# Teneur : 1 au début, baisse doucement avec ce qui a déjà été extrait.
func teneur(t: String) -> float:
    var e := float(connus.get(t, {}).get("extrait", 0.0))
    return 1.0 / (1.0 + e / float(TYPES[t]["echelle"]))

# ---------- Prospecter ----------

func prospecter(pop, jour: int) -> String:
    if not prospection.is_empty():
        return "Une prospection est déjà en cours."
    if a_decouvrir() == 0:
        return "Il ne reste rien à découvrir dans notre sous-sol."
    var choix := {}
    for h in pop.habitants:
        if pop.age(h, jour) >= pop.AGE_ADULTE and not h["metier"] in ["chef", "ancien"] and not h.has("experience") and not h.has("expedition"):
            if choix.is_empty() or pop.savoir(h, "extraction") > pop.savoir(choix, "extraction"):
                choix = h
    if choix.is_empty():
        return "Personne n'est disponible pour prospecter."
    choix["expedition"] = true
    prospection = {"membre": int(choix["id"]), "fin": jour + PROSPECTION_JOURS}
    evenement.emit("%s part prospecter le sous-sol (%d jours)." % [choix["prenom"], PROSPECTION_JOURS])
    return ""

func _fin_prospection(pop, h: Dictionary, rng: RandomNumberGenerator) -> void:
    h.erase("expedition")
    prospection = {}
    var restants: Array = []
    for t in TYPES:
        if existe(t) and not connus.has(t):
            restants.append(t)
    restants.sort_custom(func(a, b): return float(ile["richesse"][a]) > float(ile["richesse"][b]))
    if restants.is_empty():
        return
    var t: String = restants[0]
    var chance: float = 0.35 + 0.25 * float(ile["richesse"][t]) + pop.savoir(h, "extraction") / 200.0
    pop.donner_savoir(h, "extraction", minf(100.0, pop.savoir(h, "extraction") + 3.0))
    if rng.randf() < chance:
        connus[t] = {"ouvert": false, "extrait": 0.0}
        evenement.emit("Prospection réussie : %s trouvé sur notre île !" % TYPES[t]["nom"].to_lower())
    else:
        evenement.emit("La prospection n'a rien trouvé cette fois (%s a appris un peu)." % h["prenom"])

# ---------- Ouvrir un site ----------

func ouvrir(t: String, res, routes, pop) -> String:
    if not connus.has(t):
        return "Ce gisement n'est pas connu."
    if bool(connus[t]["ouvert"]):
        return "Ce site est déjà ouvert."
    var r: String = TYPES[t]["route"]
    if routes != null and not routes.relie(r):
        return "Il faut d'abord une route terminée jusqu'à %s." % routes.nom(r)
    for m in COUT_OUVERTURE:
        if res.quantite(m) < COUT_OUVERTURE[m]:
            return "Il faut 50 bois et 20 pierres pour ouvrir le site."
    for m in COUT_OUVERTURE:
        res.retirer(m, COUT_OUVERTURE[m], "construction")
    connus[t]["ouvert"] = true
    if not pop.postes.has("mineur"):
        pop.postes["mineur"] = 0
    evenement.emit("%s ouvert. Affectez des mineurs dans « Travail »." % TYPES[t]["nom"])
    return ""

func ouverts() -> Array:
    return connus.keys().filter(func(t): return bool(connus[t]["ouvert"]))

# ---------- Chaque jour ----------

func jour_passe(pop, res, routes, jour: int, rng: RandomNumberGenerator) -> void:
    if not prospection.is_empty():
        for h in pop.habitants:
            if int(h["id"]) == int(prospection["membre"]):
                h["occupe"] = true
                if jour >= int(prospection["fin"]):
                    _fin_prospection(pop, h, rng)
                break
        if not prospection.is_empty() and jour > int(prospection["fin"]):
            prospection = {}
    var sites := ouverts().filter(func(t): return routes == null or routes.relie(TYPES[t]["route"]))
    if sites.is_empty():
        return
    var i := 0
    for h in pop.habitants:
        if h["metier"] != "mineur" or h.get("occupe", false):
            continue
        var t: String = sites[i % sites.size()]
        i += 1
        var eff: float = (0.6 + float(h["competence"]) / 100.0 * 0.8) * float(h.get("bonus_outil", 1.0))
        var r: float = 0.5 + 0.5 * float(ile["richesse"].get(t, 1.0))
        var q: float = float(TYPES[t]["base"]) * eff * r * teneur(t)
        if routes != null:
            q *= routes.acces(TYPES[t]["route"])
        res.ajouter(TYPES[t]["produit"], q, "extraction")
        connus[t]["extrait"] = float(connus[t]["extrait"]) + q

func vers_dict() -> Dictionary:
    return {"connus": connus, "prospection": prospection}

func depuis_dict(d: Dictionary) -> void:
    connus = d.get("connus", {})
    prospection = d.get("prospection", {})
