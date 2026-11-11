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

var secteurs := {}     # id -> {"ministere": bool, "responsables": [ids], "postes": {poste: id}, "budget_part": float}

# ---------- Nominations (v0.3.55) ----------
# Le jeu propose, le joueur choisit. Un nommé reste un habitant réel : sa fonction
# (h["fonction"]) lui prend une part de son temps de travail, jamais tout (population.part_libre).
# Aucun bonus n'est encore donné par une fonction : seul le coût en temps existe.
const CRITERES := ["competence", "experience", "loyaute", "sante", "disponibilite", "anciennete"]
const NOMS_CRITERES := {"competence": "compétence", "experience": "expérience", "loyaute": "loyauté", "sante": "santé", "disponibilite": "temps libre", "anciennete": "ancienneté (ans)"}
const TEMPS_MIN_RESTANT := 0.4     # il doit rester au moins 40 % de son temps à son métier
const SANTE_MIN := 50
const COMP_MIN_AUTO := 10.0        # la proposition automatique n'écarte pas les incompétents d'office sauf sous ce seuil
const VITAUX := ["cultivateur", "porteur d'eau", "pêcheur", "chasseur"]
const POIDS_AUTO := {"competence": 0.4, "experience": 0.2, "loyaute": 0.2, "sante": 0.1, "disponibilite": 0.1}

var ecartes := {}      # "secteur:poste" -> ids refusés par le joueur (non sauvegardé)

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
    return {"ministere": false, "responsables": [], "postes": {}, "budget_part": 0.0}

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

# Niveau de maturité : coutumière sans responsable, émergente dès qu'une fonction est confiée.
func maturite() -> Dictionary:
    var emergente := false
    for id in secteurs:
        if bool(secteurs[id]["ministere"]):
            return maturites()[2]
        if not secteurs[id]["postes"].is_empty():
            emergente = true
    return maturites()[1] if emergente else maturites()[0]

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
        secteurs[str(id)] = {"ministere": bool(x.get("ministere", false)), "responsables": x.get("responsables", []).map(func(i): return int(i)), "postes": _postes_lus(x.get("postes", {})), "budget_part": float(x.get("budget_part", 0.0))}

static func _postes_lus(d) -> Dictionary:
    var r := {}
    if typeof(d) == TYPE_DICTIONARY:
        for p in d:
            r[str(p)] = int(d[p])
    return r

# ---------- Nominations ----------

static func postes_def() -> Dictionary:
    _charger()
    return _cat.get("postes", {})

func titulaire_de(sid: String, poste: String) -> int:
    return int(secteurs.get(sid, {}).get("postes", {}).get(poste, -1))

func fonction_de(id: int) -> Dictionary:
    for sid in secteurs:
        for p in secteurs[sid]["postes"]:
            if int(secteurs[sid]["postes"][p]) == id:
                return {"secteur": sid, "poste": p}
    return {}

func _habitant(c, id: int) -> Dictionary:
    for h in c.population.habitants:
        if int(h["id"]) == id:
            return h
    return {}

func _nom_secteur(sid: String) -> String:
    return str(_cat.get("secteurs", {}).get(sid, {}).get("nom", sid))

func _sync(sid: String) -> void:
    var l: Array = []
    for p in secteurs[sid]["postes"]:
        l.append(int(secteurs[sid]["postes"][p]))
    secteurs[sid]["responsables"] = l

# Raison pour laquelle cette personne NE PEUT PAS occuper le poste ("" si elle le peut).
func peut_occuper(h: Dictionary, sid: String, poste: String, c, jour: int) -> String:
    var d: Dictionary = postes_def().get(poste, {})
    if d.is_empty() or not secteurs.has(sid):
        return "Poste inconnu."
    if titulaire_de(sid, poste) >= 0:
        return "Le poste est déjà pourvu."
    if poste != "titulaire" and titulaire_de(sid, "titulaire") < 0:
        return "Il faut d'abord un responsable."
    var id := int(h["id"])
    if c.population.age(h, jour) < int(d.get("age_min", 18)):
        return "Trop jeune pour cette fonction."
    if h["metier"] == "chef":
        return "Le conseiller ne cumule pas de fonction."
    if not fonction_de(id).is_empty():
        return "Occupe déjà une fonction."
    if h.has("expedition"):
        return "Absent en expédition."
    var guerre = c.get("guerre")
    if guerre != null and guerre.mobilises.has(id):
        return "Mobilisé pour la guerre."
    if int(h["sante"]) < SANTE_MIN:
        return "Trop affaibli pour cette fonction."
    if c.population.part_libre(h) - float(d.get("temps", 0.0)) < TEMPS_MIN_RESTANT:
        return "Pas assez de temps libre."
    return ""

# Les six critères, séparément (0 à 100, sauf l'ancienneté en années).
func criteres(h: Dictionary, sid: String, c, jour: int) -> Dictionary:
    var pop = c.population
    var n: Dictionary = c.conseil.notes(h, pop, jour)
    var sv: String = str(_cat.get("secteurs", {}).get(sid, {}).get("savoir", ""))
    var comp: float = pop.savoir(h, sv) if sv != "" else float(n["gestion"])
    var debut: int = int(h.get("arrivee", h["naissance"]))
    return {
        "competence": comp,
        "experience": float(n["experience"]),
        "loyaute": float(h.get("loyaute", 60.0)),
        "sante": float(h["sante"]),
        "disponibilite": pop.part_libre(h) * 100.0,
        "anciennete": float(jour - debut) / 360.0,
    }

func _seul_de_son_metier(h: Dictionary, c) -> bool:
    if not VITAUX.has(str(h["metier"])):
        return false
    var n := 0
    for x in c.population.habitants:
        if x["metier"] == h["metier"]:
            n += 1
    return n <= 1

# Filtres par défaut du concours : seule la compétence est exigée ; les autres sont facultatifs.
static func filtres_defaut() -> Dictionary:
    return {
        "competence": {"actif": true, "seuil": 20},
        "experience": {"actif": false, "seuil": 20},
        "loyaute": {"actif": false, "seuil": 50},
        "sante": {"actif": false, "seuil": 70},
        "disponibilite": {"actif": false, "seuil": 50},
        "anciennete": {"actif": false, "seuil": 5},
    }

# Candidats qui peuvent réellement occuper le poste ET passent les filtres actifs.
# Un filtre désactivé n'élimine personne. Aucun score global : chaque critère reste lisible.
func candidats(sid: String, poste: String, c, jour: int, filtres: Dictionary) -> Array:
    var l: Array = []
    for h in c.population.habitants:
        if peut_occuper(h, sid, poste, c, jour) != "":
            continue
        var v := criteres(h, sid, c, jour)
        var ok := true
        for k in CRITERES:
            var f: Dictionary = filtres.get(k, {})
            if bool(f.get("actif", false)) and float(v[k]) < float(f.get("seuil", 0)):
                ok = false
        if ok:
            l.append({"id": int(h["id"]), "nom": "%s %s" % [h["prenom"], h["nom"]], "age": c.population.age(h, jour), "metier": c.population.nom_metier(h), "v": v, "vital": _seul_de_son_metier(h, c)})
    l.sort_custom(func(a, b): return float(a["v"]["competence"]) > float(b["v"]["competence"]))
    return l

# Mode automatique : UNE proposition que le joueur confirme ou refuse.
func proposer(sid: String, poste: String, c, jour: int) -> Dictionary:
    var ex: Array = ecartes.get(sid + ":" + poste, [])
    var meilleur := {}
    var m := -1.0
    for cand in candidats(sid, poste, c, jour, {}):
        if ex.has(cand["id"]) or bool(cand["vital"]) or float(cand["v"]["competence"]) < COMP_MIN_AUTO:
            continue
        var sc := 0.0
        for k in POIDS_AUTO:
            sc += float(POIDS_AUTO[k]) * float(cand["v"][k])
        if sc > m:
            m = sc
            meilleur = cand
    return meilleur

func refuser(sid: String, poste: String, id: int) -> void:
    var cle := sid + ":" + poste
    if not ecartes.has(cle):
        ecartes[cle] = []
    ecartes[cle].append(id)

# Renvoie "" si c'est fait, sinon la raison du refus. Revérifie toujours que la personne peut occuper le poste.
func nommer(sid: String, poste: String, id: int, c, jour: int) -> String:
    var h := _habitant(c, id)
    if h.is_empty():
        return "Cette personne n'est plus là."
    var r := peut_occuper(h, sid, poste, c, jour)
    if r != "":
        return r
    var d: Dictionary = postes_def()[poste]
    secteurs[sid]["postes"][poste] = id
    h["fonction"] = {"secteur": sid, "poste": poste, "temps": float(d.get("temps", 0.0)), "depuis": jour}
    _sync(sid)
    ecartes.erase(sid + ":" + poste)
    evenement.emit("%s %s est nommé %s (%s)." % [h["prenom"], h["nom"], d["nom"], _nom_secteur(sid)])
    return ""

# Le joueur peut toujours relever quelqu'un ; la personne n'apprécie pas (loyauté -10).
func revoquer(sid: String, poste: String, c) -> String:
    var id := titulaire_de(sid, poste)
    if id < 0:
        return "Ce poste est déjà vacant."
    secteurs[sid]["postes"].erase(poste)
    _sync(sid)
    var h := _habitant(c, id)
    if not h.is_empty():
        h.erase("fonction")
        h["loyaute"] = maxf(0.0, float(h.get("loyaute", 60.0)) - 10.0)
        evenement.emit("%s %s est relevé de ses fonctions (%s)." % [h["prenom"], h["nom"], _nom_secteur(sid)])
    return ""

# Chaque jour : mort ou départ => poste vacant ; devenu conseiller => fonction retirée ; temps toujours appliqué.
func verifier(c) -> void:
    for sid in secteurs:
        for poste in secteurs[sid]["postes"].keys():
            var id := int(secteurs[sid]["postes"][poste])
            var h := _habitant(c, id)
            var d: Dictionary = postes_def().get(poste, {})
            if h.is_empty():
                secteurs[sid]["postes"].erase(poste)
                _sync(sid)
                evenement.emit("Le poste de %s (%s) est vacant : son titulaire est mort ou parti." % [d.get("nom", poste), _nom_secteur(sid)])
            elif h["metier"] == "chef":
                secteurs[sid]["postes"].erase(poste)
                _sync(sid)
                h.erase("fonction")
                evenement.emit("%s %s devient conseiller : le poste de %s (%s) est vacant." % [h["prenom"], h["nom"], d.get("nom", poste), _nom_secteur(sid)])
            elif not h.has("fonction"):
                h["fonction"] = {"secteur": sid, "poste": poste, "temps": float(d.get("temps", 0.0)), "depuis": 0}
