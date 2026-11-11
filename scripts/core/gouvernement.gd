extends RefCounted

# Socle du gouvernement (v0.3.52), commun au joueur et aux clans de l'ordinateur.
#  - Un SECTEUR (santé, défense, finances, plus tard justice, éducation...) n'est pas un ministère :
#    il apparaît d'abord comme tableau de bord des systèmes qui existent déjà.
#  - Le socle ne connaît aucun secteur en particulier : data/secteurs.json les décrit, et un
#    « adaptateur » (ci-dessous) lit les vraies données. Ajouter un secteur = une ligne de données
#    + un adaptateur, sans toucher au reste.
#  - Aucune efficacité inventée : tant que les nominations et les budgets sectoriels n'existent pas,
#    on affiche seulement les données réelles. Aucun bonus sur la production, la santé ou la défense.
#  - Pas de double comptabilité : tout est lu dans population, ressources, guerre, budget...
#  - Chaque secteur garde déjà sa place pour plus tard : ministère constitué ou non, responsables
#    (identifiants d'habitants) et part de budget, sauvegardés mais pas encore utilisés.

signal evenement(texte)

const FICHIER := "res://data/secteurs.json"
static var _cat: Dictionary = {}

var secteurs := {}     # id -> {"ministere": bool, "responsables": [ids], "budget_part": float}

static func _charger() -> void:
    if not _cat.is_empty():
        return
    var d = JSON.parse_string(FileAccess.get_file_as_string(FICHIER))
    if typeof(d) == TYPE_DICTIONARY:
        _cat = d

func _init() -> void:
    _charger()
    for id in actifs():
        secteurs[id] = _vide()

static func _vide() -> Dictionary:
    return {"ministere": false, "responsables": [], "budget_part": 0.0}

static func maturites() -> Array:
    _charger()
    return _cat.get("maturites", [])

# Secteurs qui ont une source de données réelle.
static func actifs() -> Array:
    _charger()
    var l: Array = []
    for id in _cat.get("secteurs", {}):
        if str(_cat["secteurs"][id].get("source", "")) != "":
            l.append(id)
    return l

static func prevus() -> Array:
    _charger()
    var l: Array = []
    for id in _cat.get("secteurs", {}):
        if str(_cat["secteurs"][id].get("source", "")) == "":
            l.append(str(_cat["secteurs"][id]["nom"]))
    return l

# Niveau de maturité : tant qu'aucun ministère n'est constitué, la gouvernance reste coutumière.
func maturite() -> Dictionary:
    for id in secteurs:
        if bool(secteurs[id]["ministere"]):
            return maturites()[2]
    return maturites()[0]

# Tableau de bord de tous les secteurs actifs d'un clan (joueur ou ordinateur).
func tableau(c, jour: int) -> Array:
    var l: Array = []
    for id in actifs():
        var def: Dictionary = _cat["secteurs"][id]
        var s: Dictionary = secteurs.get(id, _vide())
        var d: Dictionary = _lire(str(def["source"]), c, jour)
        l.append({"id": id, "nom": def["nom"], "mission": def.get("mission", ""), "ministere": s["ministere"], "responsables": s["responsables"], "budget_part": s["budget_part"], "indicateurs": d["indicateurs"], "besoins": d["besoins"], "rattaches": d["rattaches"]})
    return l

# ---------- Adaptateurs : ils LISENT les systèmes existants ----------

func _lire(source: String, c, jour: int) -> Dictionary:
    match source:
        "sante":
            return _sante(c, jour)
        "defense":
            return _defense(c, jour)
        "finances":
            return _finances(c)
    return {"indicateurs": [], "besoins": [], "rattaches": []}

func _sante(c, jour: int) -> Dictionary:
    var pop = c.population
    # Mêmes fonctions que le vrai système de soins (population.soigner) : aucun chiffre inventé.
    var malades: int = pop.a_soigner().size()
    var g: int = pop.nb_guerisseurs()
    var libres: int = pop.guerisseurs_dispos().size()
    var places: int = int(c.construction.effet_total("soin_places"))
    var capacite: int = pop.capacite_soins(places)
    var plantes: float = float(c.ressources.quantite("plantes_medicinales"))
    var ind: Array = [
        ["Habitants à soigner", str(malades)],
        ["Guérisseurs", "%d désignés, %d libres (maximum %d)" % [g, libres, pop.max_guerisseurs(jour)]],
        ["Soins possibles par jour", str(capacite)],
        ["Plantes médicinales", "%d kg" % int(plantes)],
    ]
    var besoins: Array = []
    if malades > 0 and g == 0:
        besoins.append("Aucun guérisseur : personne ne soigne.")
    elif malades > capacite:
        besoins.append("Capacité de soins insuffisante (%d à soigner pour %d soins par jour)." % [malades, capacite])
    if malades > 0 and plantes < float(malades) * float(pop.PLANTES_PAR_SOIN) * 10.0:
        besoins.append("Manque de plantes médicinales.")
    var rat: Array = ["Guérisseurs (rôle secondaire)", "Cueillette de plantes médicinales"]
    if places > 0:
        rat.append("Infirmerie (%d places)" % places)
    if c.decouvertes.connait("soins_organises"):
        rat.append("Culture des plantes médicinales")
    return {"indicateurs": ind, "besoins": besoins, "rattaches": rat}

func _defense(c, jour: int) -> Dictionary:
    var g = c.guerre
    var dispo: Array = g.combattants(c.population, c.ressources, jour)
    var armes: int = c.equipement.nombre("lance") + c.equipement.nombre("arc")
    var force: float = g.force_groupe(dispo, c.equipement, c.ressources, g.mobilises.size())
    var defense: float = g.defense(c.population, c.equipement, c.clotures, c.ressources, jour)
    var ind: Array = [
        ["Combattants disponibles", "%d (mobilisés : %d)" % [dispo.size(), g.mobilises.size()]],
        ["Protecteurs", "%d (maximum %d)" % [g.nb_protecteurs(c.population), g.max_protecteurs(c.population, jour)]],
        ["Armes (lances et arcs)", str(armes)],
        ["Force / défense", "%.1f / %.1f" % [force, defense]],
    ]
    var raids = c.get("raids")
    if raids != null:
        ind.append(["Crainte inspirée", "%d/100" % int(float(raids.crainte.get("joueur", 0.0)))])
    var besoins: Array = []
    if g.plafond(c.population, c.ressources, jour) < 2:
        besoins.append("Trop peu de combattants disponibles pour mobiliser un groupe.")
    if armes * 2 < dispo.size():
        besoins.append("Peu d'armes pour %d combattants." % dispo.size())
    if c.ressources.faim:
        besoins.append("La faim affaiblit les combattants.")
    var rat: Array = ["Protecteurs (rôle secondaire)", "Mobilisation temporaire"]
    if float(c.clotures.protection("village")) > 0.0:
        rat.append("Clôtures du village (+%d %% de défense)" % int(round(float(c.clotures.protection("village")) * 100.0)))
    if raids != null:
        rat.append("Raids")
    return {"indicateurs": ind, "besoins": besoins, "rattaches": rat}

func _finances(c) -> Dictionary:
    var b = c.get("budget")
    if b == null:
        return {"indicateurs": [["Impôt", "pas encore d'impôt chez ce clan"]], "besoins": [], "rattaches": ["Stocks du clan"]}
    var ind: Array = [
        ["Impôt", "%d %%" % int(round(float(b.taux) * 100.0))],
        ["Production permise", "%d %% de la normale" % int(round(float(b.facteur_productivite()) * 100.0))],
        ["Réserve commune", b._liste(b.caisse)],
    ]
    var besoins: Array = []
    if float(b.taux) > float(b.SANS_MALUS) + 0.0001:
        besoins.append("Impôt au-dessus de 10 % : le travail rend moins.")
    if float(b.taux) <= 0.0001:
        besoins.append("Aucun impôt : pas de réserve pour les chantiers et l'entretien.")
    return {"indicateurs": ind, "besoins": besoins, "rattaches": ["Impôt en nature", "Réserve commune (chantiers, entretien)"]}

# ---------- Sauvegarde ----------

func vers_dict() -> Dictionary:
    return {"secteurs": secteurs}

func depuis_dict(d: Dictionary) -> void:
    for id in actifs():
        secteurs[id] = _vide()
    for id in d.get("secteurs", {}):
        var x: Dictionary = d["secteurs"][id]
        secteurs[str(id)] = {"ministere": bool(x.get("ministere", false)), "responsables": x.get("responsables", []).map(func(i): return int(i)), "budget_part": float(x.get("budget_part", 0.0))}
