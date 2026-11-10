extends RefCounted

# Routes (v0.3.19 T4) : un seul réseau qui part du village.
# Destinations : l'eau (rivière, source), la forêt, la carrière, la mine, le
# port, et les parcelles où sont les champs. Leur distance vient de l'île :
# une île à 4 rivières a l'eau près du village, une île sans forêt l'a loin.
# Règle : un équipement (champ hors du village, puits, retenue, plus tard le
# port et les mines) ne fonctionne que s'il est relié au village par la route.
# Les ressources naturelles restent accessibles sans route (on porte l'eau, on
# coupe le bois à pied) ; une route rend seulement le travail plus efficace.
# Une parcelle se relie depuis une parcelle déjà reliée (ou le village) :
# le réseau grandit de proche en proche, jamais en morceaux isolés.

signal evenement(texte)

const NIVEAUX := ["sentier", "chemin", "route", "boulevard"]
const DEF := {
    "sentier": {"nom": "Sentier", "cout_km": {}, "travail_km": 10.0, "bonus": 0.10},
    "chemin": {"nom": "Chemin aménagé", "cout_km": {"bois": 40.0}, "travail_km": 40.0, "bonus": 0.20},
    "route": {"nom": "Route empierrée", "cout_km": {"pierre": 300.0}, "travail_km": 120.0, "bonus": 0.35},
    "boulevard": {"nom": "Boulevard", "cout_km": {"pierre": 800.0, "bois": 100.0}, "travail_km": 300.0, "bonus": 0.50},
}
const NOMS := {"eau": "le point d'eau", "foret": "la forêt", "carriere": "la carrière", "mine": "la mine de fer", "port": "le port"}
const ENTRETIEN := 0.05          # (ancien entretien annuel, remplacé par l'état v0.3.32b)
# État des routes (v0.3.32b) : de 1 (bon) à 0. Il baisse chaque mois (pluies +50 %).
# Une seule formule d'accès pour tout ce qui dépend d'une route : acces(dest).
#   bon état : 1 ; dégradé : jusqu'à 0,5 ; sous 0,2 : inutilisable (0).
# La réparation prend le travail des bâtisseurs libres et des matériaux :
# remettre à neuf coûte 20 % du travail et des matériaux de construction.
const USURE_MOIS := {"sentier": 0.04, "chemin": 0.03, "route": 0.015, "boulevard": 0.01}
const INUTILISABLE := 0.2
const PART_REPARATION := 0.2
const PRIORITE := ["eau", "parcelle_", "foret", "carriere", "mine", "port"]

var ile := {}
var troncons := {}               # destination -> {niveau, km, travail_restant, cout}

func installer(ile_dict: Dictionary) -> void:
    ile = ile_dict

# Distance (km) du village à chaque destination naturelle.
func destinations() -> Dictionary:
    var r: Dictionary = ile.get("richesse", {})
    var e: Dictionary = ile.get("eau_douce", {})
    var d := {
        "eau": 0.5 + 4.0 / (1.0 + float(e.get("rivieres", 0)) + 0.5 * float(e.get("sources", 0))),
        "foret": 0.5 + 2.5 / maxf(0.2, float(r.get("bois", 1.0))),
        "carriere": 1.0 + 3.0 / maxf(0.2, float(r.get("pierre", 1.0))),
        "port": 1.0 + 6.0 / (1.0 + float(ile.get("littoral", {}).get("baies", 1))),
    }
    if float(r.get("fer", 0.0)) >= 0.3:
        d["mine"] = 2.0 + 6.0 / float(r.get("fer", 1.0))
    return d

func nom(dest: String) -> String:
    return NOMS.get(dest, "la parcelle %s" % dest.trim_prefix("parcelle_"))

# Une destination est-elle reliée (tronçon terminé) ? Le village l'est toujours.
func relie(dest: String) -> bool:
    if dest == "village":
        return true
    return troncons.has(dest) and float(troncons[dest]["travail_restant"]) <= 0.0 and etat(dest) >= INUTILISABLE
func etat(dest: String) -> float:
    return float(troncons[dest].get("etat", 1.0)) if troncons.has(dest) else 0.0
# Formule commune d'accessibilité : champs, mines, carrière, forêt, eau, port.
func acces(dest: String) -> float:
    if dest == "village":
        return 1.0
    if not relie(dest):
        return 0.0
    return 0.5 + 0.5 * etat(dest)

func niveau(dest: String) -> int:
    if not relie(dest):
        return -1
    return NIVEAUX.find(troncons[dest]["niveau"])

# Gain d'efficacité du travail vers une destination (0 sans route).
func bonus(dest: String) -> float:
    var n := niveau(dest)
    return 0.0 if n < 0 else float(DEF[NIVEAUX[n]]["bonus"]) * etat(dest)

# Parcelle : reliée si c'est celle du village, ou si une route y mène.
func parcelle_reliee(cle: String, territoire) -> bool:
    if territoire == null or cle == territoire.cle(territoire.centre):
        return true
    return relie("parcelle_" + cle)
func acces_parcelle(cle: String, territoire) -> float:
    if territoire == null or cle == "" or cle == territoire.cle(territoire.centre):
        return 1.0
    return acces("parcelle_" + cle)

# Peut-on commencer une route vers cette parcelle ? Il faut une voisine déjà reliée.
func _parcelle_atteignable(cle: String, territoire) -> bool:
    var p: Vector2i = territoire.pos(cle)
    for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
        var q: String = territoire.cle(p + d)
        if territoire.possedees.has(q) and parcelle_reliee(q, territoire):
            return true
    return false

func km(dest: String) -> float:
    if dest.begins_with("parcelle_"):
        return 1.0
    return float(destinations().get(dest, 1.0))

func cout(dest: String, niv: String) -> Dictionary:
    var c := {}
    for r in DEF[niv]["cout_km"]:
        c[r] = float(DEF[niv]["cout_km"][r]) * km(dest)
    # Améliorer : on ne paie que la différence avec le niveau déjà construit.
    if troncons.has(dest):
        for r in troncons[dest].get("cout", {}):
            if c.has(r):
                c[r] = maxf(0.0, float(c[r]) - float(troncons[dest]["cout"][r]))
    return c

func texte_cout(c: Dictionary) -> String:
    var t: PackedStringArray = []
    for r in c:
        if float(c[r]) >= 1.0:
            t.append("%d %s" % [int(c[r]), r])
    return ", ".join(t) if t.size() > 0 else "du travail seulement"

func construire(dest: String, niv: String, res, territoire) -> String:
    if dest.begins_with("parcelle_"):
        var cle := dest.trim_prefix("parcelle_")
        if territoire == null or not territoire.possedees.has(cle):
            return "Cette parcelle n'est pas à nous."
        if not troncons.has(dest) and not _parcelle_atteignable(cle, territoire):
            return "Il faut d'abord relier une parcelle voisine : le réseau part du village."
    elif not destinations().has(dest):
        return "Cette île n'a pas de %s." % nom(dest)
    if troncons.has(dest) and float(troncons[dest]["travail_restant"]) > 0.0:
        return "Des travaux sont déjà en cours sur cette route."
    if troncons.has(dest) and NIVEAUX.find(niv) <= NIVEAUX.find(troncons[dest]["niveau"]):
        return "Cette route est déjà à ce niveau ou mieux."
    var c := cout(dest, niv)
    for r in c:
        if res.quantite(r) < float(c[r]):
            return "Il faut %s." % texte_cout(c)
    for r in c:
        res.retirer(r, float(c[r]), "construction")
    var total := {}
    for r in DEF[niv]["cout_km"]:
        total[r] = float(DEF[niv]["cout_km"][r]) * km(dest)
    var deja := 0.0
    if troncons.has(dest):
        deja = float(DEF[troncons[dest]["niveau"]]["travail_km"]) * km(dest)
    troncons[dest] = {"niveau": niv, "km": km(dest), "cout": total,
        "travail_restant": maxf(1.0, float(DEF[niv]["travail_km"]) * km(dest) - deja)}
    evenement.emit("Travaux : %s vers %s (%.1f km)." % [DEF[niv]["nom"], nom(dest), km(dest)])
    return ""

# Les bâtisseurs sans autre chantier tracent les routes, une à la fois.
func en_travaux() -> bool:
    for d in troncons:
        if float(troncons[d]["travail_restant"]) > 0.0:
            return true
    return false

func jour_passe(travail: float) -> void:
    for d in troncons:
        var t: Dictionary = troncons[d]
        if float(t["travail_restant"]) <= 0.0:
            continue
        t["travail_restant"] = maxf(0.0, float(t["travail_restant"]) - travail)
        if float(t["travail_restant"]) <= 0.0:
            evenement.emit("%s vers %s terminé." % [DEF[t["niveau"]]["nom"], nom(d)])
        return

# Usure chaque mois (plus forte en saison des pluies).
func mois_passe(res, mois: int) -> void:
    var pluie := mois >= 5 and mois <= 9
    for d in troncons:
        var t: Dictionary = troncons[d]
        if float(t["travail_restant"]) > 0.0:
            continue
        var avant := etat(d)
        t["etat"] = maxf(0.0, avant - float(USURE_MOIS[t["niveau"]]) * (1.5 if pluie else 1.0))
        if avant >= INUTILISABLE and float(t["etat"]) < INUTILISABLE:
            evenement.emit("La route vers %s est impraticable : il faut la réparer." % nom(d))
# Tronçon à réparer en priorité (eau, champs, forêt, carrière, mine, port, reste).
func a_reparer() -> String:
    for p in PRIORITE + [""]:
        for d in troncons:
            if float(troncons[d]["travail_restant"]) <= 0.0 and etat(d) < 0.8 and str(d).begins_with(p):
                return d
    return ""
# Réparation par les bâtisseurs libres : travail ET matériaux réels.
func reparer(travail: float, res) -> void:
    var d := a_reparer()
    if d == "" or travail <= 0.0:
        return
    var t: Dictionary = troncons[d]
    var plein: float = float(DEF[t["niveau"]]["travail_km"]) * float(t["km"]) * PART_REPARATION
    var gain := minf(1.0 - etat(d), travail / maxf(1.0, plein))
    for r in t.get("cout", {}):
        var besoin: float = float(t["cout"][r]) * PART_REPARATION * gain
        if besoin > 0.0:
            gain = minf(gain, res.quantite(r) / (float(t["cout"][r]) * PART_REPARATION))
    if gain <= 0.0:
        return
    for r in t.get("cout", {}):
        res.retirer(r, float(t["cout"][r]) * PART_REPARATION * gain, "entretien")
    var avant := etat(d)
    t["etat"] = avant + gain
    if avant < INUTILISABLE and float(t["etat"]) >= INUTILISABLE:
        evenement.emit("La route vers %s est de nouveau praticable." % nom(d))

# Ordinateur : sentiers vers l'eau, la forêt et les parcelles de ses champs.
func gerer_auto(res, territoire, agriculture) -> void:
    if en_travaux():
        return
    for dest in ["eau", "foret", "carriere"]:
        if not troncons.has(dest) and destinations().has(dest):
            construire(dest, "sentier", res, territoire)
            return
    for c in agriculture.champs:
        var cle := str(c.get("parcelle", ""))
        if cle != "" and not parcelle_reliee(cle, territoire) and not troncons.has("parcelle_" + cle):
            if construire("parcelle_" + cle, "sentier", res, territoire) == "":
                return

# Tracés déjà faits (clan ancien, ancienne sauvegarde) : sentiers terminés.
func sentiers_existants(dests: Array) -> void:
    for d in dests:
        if not troncons.has(d):
            troncons[d] = {"niveau": "sentier", "km": km(d), "cout": {}, "travail_restant": 0.0}

func vers_dict() -> Dictionary:
    return {"troncons": troncons}

func depuis_dict(d: Dictionary) -> void:
    troncons = d.get("troncons", {})
