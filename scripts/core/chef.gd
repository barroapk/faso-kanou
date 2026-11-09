extends RefCounted

# Le chef : superviseur nommé par le joueur (v0.3.3.1 : missions et alertes).
# Il lit les problèmes calculés par besoins.gd et ne garde que ceux
# qu'il est capable de voir, selon ses missions et ses notes :
#   prévoyance -> combien de jours à l'avance il voit un danger (5 à 45)
#   gestion    -> combien de problèmes il suit en même temps (1 à 3)
# Ordre de suivi : d'abord les urgences (danger dans 10 jours ou moins), de la
# plus proche à la plus lointaine ; ensuite la mission principale ; puis le reste.
# S'il y a plus d'urgences que de places, il le dit au joueur (débordé).
# Il ne change jamais rien dans le jeu : il alerte, le joueur décide.
# Il fait sa revue tous les 5 jours (REVUE_JOURS).

signal evenement(texte)

# Chaque mission couvre des ressources et des types de problèmes de besoins.gd.
const MISSIONS := {
    "eau": {"nom": "Gestion de l'eau", "ressources": ["eau"], "types": ["deficit", "marge", "stockage"]},
    "nourriture": {"nom": "Surveillance alimentaire", "ressources": ["nourriture"], "types": ["deficit", "marge", "stockage"]},
    "constructions": {"nom": "Bois et constructions", "ressources": ["bois"], "types": ["deficit", "marge", "stockage"]},
    "travail": {"nom": "Organisation du travail", "ressources": ["eau", "nourriture", "bois"], "types": ["surplus"]},
}
const SECONDAIRES_MAX := 2
const REVUE_JOURS := 5
const DANGER_IMMINENT := 10.0
const COEF_SECONDAIRE := 0.75
# Délai avant que le problème devienne dangereux, quand il n'y a pas de rupture calculée.
const DELAI_PAR_TYPE := {"marge": 40.0, "stockage": 30.0, "surplus": 30.0}

var principale := "nourriture"
var secondaires: Array = ["eau"]
var alertes: Array = []
var _deja_signale := {}
var manquees := 0
var hors_mission := 0
var debordes := 0
var _manques := {}
var _deborde_signale := 0

# ---------- Choix du joueur ----------

# Renvoie "" si c'est fait, sinon la raison du refus.
func definir_missions(p: String, s: Array) -> String:
    if not MISSIONS.has(p):
        return "Mission inconnue : %s." % p
    if s.size() > SECONDAIRES_MAX:
        return "Deux missions secondaires au maximum."
    var vues := [p]
    for m in s:
        if not MISSIONS.has(m):
            return "Mission inconnue : %s." % m
        if vues.has(m):
            return "La mission %s est donnée deux fois." % MISSIONS[m]["nom"]
        vues.append(m)
    principale = p
    secondaires = s.duplicate()
    _deja_signale = {}
    return ""

# ---------- Capacités ----------

static func horizon(prevoyance: float) -> float:
    return 5.0 + clampf(prevoyance, 0.0, 100.0) / 100.0 * 40.0

static func suivis_max(gestion: float) -> int:
    return 1 + mini(2, int(clampf(gestion, 0.0, 100.0) / 34.0))

static func delai_danger(p: Dictionary) -> float:
    if p["type"] == "deficit":
        return maxf(0.0, float(p["jours_rupture"])) if float(p["jours_rupture"]) >= 0.0 else 999.0
    return DELAI_PAR_TYPE.get(p["type"], 999.0)

# ---------- Revue ----------

func revue(conseil, pop, besoins, jour: int) -> void:
    if conseil.chef_id < 0:
        alertes = []
        return
    var h: Dictionary = conseil.habitant(pop, conseil.chef_id)
    if h.is_empty():
        alertes = []
        return
    analyser(besoins.problemes, conseil.notes(h, pop, jour), jour)
    for a in alertes:
        var cle: String = a["cle"]
        if int(_deja_signale.get(cle, -1)) < int(a["niveau"]):
            evenement.emit(texte_alerte(a, h["prenom"]))
        _deja_signale[cle] = int(a["niveau"])
    var actives := {}
    for p in besoins.problemes:
        actives[_cle(p)] = true
    for cle in _deja_signale.keys():
        if not actives.has(cle):
            _deja_signale.erase(cle)
    if debordes > _deborde_signale:
        evenement.emit("%s est débordé : %d autre(s) urgence(s) sans suivi." % [h["prenom"], debordes])
    _deborde_signale = debordes

# Fonction pure (testable) : problèmes + notes du chef -> alertes retenues.
func analyser(problemes: Array, notes: Dictionary, jour: int) -> void:
    var vision := horizon(notes["prevoyance"])
    var candidats := []
    for p in problemes:
        var mission := _mission_de(p)
        if mission == "":
            continue
        var portee := vision if mission == principale else vision * COEF_SECONDAIRE
        var delai := delai_danger(p)
        if delai > portee:
            continue
        candidats.append({
            "cle": _cle(p),
            "ressource": p["ressource"],
            "type": p["type"],
            "niveau": p["niveau"],
            "mission": mission,
            "principale": mission == principale,
            "delai": delai,
            "probleme": p,
            "jour": jour,
        })
    candidats.sort_custom(func(a, b):
        var ua: bool = a["delai"] <= DANGER_IMMINENT
        var ub: bool = b["delai"] <= DANGER_IMMINENT
        if ua != ub:
            return ua
        if not ua and a["principale"] != b["principale"]:
            return a["principale"]
        return a["delai"] < b["delai"])
    var places := suivis_max(notes["gestion"])
    alertes = candidats.slice(0, places)
    # Débordé : urgences qu'il voit mais ne peut pas suivre (pas celles qu'il ne voit pas).
    debordes = 0
    for c in candidats.slice(places):
        if c["delai"] <= DANGER_IMMINENT:
            debordes += 1
    var encore := {}
    for p in problemes:
        if p["type"] != "deficit" or delai_danger(p) > DANGER_IMMINENT or _alerte(_cle(p)):
            continue
        var cle := _cle(p)
        encore[cle] = true
        var dans_mission := _mission_de(p) != ""
        if not _manques.has(cle):
            if dans_mission:
                manquees += 1
            else:
                hors_mission += 1
    _manques = encore

func _mission_de(p: Dictionary) -> String:
    for m in [principale] + secondaires:
        var def: Dictionary = MISSIONS[m]
        if def["ressources"].has(p["ressource"]) and def["types"].has(p["type"]):
            return m
    return ""

func _cle(p: Dictionary) -> String:
    return "%s_%s" % [p["ressource"], p["type"]]

func _alerte(cle: String) -> bool:
    for a in alertes:
        if a["cle"] == cle:
            return true
    return false

const DE := {"eau": "d'eau", "nourriture": "de nourriture", "bois": "de bois"}

func texte_alerte(a: Dictionary, prenom: String) -> String:
    var r: String = DE.get(a["ressource"], "de " + a["ressource"])
    match a["type"]:
        "deficit":
            if a["delai"] < 1.0:
                return "%s : pénurie %s imminente !" % [prenom, r]
            return "%s : risque de pénurie %s dans %d jours." % [prenom, r, int(a["delai"])]
        "marge":
            return "%s : la production %s suffit à peine." % [prenom, r]
        "stockage":
            return "%s : nos réserves %s sont trop petites." % [prenom, r]
        "surplus":
            return "%s : trop de travailleurs pour la production %s." % [prenom, r]
    return "%s : problème %s." % [prenom, r]

# ---------- Sauvegarde ----------

func vers_dict() -> Dictionary:
    return {
        "principale": principale,
        "secondaires": secondaires,
        "deja_signale": _deja_signale,
        "manques": _manques.keys(),
        "deborde_signale": _deborde_signale,
        "manquees": manquees,
        "hors_mission": hors_mission,
    }

func depuis_dict(d: Dictionary) -> void:
    principale = str(d.get("principale", "nourriture"))
    secondaires = []
    for m in d.get("secondaires", ["eau"]):
        secondaires.append(str(m))
    _deja_signale = {}
    var ds: Dictionary = d.get("deja_signale", {})
    for cle in ds:
        _deja_signale[cle] = int(ds[cle])
    _manques = {}
    for cle in d.get("manques", []):
        _manques[str(cle)] = true
    _deborde_signale = int(d.get("deborde_signale", 0))
    manquees = int(d.get("manquees", 0))
    hors_mission = int(d.get("hors_mission", 0))
