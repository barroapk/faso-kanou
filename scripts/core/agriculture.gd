extends RefCounted

# Agriculture et irrigation (v0.3.16 A).
# Les champs sont des données (la 3D les montrera plus tard).
# La terre est limitée : chaque clan cultive seulement son île (data/iles.json).
# Aucune terre n'est créée ; les améliorations augmentent le rendement, pas la surface.
# Rendement d'une récolte = rendement de la culture × hectares × fertilité
#   × part du travail fait^0,7 × part de l'eau reçue.
# Le travail vient des cultivateurs (compétence, outil : houe).
# L'eau vient des pluies, ou de l'irrigation : puits (nappe) et retenue (pluie
# retenue) ; un ouvrage ne crée pas d'eau, il garde celle qui tombe.

signal evenement(texte)

const RETENUE_EVAPORATION := 0.005    # part perdue par jour
const MOIS_PLUIES := [5, 6, 7, 8, 9]  # juin à octobre

var honneur_puits := 0.0       # puits portant le nom d'un héros (v0.3.30)
var cultures := {}
var regle := {}
var ile_id := ""
var ile := {}
var champs: Array = []
var prochain_id := 1
var eau_retenue := 0.0                # m³ gardés par les retenues
var semences := {}                    # réserve de semences, mise à part : on ne la mange pas
var recoltes := 0                     # nombre de récoltes réussies (pour les époques)
var territoire = null                 # territoire.gd : on ne cultive que ses propres parcelles
var clotures = null                   # clotures.gd : un champ clôturé perd moins de récolte
var routes = null                     # routes.gd : un champ hors du village doit être relié par la route

# Un champ hors de la parcelle du village ne fonctionne que s'il est relié.
func accessible(c: Dictionary) -> bool:
    if routes == null or territoire == null:
        return true
    return routes.parcelle_reliee(str(c.get("parcelle", territoire.cle(territoire.centre))), territoire)

func _init() -> void:
    var c = JSON.parse_string(FileAccess.get_file_as_string("res://data/cultures.json"))
    if typeof(c) == TYPE_DICTIONARY:
        cultures = c["cultures"]
        regle = c
    choisir_ile("kossi")

static func catalogue_iles() -> Dictionary:
    var t = JSON.parse_string(FileAccess.get_file_as_string("res://data/iles.json"))
    return t["iles"] if typeof(t) == TYPE_DICTIONARY else {}

func choisir_ile(id: String) -> void:
    var iles := catalogue_iles()
    if iles.has(id):
        ile_id = id
        ile = iles[id]

# ---------- Terre ----------

func surface_cultivee() -> float:
    var s := 0.0
    for c in champs:
        s += float(c["ha"])
    return s

func terre_libre() -> float:
    var limite: float = float(ile.get("cultivable_ha", 0.0))
    if territoire != null:
        limite = minf(limite, territoire.cultivable_possede())
    return maxf(0.0, limite - surface_cultivee())

# ---------- Aménagement (v0.3.19 T2) ----------
# Le joueur choisit la parcelle où il ouvre un champ. Trois notions distinctes :
#   terre cultivable (potentiel du sol, fixé par la parcelle),
#   champ défriché (travail fait : 20 jours d'adulte par ha, en saison sèche),
#   champ semé (cultivé et entretenu).
# Le défrichement ne crée pas de terre : il rend utilisable le potentiel d'une
# parcelle acquise. La fertilité dépend de l'île et de la qualité du sol choisi.
# Amender un champ (cendres) augmente la fertilité, jusqu'à +30 % au plus.

const CENDRES_HA := 200.0          # kg de cendres par ha pour un amendement
const GAIN_AMENDEMENT := 0.1       # +10 % de fertilité par amendement
const AMENDEMENT_MAX := 1.3        # au plus 1,3 × la fertilité naturelle
# Fumier (v0.3.37) : 3 tonnes par ha, +15 % de fertilité (même plafond 1,3).
# Il faut l'épandre : 1 adulte pendant 2 jours par ha (au moins 1 jour).
const FUMIER_HA := 3000.0
const GAIN_FUMIER := 0.15
const JOURS_FUMIER_HA := 2.0

# Terre encore libre dans une parcelle acquise.
func libre_parcelle(cle: String) -> float:
    if territoire == null or not territoire.possedees.has(cle):
        return 0.0
    var occupe := 0.0
    for c in champs:
        if str(c.get("parcelle", territoire.cle(territoire.centre))) == cle:
            occupe += float(c["ha"])
    return maxf(0.0, territoire.cultivable(territoire.pos(cle)) - occupe)

# Parcelles acquises qui ont encore de la terre libre, meilleur sol d'abord.
func parcelles_libres() -> Array:
    var l: Array = []
    if territoire == null:
        return l
    for k in territoire.possedees:
        if libre_parcelle(k) >= 0.5:
            l.append(k)
    l.sort_custom(func(a, b): return territoire.qualite(territoire.pos(a)) > territoire.qualite(territoire.pos(b)))
    return l

# Un nouveau champ sur une parcelle choisie ("" = la meilleure terre libre).
# Il faudra le défricher avant de le semer.
func creer_champ(ha: float, parcelle := "") -> String:
    if territoire != null:
        if parcelle == "":
            var l := parcelles_libres()
            if l.is_empty():
                return "Plus de terre cultivable libre sur notre territoire : acquérez une parcelle."
            parcelle = l[0]
        if not territoire.possedees.has(parcelle):
            return "Cette parcelle n'est pas acquise."
        ha = minf(ha, libre_parcelle(parcelle))
    else:
        ha = minf(ha, terre_libre())
    if ha < 0.1:
        return "Plus de terre cultivable libre ici : choisissez une autre parcelle ou acquérez-en une."
    var sol: float = territoire.qualite(territoire.pos(parcelle)) if territoire != null else 1.0
    var fert: float = float(ile.get("fertilite", 1.0)) * sol
    champs.append({"id": prochain_id, "ha": ha, "culture": "", "etat": "friche", "parcelle": parcelle,
        "fertilite": fert, "fertilite_max": fert, "defriche": false, "defrichage": 0.0,
        "semis": -1, "jours": 0, "eau": 0.0, "travail": 0.0, "irrigue": false})
    prochain_id += 1
    evenement.emit("Nouveau champ de %.1f ha à défricher (sol %d %%)." % [ha, int(sol * 100)])
    return ""

# Amender un champ avec des cendres (le feu de cuisine en produit chaque jour).
func amender(id: int, res) -> String:
    var c := champ(id)
    if c.is_empty():
        return "Champ inconnu."
    var base: float = float(c.get("fertilite_max", c["fertilite"]))
    if float(c["fertilite"]) >= base * AMENDEMENT_MAX - 0.001:
        return "Ce champ est déjà au mieux de sa fertilité."
    var besoin: float = CENDRES_HA * float(c["ha"])
    if res.quantite("cendres") < besoin:
        return "Il faut %d kg de cendres." % int(besoin)
    res.retirer("cendres", besoin, "amendement")
    c["fertilite"] = minf(base * AMENDEMENT_MAX, float(c["fertilite"]) + base * GAIN_AMENDEMENT)
    return ""
func amender_fumier(id: int, res) -> String:
    var c := champ(id)
    if c.is_empty():
        return "Champ inconnu."
    var base: float = float(c.get("fertilite_max", c["fertilite"]))
    if float(c["fertilite"]) >= base * AMENDEMENT_MAX - 0.001:
        return "Ce champ est déjà au mieux de sa fertilité."
    var besoin: float = FUMIER_HA * float(c["ha"])
    if float(res.objets.get("fumier", 0.0)) < besoin:
        return "Il faut %d kg de fumier (nous en avons %d)." % [int(besoin), int(res.objets.get("fumier", 0.0))]
    res.objets["fumier"] = float(res.objets["fumier"]) - besoin
    res.noter("amendement", "fumier", -besoin)
    c["fertilite"] = minf(base * AMENDEMENT_MAX, float(c["fertilite"]) + base * GAIN_FUMIER)
    return ""

func _defricher(force: float) -> float:
    var a_faire: Array = champs.filter(func(c): return not bool(c["defriche"]) and accessible(c))
    if a_faire.is_empty() or force <= 0.0:
        return force
    var c: Dictionary = a_faire[0]
    var total: float = float(regle.get("defrichage", 20.0)) * float(c["ha"])
    var fait: float = minf(force, total - float(c.get("defrichage", 0.0)))
    c["defrichage"] = float(c.get("defrichage", 0.0)) + fait
    if float(c["defrichage"]) >= total - 0.001:
        c["defriche"] = true
        evenement.emit("Champ %d défriché : prêt à semer." % int(c["id"]))
    return force - fait

func champ(id: int) -> Dictionary:
    for c in champs:
        if int(c["id"]) == id:
            return c
    return {}

# ---------- Semis ----------

func peut_semer_sans_irrigation(culture: String, mois: int) -> bool:
    for m in cultures.get(culture, {}).get("mois_semis", []):
        if int(m) == mois:
            return true
    return false

# Semences disponibles : la réserve d'abord, puis le stock de nourriture.
func semence(culture: String, res, besoin: float) -> String:
    for s in cultures[culture]["semences"]:
        if float(semences.get(s, 0.0)) + res.quantite(s) >= besoin:
            return s
    return ""

# Mettre des grains de côté pour les prochains semis (retirés de la nourriture).
func garder_semences(id: String, q: float, res) -> void:
    q = minf(q, res.quantite(id))
    if q > 0.0 and res.retirer(id, q, "semence"):
        semences[id] = float(semences.get(id, 0.0)) + q

# Renvoie "" si le champ est semé.
func semer(id: int, culture: String, res, jour: int, connait: Callable) -> String:
    var c := champ(id)
    if c.is_empty():
        return "Champ inconnu."
    if not connait.call("agriculture"):
        return "Le clan ne connaît pas encore l'agriculture."
    if not cultures.has(culture):
        return "Culture inconnue."
    if c["etat"] == "seme":
        return "Le champ est déjà semé."
    if not accessible(c):
        return "Ce champ n'est pas relié au village : construisez d'abord un sentier jusqu'à sa parcelle."
    if not bool(c["defriche"]):
        return "Il faut d'abord défricher ce champ (les cultivateurs le font quand ils ne sont pas aux semis)."
    var mois := (jour / 30) % 12
    var irrigue := not peut_semer_sans_irrigation(culture, mois)
    if irrigue and not connait.call("irrigation"):
        return "Ce n'est pas la saison des semis, et le clan ne sait pas irriguer."
    var f: Dictionary = cultures[culture]
    var besoin: float = float(f["semence_ha"]) * float(c["ha"])
    var s := semence(culture, res, besoin)
    if s == "":
        return "Pas assez de semences (%.0f kg nécessaires)." % besoin
    var de_reserve := minf(besoin, float(semences.get(s, 0.0)))
    semences[s] = float(semences.get(s, 0.0)) - de_reserve
    if besoin > de_reserve:
        res.retirer(s, besoin - de_reserve, "semence")
    c["culture"] = culture
    c["etat"] = "seme"
    c["semis"] = jour
    c["jours"] = 0
    c["eau"] = 0.0
    c["travail"] = 0.0
    c["irrigue"] = irrigue
    return ""

func travail_requis(c: Dictionary) -> float:
    return float(cultures[c["culture"]]["travail"]) * float(c["ha"])

# ---------- Chaque jour ----------

func jour_passe(pop, res, cons, jour: int, pluie: bool) -> void:
    var mois := (jour / 30) % 12
    _remplir_retenue(cons, pluie, mois)
    var force := 0.0
    for h in pop.habitants:
        if h["metier"] == "cultivateur" and not h.get("occupe", false):
            force += (0.6 + float(h["competence"]) / 100.0 * 0.8) * float(h.get("bonus_outil", 1.0))
    var semes: Array = champs.filter(func(c): return c["etat"] == "seme" and accessible(c))
    var reste_total := 0.0
    for c in semes:
        reste_total += maxf(0.0, travail_requis(c) - float(c["travail"]))
    # Sans travaux aux champs semés, les cultivateurs défrichent.
    if reste_total <= 0.0:
        _defricher(force)
    var eau_puits: float = cons.effet_total("irrigation_m3_jour") * (1.0 + honneur_puits)
    if routes != null and not routes.relie("eau"):
        eau_puits = 0.0   # puits sans route : il ne sert pas
    for c in semes:
        var reste := maxf(0.0, travail_requis(c) - float(c["travail"]))
        if reste_total > 0.0:
            c["travail"] = float(c["travail"]) + minf(reste, force * reste / reste_total)
        c["jours"] = int(c["jours"]) + 1
        if pluie:
            c["eau"] = float(c["eau"]) + 1.0
        elif bool(c["irrigue"]):
            var besoin: float = float(cultures[c["culture"]]["eau_m3_ha_jour"]) * float(c["ha"])
            var donne := minf(besoin, eau_puits)
            eau_puits -= donne
            var de_retenue := minf(besoin - donne, eau_retenue)
            eau_retenue -= de_retenue
            c["eau"] = float(c["eau"]) + (donne + de_retenue) / besoin
        if int(c["jours"]) >= int(cultures[c["culture"]]["cycle"]):
            _recolter(c, res, pop, jour)
    var rec := float(regle.get("recuperation_jachere_an", 0.08)) / 360.0
    for c in champs:
        if c["etat"] != "seme":
            c["fertilite"] = maxf(float(c["fertilite"]), minf(float(c.get("fertilite_max", ile.get("fertilite", 1.0))), float(c["fertilite"]) + rec))

func _remplir_retenue(cons, pluie: bool, mois: int) -> void:
    var cap: float = cons.effet_total("retenue_m3")
    if routes != null and not routes.relie("eau"):
        cap = 0.0         # retenue sans route : elle ne sert pas
    eau_retenue *= 1.0 - RETENUE_EVAPORATION
    if pluie and cap > 0.0:
        # Pluie qui ruisselle sur l'île, par jour de pluie (1 mm sur 1 ha = 10 m³).
        var arrivee: float = float(ile.get("pluie_mm", 0.0)) * 10.0 * float(ile.get("surface_ha", 0.0)) * float(ile.get("ruissellement", 0.0)) / (MOIS_PLUIES.size() * 30.0)
        eau_retenue = minf(cap, eau_retenue + arrivee)
    eau_retenue = minf(eau_retenue, cap)

func _recolter(c: Dictionary, res, pop, jour: int) -> void:
    var f: Dictionary = cultures[c["culture"]]
    var part_travail := clampf(float(c["travail"]) / travail_requis(c), 0.0, 1.0)
    var part_eau := clampf(float(c["eau"]) / float(f["cycle"]), 0.0, 1.0)
    var kg: float = float(f["rendement"]) * float(c["ha"]) * float(c["fertilite"]) * pow(part_travail, 0.7) * part_eau
    if routes != null and territoire != null:
        kg *= routes.acces_parcelle(str(c.get("parcelle", "")), territoire)   # chemin en mauvais état
    if clotures != null:
        kg *= 1.0 - clotures.perte_champ(int(c["id"]))   # bêtes, oiseaux, vols
    kg *= 1.0 - float(c.get("degats", 0.0))              # ravages d'un événement
    c["degats"] = 0.0
    if kg > 0.0:
        recoltes += 1
    res.ajouter(f["produit"], kg, "production")
    # Le paysan garde de quoi ressemer le même champ (+20 % de sécurité).
    garder_semences(f["produit"], float(f["semence_ha"]) * float(c["ha"]) * 1.2, res)
    c["fertilite"] = float(c["fertilite"]) * (1.0 - float(f["epuisement"]))
    c["etat"] = "recolte"
    evenement.emit("Récolte : %.0f kg de %s sur %.1f ha (travail %d %%, eau %d %%)." % [kg, f["nom"], float(c["ha"]), int(part_travail * 100), int(part_eau * 100)])

# Jour de la prochaine récolte (pour garder les cultivateurs à leur poste).
func prochaine_recolte() -> int:
    var j := -1
    for c in champs:
        if c["etat"] == "seme":
            var fin: int = int(c["semis"]) + int(cultures[c["culture"]]["cycle"])
            j = maxi(j, fin)
    return j

# ---------- Décisions de l'ordinateur (et conseil pour le joueur) ----------

# Avant et pendant les semis : un champ à la taille des cultivateurs, semé avec
# la meilleure culture dont on a les semences.
func gerer_auto(pop, res, jour: int, connait: Callable) -> void:
    if not connait.call("agriculture"):
        return
    var mois := (jour / 30) % 12
    if not mois in [4, 5, 6]:
        return
    _postes_cultivateurs(pop, jour)
    var n: int = int(pop.postes.get("cultivateur", 0))
    var voulu := maxf(1.0, n * float(regle.get("ha_par_cultivateur", 2.0)))
    if surface_cultivee() < voulu:
        creer_champ(voulu - surface_cultivee())
    for c in champs:
        if c["etat"] == "seme":
            continue
        for culture in ["sorgho", "mil", "fonio"]:
            # Pas assez de semences pour tout le champ : on sème ce qu'on peut,
            # le reste du champ retourne à la friche (terre libre).
            var dispo := 0.0
            for s in cultures[culture]["semences"]:
                dispo = maxf(dispo, float(semences.get(s, 0.0)) + res.quantite(s))
            var ha_possible := dispo / float(cultures[culture]["semence_ha"])
            if ha_possible < 0.1:
                continue
            if ha_possible < float(c["ha"]):
                c["ha"] = ha_possible
            if semer(int(c["id"]), culture, res, jour, connait) == "":
                break

# Un cultivateur pour 4 habitants (2 ha par cultivateur, aidé par sa famille :
# environ 0,5 ha cultivé par habitant, comme au Sahel). Un adulte
# libre d'abord ; sinon un cueilleur devient cultivateur (le champ remplace la
# cueillette), jamais un porteur d'eau ni un chasseur.
func _postes_cultivateurs(pop, jour: int) -> void:
    var voulu := int(ceil(pop.habitants.size() / float(regle.get("habitants_par_cultivateur", 4.0))))
    var adultes := 0
    for h in pop.habitants:
        if pop.age(h, jour) >= pop.AGE_ADULTE and h["metier"] != "chef" and h["metier"] != "ancien":
            adultes += 1
    var occupes := 0
    for m in pop.postes:
        occupes += int(pop.postes[m])
    while int(pop.postes.get("cultivateur", 0)) < voulu:
        if occupes < adultes:
            occupes += 1
        elif int(pop.postes.get("cueilleur", 0)) > 1:
            pop.postes["cueilleur"] = int(pop.postes["cueilleur"]) - 1
        else:
            break
        pop.postes["cultivateur"] = int(pop.postes.get("cultivateur", 0)) + 1

# ---------- Sauvegarde ----------

func vers_dict() -> Dictionary:
    return {"recoltes": recoltes, "ile": ile_id, "champs": champs, "prochain_id": prochain_id, "eau_retenue": eau_retenue, "semences": semences}

func depuis_dict(d: Dictionary) -> void:
    if d.is_empty():
        return
    # Sauvegarde v0.3.16 A (régions) : chaque ancienne région devient l'île du clan.
    var ancien := {"centre": "kossi", "nord": "wobe", "sud": "dafra"}
    choisir_ile(str(d.get("ile", ancien.get(str(d.get("region", "")), ile_id))))
    champs = d.get("champs", [])
    for c in champs:
        c["id"] = int(c["id"])
        if not c.has("defrichage"):   # ancienne sauvegarde : un champ déjà semé était défriché
            c["defriche"] = bool(c.get("defriche", false)) or c["etat"] != "friche"
    prochain_id = int(d.get("prochain_id", 1))
    eau_retenue = float(d.get("eau_retenue", 0.0))
    recoltes = int(d.get("recoltes", 0))
    semences = {}
    for k in d.get("semences", {}):
        semences[str(k)] = float(d["semences"][k])
