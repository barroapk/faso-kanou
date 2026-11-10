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

var cultures := {}
var regle := {}
var ile_id := ""
var ile := {}
var champs: Array = []
var prochain_id := 1
var eau_retenue := 0.0                # m³ gardés par les retenues
var semences := {}                    # réserve de semences, mise à part : on ne la mange pas

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
    return maxf(0.0, float(ile.get("cultivable_ha", 0.0)) - surface_cultivee())

# Un nouveau champ : il faudra le défricher (travail) avant la première récolte.
func creer_champ(ha: float) -> String:
    ha = minf(ha, terre_libre())
    if ha < 0.1:
        return "Plus de terre cultivable libre sur l'île."
    champs.append({"id": prochain_id, "ha": ha, "culture": "", "etat": "friche",
        "fertilite": float(ile.get("fertilite", 1.0)), "defriche": false,
        "semis": -1, "jours": 0, "eau": 0.0, "travail": 0.0, "irrigue": false})
    prochain_id += 1
    evenement.emit("Nouveau champ de %.1f ha (%s)." % [ha, ile.get("nom", ile_id)])
    return ""

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
    var t: float = float(cultures[c["culture"]]["travail"]) * float(c["ha"])
    if not bool(c["defriche"]):
        t += float(regle.get("defrichage", 20.0)) * float(c["ha"])
    return t

# ---------- Chaque jour ----------

func jour_passe(pop, res, cons, jour: int, pluie: bool) -> void:
    var mois := (jour / 30) % 12
    _remplir_retenue(cons, pluie, mois)
    var force := 0.0
    for h in pop.habitants:
        if h["metier"] == "cultivateur" and not h.get("occupe", false):
            force += (0.6 + float(h["competence"]) / 100.0 * 0.8) * float(h.get("bonus_outil", 1.0))
    var semes: Array = champs.filter(func(c): return c["etat"] == "seme")
    var reste_total := 0.0
    for c in semes:
        reste_total += maxf(0.0, travail_requis(c) - float(c["travail"]))
    var eau_puits: float = cons.effet_total("irrigation_m3_jour")
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
            c["fertilite"] = minf(float(ile.get("fertilite", 1.0)), float(c["fertilite"]) + rec)

func _remplir_retenue(cons, pluie: bool, mois: int) -> void:
    var cap: float = cons.effet_total("retenue_m3")
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
    res.ajouter(f["produit"], kg, "production")
    # Le paysan garde de quoi ressemer le même champ (+20 % de sécurité).
    garder_semences(f["produit"], float(f["semence_ha"]) * float(c["ha"]) * 1.2, res)
    c["defriche"] = c["defriche"] or part_travail >= 0.999
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
    var voulu := maxf(1.0, n * float(regle.get("ha_par_cultivateur", 1.5)))
    if surface_cultivee() < voulu:
        creer_champ(voulu - surface_cultivee())
    for c in champs:
        if c["etat"] == "seme":
            continue
        for culture in ["sorgho", "mil", "fonio"]:
            if semer(int(c["id"]), culture, res, jour, connait) == "":
                break

# Un cultivateur pour 5 habitants (une famille nourrie par champ). Un adulte
# libre d'abord ; sinon un cueilleur devient cultivateur (le champ remplace la
# cueillette), jamais un porteur d'eau ni un chasseur.
func _postes_cultivateurs(pop, jour: int) -> void:
    var voulu := int(ceil(pop.habitants.size() / 5.0))
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
    return {"ile": ile_id, "champs": champs, "prochain_id": prochain_id, "eau_retenue": eau_retenue, "semences": semences}

func depuis_dict(d: Dictionary) -> void:
    if d.is_empty():
        return
    # Sauvegarde v0.3.16 A (régions) : chaque ancienne région devient l'île du clan.
    var ancien := {"centre": "kossi", "nord": "wobe", "sud": "dafra"}
    choisir_ile(str(d.get("ile", ancien.get(str(d.get("region", "")), ile_id))))
    champs = d.get("champs", [])
    for c in champs:
        c["id"] = int(c["id"])
    prochain_id = int(d.get("prochain_id", 1))
    eau_retenue = float(d.get("eau_retenue", 0.0))
    semences = {}
    for k in d.get("semences", {}):
        semences[str(k)] = float(d["semences"][k])
