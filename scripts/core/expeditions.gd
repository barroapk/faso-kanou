extends RefCounted

# Expéditions en mer (v0.3.20 E3-E4) : explorer et visiter.
# La carte de l'archipel se découvre peu à peu : au départ, le clan ne connaît
# que son île. Une EXPLORATION part vers l'inconnu et peut trouver l'île la
# plus proche encore inconnue (ou revenir bredouille). Une VISITE va sur une
# île connue : elle renforce l'amitié (de moins en moins si on revient trop
# souvent) et permet d'OBSERVER les techniques de l'autre clan.
# Observer n'est pas maîtriser : une technique observée devient une idée
# d'expérience (même sans difficulté) et l'essai a plus de chances de réussir,
# surtout entre amis ou alliés. Il faut toujours expérimenter soi-même.
# Une expédition coûte : des adultes retirés de leur métier, des vivres pour
# l'aller-retour, et des risques en mer (tempête : un membre peut périr).

signal evenement(texte)

const VITESSE_KM := 40.0         # km par jour en grande pirogue
const SEJOUR := 5                # jours sur place
const VIVRES_JOUR := 0.8         # kg équivalent mil par personne et par jour
const RISQUE_MORT_JOUR := 0.003  # chance par jour en mer de perdre un membre
const CHANCE_DECOUVERTE := 0.6   # une exploration trouve une île 6 fois sur 10
const AMITIE_VISITE := 8.0       # points d'amitié d'une visite (divisés si visites rapprochées)
const DELAI_PLEIN := 180         # jours entre deux visites pour le gain complet
const HEROS = preload("res://scripts/core/heros.gd")
const MEMBRES := {"exploration": 2, "visite": 2}
const GARDER_AU_VILLAGE := 2     # adultes qui restent au travail (on ne vide pas le village)
# Bateau égaré (v0.3.27) : risque par jour en mer, selon le bateau, son état et la saison.
const RISQUE_EGARE_JOUR := 0.004
const SOLIDITE := {"pirogue": 1.0, "boutre": 0.6, "navire": 0.3}

var connues := {}                # ile_id -> niveau de connaissance (1 = vue, 2+ = visitée)
var visites := {}                # clan_id -> {"nb": n, "dernier": jour}
var en_cours := {}               # {type, cible, membres: [id], retour, ...}
var rng := RandomNumberGenerator.new()
var flotte = null                # flotte.gd : chaque expédition prend un bateau

func _init() -> void:
    rng.seed = 4242

func depart(ile_maison: String) -> void:
    if connues.is_empty():
        connues[ile_maison] = 9

func _iles() -> Dictionary:
    return load("res://scripts/core/agriculture.gd").catalogue_iles()

func _distance(a: String, b: String) -> float:
    var i := _iles()
    var pa: Dictionary = i[a]["carte"]
    var pb: Dictionary = i[b]["carte"]
    return Vector2(float(pa["x"]) - float(pb["x"]), float(pa["z"]) - float(pb["z"])).length()

func jours_mer(a: String, b: String) -> int:
    return maxi(1, int(ceil(_distance(a, b) / VITESSE_KM)))

# Lance une expédition. type = "exploration" (cible ignorée) ou "visite" (cible = île).
func lancer(type: String, cible: String, maison: String, pop, res, jour: int) -> String:
    if not en_cours.is_empty():
        return "Une expédition est déjà en mer."
    if type == "visite" and int(connues.get(cible, 0)) < 1:
        return "Cette île n'est pas encore connue : il faut d'abord l'explorer."
    var duree := SEJOUR
    if type == "visite":
        duree += 2 * jours_mer(maison, cible)
    else:
        var proche := _inconnue_proche(maison)
        if proche == "":
            return "Toutes les îles sont déjà connues."
        duree += 2 * jours_mer(maison, proche) + 4    # on cherche avant de trouver
    var membres := _choisir(pop, jour, int(MEMBRES[type]))
    if membres.size() < int(MEMBRES[type]):
        return "Pas assez d'adultes disponibles (%d nécessaires)." % int(MEMBRES[type])
    if _choisir(pop, jour, 99).size() - membres.size() < GARDER_AU_VILLAGE:
        return "Il faut garder au moins %d adultes au travail au village." % GARDER_AU_VILLAGE
    if flotte != null:
        var v: float = flotte.vitesse_libre(jour, membres.size(), 0.0)
        if v <= 0.0:
            return flotte.raison_aucun(jour, membres.size(), 0.0)
        # Un bateau plus rapide raccourcit le voyage.
        duree = SEJOUR + int(ceil((duree - SEJOUR) * VITESSE_KM / v))
    var vivres := VIVRES_JOUR * membres.size() * duree
    if res.total_aliments() < vivres:
        return "Il faut %d kg de vivres pour le voyage." % int(vivres)
    _payer_vivres(res, vivres)
    var bateau := {}
    if flotte != null:
        bateau = flotte.reserver(jour, jour + duree, membres.size(), 0.0, type)
    var ids: Array = []
    for h in membres:
        h["expedition"] = true
        h["metier"] = "sans métier"     # son poste est repris par un autre adulte
        ids.append(int(h["id"]))
    pop.repartir(jour)
    en_cours = {"type": type, "cible": cible, "membres": ids, "depart": jour, "retour": jour + duree, "jours_mer": duree - SEJOUR, "bateau": int(bateau.get("id", -1))}
    evenement.emit("Expédition (%s) partie avec %s, retour dans %d jours." % [type, ", ".join(membres.map(func(h): return h["prenom"])), duree])
    return ""

func _choisir(pop, jour: int, n: int) -> Array:
    var l: Array = []
    for h in pop.habitants:
        if pop.age(h, jour) >= pop.AGE_ADULTE and pop.age(h, jour) < 50 and not h["metier"] in ["chef", "ancien"] and not h.has("experience") and not h.has("expedition"):
            l.append(h)
    l.sort_custom(func(a, b): return float(a["competence"]) > float(b["competence"]))
    return l.slice(0, n)

func _payer_vivres(res, kgem: float) -> void:
    var total: float = res.total_aliments()
    for a in res.aliments.keys():
        var part: float = float(res.aliments[a]) * res.facteur(a) / total
        res.retirer(a, kgem * part / res.facteur(a), "expedition")

# La première île trouvée est toujours Wobé, celle du grand rival BARRO FASO.
func _inconnue_proche(maison: String) -> String:
    if maison != "wobe" and int(connues.get("wobe", 0)) < 1:
        return "wobe"
    var meilleure := ""
    var dmin := INF
    for id in _iles():
        if int(connues.get(id, 0)) >= 1:
            continue
        var d := _distance(maison, id)
        if d < dmin:
            dmin = d
            meilleure = id
    return meilleure

# Chaque jour : les membres ne travaillent pas ; dangers en mer ; retour.
# clans : {ile_id: [clan_id, objet clan]} ; moi : [clan_id, objet], diplomatie.
func jour_passe(pop, jour: int, maison: String, clans: Dictionary, moi_id: String, moi, diplomatie) -> void:
    if en_cours.is_empty():
        return
    var membres: Array = []
    for h in pop.habitants:
        if en_cours["membres"].has(int(h["id"])):
            h["occupe"] = true
            membres.append(h)
    if membres.is_empty():
        en_cours = {}
        return
    if rng.randf() < RISQUE_MORT_JOUR * membres.size() * 0.5:
        var perdu: Dictionary = membres[rng.randi() % membres.size()]
        evenement.emit("Tempête en mer : %s %s a péri pendant l'expédition." % [perdu["prenom"], perdu["nom"]])
        pop.faire_sortir(perdu, jour)
        en_cours["membres"].erase(int(perdu["id"]))
    _equipage = membres
    if en_cours.get("disparu", false):
        _attendre_disparu(pop, membres, jour, moi_id, diplomatie)
        return
    _risque_mer(jour)
    if jour < int(en_cours["retour"]):
        return
    if en_cours.get("egare", false):
        en_cours["disparu"] = true
        en_cours["disparu_le"] = jour
        var b := _bateau()
        if not b.is_empty():
            b["occupe_jusqu"] = 999999
        evenement.emit("Le bateau de l'expédition n'est pas revenu à la date prévue !")
        return
    for h in membres:
        h.erase("expedition")
    var type: String = en_cours["type"]
    var cible: String = en_cours["cible"]
    en_cours = {}
    if type == "exploration":
        var trouvee := _inconnue_proche(maison)
        if trouvee == "" or (trouvee != "wobe" and rng.randf() > CHANCE_DECOUVERTE + _bonus_equipage("navigateur")):
            evenement.emit("L'expédition revient sans avoir trouvé de nouvelle terre.")
            return
        connues[trouvee] = 1
        var t := "Exploration : %s est découverte !" % _iles()[trouvee]["nom"]
        if clans.has(trouvee):
            t += " Elle est habitée par le %s." % clans[trouvee][1].nom
            diplomatie.noter(moi_id, clans[trouvee][0], "contact", 3.0, "premier contact", jour)
        evenement.emit(t)
    else:
        _visiter(cible, clans, moi_id, moi, diplomatie, jour)
# --- Bateau disparu (v0.3.27) ---
func _bateau() -> Dictionary:
    if flotte == null:
        return {}
    for b in flotte.bateaux:
        if int(b["id"]) == int(en_cours.get("bateau", -1)):
            return b
    return {}
# Personne ne le sait encore : le bateau s'égare (tempête, courant, avarie).
func _risque_mer(jour: int) -> void:
    if en_cours.get("egare", false) or jour >= int(en_cours["retour"]) - SEJOUR / 2:
        return
    var b := _bateau()
    var mois := (jour / 30) % 12
    var r := RISQUE_EGARE_JOUR * (1.6 if mois >= 5 and mois <= 9 else 1.0)
    if not b.is_empty():
        r *= float(SOLIDITE.get(b["type"], 1.0)) * (1.5 - float(b["etat"]))
    r *= 1.0 - _bonus_equipage("navigateur")
    if rng.randf() < r:
        en_cours["egare"] = true
# Bonus du héros s'il fait partie de l'équipage (v0.3.29).
var _equipage: Array = []
func _bonus_equipage(type: String) -> float:
    var b := 0.0
    for h in _equipage:
        b = maxf(b, HEROS.bonus(h, type))
    return b
# Le joueur choisit les secours (defis.gd) ; sans choix, on attend.
func secourir(jusqu_a: int, chance: float, aide: String) -> void:
    en_cours["secours"] = jusqu_a
    en_cours["chance"] = chance
    en_cours["aide"] = aide
# Attente des secours, puis issue : retrouvé ou perdu.
func _attendre_disparu(pop, membres: Array, jour: int, moi_id: String, diplomatie) -> void:
    if not en_cours.has("secours"):
        if jour < int(en_cours["disparu_le"]) + 15:
            return
        secourir(jour + 15, 0.25, "")
    if jour < int(en_cours["secours"]):
        return
    var b := _bateau()
    var aide: String = en_cours.get("aide", "")
    for h in membres:
        h.erase("expedition")
    if rng.randf() < float(en_cours["chance"]):
        if not b.is_empty():
            b["occupe_jusqu"] = jour
            b["etat"] = minf(float(b["etat"]), 0.3)
        for h in membres:
            h["exploit"] = "navigateur"
        var t := "Le bateau disparu est retrouvé : l'équipage rentre épuisé, le bateau est très abîmé."
        if aide != "":
            diplomatie.noter(moi_id, aide, "secours", 6.0, "sauvetage en mer", jour)
            t += " Nos amis ont participé au sauvetage (relation +6)."
        evenement.emit(t)
    else:
        if not b.is_empty():
            flotte.bateaux.erase(b)
        var perdus: PackedStringArray = []
        for h in membres:
            if rng.randf() < 0.25:
                perdus.append(h["prenom"])
                pop.faire_sortir(h, jour)
            else:
                h["exploit"] = "navigateur"
        var t := "Le bateau est perdu en mer."
        if perdus.is_empty():
            t += " L'équipage a pu regagner la côte sur une épave."
        else:
            t += " Portés disparus : %s." % ", ".join(perdus)
        evenement.emit(t)
    en_cours = {}

const OBSERVATION := {"hostilité": 0.0, "rivalité": 0.5, "neutralité": 1.0, "amitié": 1.5, "alliance": 2.0}

# Une visite : amitié (moins si on revient trop vite) et techniques observées.
func _visiter(cible: String, clans: Dictionary, moi_id: String, moi, diplomatie, jour: int) -> void:
    connues[cible] = mini(5, maxi(2, int(connues.get(cible, 0)) + 1))
    if not clans.has(cible):
        evenement.emit("Visite terminée : l'île est déserte.")
        return
    var autre_id: String = clans[cible][0]
    var autre = clans[cible][1]
    var v: Dictionary = visites.get(autre_id, {"nb": 0, "dernier": -99999})
    var gain := AMITIE_VISITE * clampf(float(jour - int(v["dernier"])) / DELAI_PLEIN, 0.1, 1.0)
    diplomatie.noter(moi_id, autre_id, "visite", gain, "visite d'une délégation", jour)
    visites[autre_id] = {"nb": int(v["nb"]) + 1, "dernier": jour}
    var niveau: float = OBSERVATION.get(diplomatie.etat(moi_id, autre_id), 1.0)
    var vues: PackedStringArray = []
    if niveau > 0.0:
        for t in autre.decouvertes.connues:
            if not moi.decouvertes.connait(t):
                moi.decouvertes.observer(t, niveau)
                vues.append(moi.decouvertes.definitions[t]["nom"])
    var texte := "Visite chez le %s : amitié +%d." % [autre.nom, int(gain)]
    texte += (" Techniques observées : %s." % ", ".join(vues)) if vues.size() > 0 else " Rien de nouveau à apprendre chez eux."
    evenement.emit(texte)

# Ce que le clan sait d'une île (pour l'écran) : plus on y va, plus on en sait.
func fiche(ile_id: String, clans: Dictionary, jour: int) -> String:
    var niv := int(connues.get(ile_id, 0))
    var i: Dictionary = _iles()[ile_id]
    if niv <= 0:
        return "Île inconnue."
    var t := "%s — %s." % [i["nom"], i["forme"]]
    if not clans.has(ile_id):
        return t
    var c = clans[ile_id][1]
    t += "\nHabitée par le %s." % c.nom
    if niv < 2:
        return t + " Il faut la visiter pour en savoir plus."
    t += "\nEnviron %d habitants, chef : %s. %d hutte(s), %d grenier(s)." % [c.population.habitants.size(), c.nom_du_chef(), c.construction.nombre("hutte"), c.construction.nombre("grenier")]
    var postes: PackedStringArray = []
    for m in c.population.postes:
        if int(c.population.postes[m]) > 0:
            postes.append("%s %d" % [m, int(c.population.postes[m])])
    t += "\nActivités : %s." % ", ".join(postes)
    if niv >= 3:
        var sav: PackedStringArray = []
        for d in c.decouvertes.connues:
            sav.append(c.decouvertes.definitions[d]["nom"])
        t += "\nTechniques : %s. Champs : %.1f ha. Territoire : %d ha." % [", ".join(sav) if sav.size() > 0 else "aucune", c.agriculture.surface_cultivee(), int(c.territoire.surface_possedee())]
    return t

func vers_dict() -> Dictionary:
    return {"connues": connues, "visites": visites, "en_cours": en_cours, "graine": rng.seed, "etat": rng.state}

func depuis_dict(d: Dictionary) -> void:
    connues = {}
    for k in d.get("connues", {}):
        connues[str(k)] = int(d["connues"][k])
    visites = d.get("visites", {})
    en_cours = d.get("en_cours", {})
    if en_cours.has("membres"):
        en_cours["membres"] = en_cours["membres"].map(func(x): return int(x))
    if d.has("graine"):
        rng.seed = int(d["graine"])
        rng.state = int(d["etat"])
