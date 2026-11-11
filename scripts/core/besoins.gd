extends RefCounted

# Diagnostic des besoins du clan.
# Chaque mois : calcule consommation, production prévue et réserves,
# puis liste les problèmes avec leurs solutions possibles :
#   deficit  : la production prévue ne couvre pas la consommation
#   marge    : elle la couvre, mais sans la marge de sécurité
#   stockage : la réserve maximale tient moins que l'autonomie visée
#              (90 jours de nourriture, 30 jours d'eau et de bois)
#   surplus  : un poste peut être libéré sans danger
#   logement : moins de places libres que de couples qui peuvent avoir un enfant
# Ce module ne change rien tout seul en mode "conseil".
# Toute action passe par appliquer(), qui vérifie les règles du jeu
# (même chemin pour le joueur, le chef et les tests).
# Mode "auto" : temporaire, applique la première solution, en attendant
# l'écran du chef (v0.3.3).

signal evenement(texte)

const ORDRE := ["eau", "nourriture", "bois"]
const MARGES := [0.15, 0.25, 0.40, 0.60]
const ACTIONS_MAX := [1, 1, 2, 3]
const MOIS_VERROU := 6
const MARGE_FERMETURE := 0.35
const AUTONOMIE_VISEE := {"nourriture": 90.0, "eau": 30.0, "bois": 30.0}

var mode := "auto"
var verrou := {}
var problemes: Array = []
var dernier_avis := {}

var _pop
var _res
var _cons
var _jour := 0
var _s := 0
# Stabilité (v0.3.33) : pas de changement de métier ordinaire moins de 60 jours
# après le précédent ; exception : urgence vitale (danger à moins de 20 jours).
const DELAI_CHANGEMENT := 60
const URGENCE_JOURS := 20.0
var dernier_changement := -9999
var _chantier := false

func verrouiller(m: String, jour: int) -> void:
    verrou[m] = jour + MOIS_VERROU * 30

func mois_passe(population, ressources, construction, jour: int, pluie: bool, chantier_actif: bool) -> void:
    _contexte(population, ressources, construction, jour, pluie, chantier_actif)
    if mode == "auto":
        _ajuster_postes()
        var calme := jour - dernier_changement < DELAI_CHANGEMENT and not _urgence_plan()
        if not calme:
            var avant: Dictionary = population.postes.duplicate()
            _planifier()
            _res.prod_metier = {}
            _jour_plan = jour
            if population.postes != avant:
                dernier_changement = jour
    problemes = diagnostiquer()
    for p in problemes:
        if p["type"] == "stockage":
            _avis(p["ressource"], "Réserve de %s trop petite pour %d jours : construisez du stockage." % [p["ressource"], int(AUTONOMIE_VISEE[p["ressource"]])])
        elif p["type"] == "logement":
            _avis("logement", "Logement : %d place(s) libre(s) pour %d couple(s) qui peuvent avoir un enfant. Construisez des huttes." % [maxi(0, p["places"]), int(p["besoin"])])
        elif p["type"] == "deficit" and p["solutions"].is_empty():
            _avis(p["ressource"] + "_bras", "Pas assez de bras pour produire assez de %s." % p["ressource"])

# Diagnostic seul, sans action ni message : utilisé par le chef entre deux mois.
func actualiser(population, ressources, construction, jour: int, pluie: bool, chantier_actif: bool) -> void:
    _contexte(population, ressources, construction, jour, pluie, chantier_actif)
    problemes = diagnostiquer()

func _contexte(population, ressources, construction, jour: int, pluie: bool, chantier_actif: bool) -> void:
    _pop = population
    _cache = {}
    _res = ressources
    _cons = construction
    _jour = jour
    _s = 1 if pluie else 0
    _chantier = chantier_actif

func diagnostiquer() -> Array:
    var liste := []
    for r in ORDRE:
        var p := _diagnostic(r)
        if not p.is_empty():
            liste.append(p)
    var l := _diagnostic_logement()
    if not l.is_empty():
        liste.append(l)
    return liste

# ---------- Diagnostic du logement ----------

func _diagnostic_logement() -> Dictionary:
    var capacite := int(_cons.effet_total("logement"))
    var occupes: int = _pop.habitants.size() + _pop.grossesses()
    var places := capacite - occupes
    var feconds := 0
    for c in _pop.couples:
        if int(c["fin"]) >= 0 or c["sterile"]:
            continue
        var mere: Dictionary = _pop.par_id(int(c["femme"]))
        if not mere.is_empty() and _pop.age(mere, _jour) <= 44:
            feconds += 1
    if places >= feconds:
        return {}
    var p := {
        "ressource": "logement",
        "type": "logement",
        "niveau": 2 if places <= 0 else 1,
        "capacite": capacite,
        "occupes": occupes,
        "places": places,
        "deficit": feconds - places,
        "conso": 0.0,
        "production": 0.0,
        "besoin": float(feconds),
        "stock": float(places),
        "jours_reserve": -1.0,
        "jours_rupture": -1.0,
        "solutions": [],
    }
    var b := _batiment_pour("logement")
    if b != "":
        p["solutions"] = [{"action": "construire", "ressource": "logement", "batiment": b}]
    return p

# ---------- Diagnostic d'une ressource ----------

func _diagnostic(r: String) -> Dictionary:
    var conso := _conso(r)
    if conso <= 0.0:
        return {}
    var stock: float = _res.stocks[r]
    var capacite: float = _res.capacite(r)
    var plein: bool = stock >= capacite * 0.9
    var jours := stock / conso
    var niveau := 0
    if not plein:
        if jours < 7.0:
            niveau = 3
        elif jours < 15.0:
            niveau = 2
        elif jours < 30.0:
            niveau = 1
    var besoin: float = conso * (1.0 + float(MARGES[niveau]))
    var prod := _production(r)
    var p := {
        "ressource": r,
        "type": "",
        "niveau": niveau,
        "conso": conso,
        "production": prod,
        "besoin": besoin,
        "stock": stock,
        "jours_reserve": jours,
        "jours_rupture": stock / (conso - prod) if prod < conso else -1.0,
        "solutions": [],
    }
    if prod < besoin:
        p["type"] = "deficit" if prod < conso else "marge"
        p["solutions"] = _solutions_deficit(r, niveau)
        return p
    if plein and capacite / conso < float(AUTONOMIE_VISEE.get(r, 30.0)):
        p["type"] = "stockage"
        var b := _batiment_pour("stock_" + r)
        if b != "":
            p["solutions"] = [{"action": "construire", "ressource": r, "batiment": b}]
        return p
    if niveau == 0:
        var m := _metier_en_trop(r, besoin)
        if m != "":
            p["type"] = "surplus"
            p["solutions"] = [{"action": "fermer", "ressource": r, "metier": m}]
            return p
    return {}

func _solutions_deficit(r: String, niveau: int) -> Array:
    var sols := []
    var m := _meilleur_metier(r, niveau)
    if m == "":
        return sols
    if _libres() > 0:
        sols.append({"action": "ouvrir", "ressource": r, "metier": m})
    if niveau >= 1:
        for m2 in _pop.postes:
            if m2 == m or int(_pop.postes[m2]) <= 0:
                continue
            if niveau < 3 and _verrouille(m2):
                continue
            if _peut_ceder(m2, niveau if r == ORDRE[0] else 0):
                sols.append({"action": "transferer", "ressource": r, "de": m2, "vers": m})
                break
    return sols

func _premiere_action(p: Dictionary) -> Dictionary:
    for sol in p["solutions"]:
        if sol["action"] != "construire":
            if sol.has("metier") and _verrouille(sol["metier"]) and p["niveau"] < 3:
                continue
            return sol
    return {}

# ---------- Application avec vérification ----------

# Renvoie "" si l'action est faite, sinon la raison du refus.
func appliquer(sol: Dictionary) -> String:
    var r: String = sol["ressource"]
    var p := _diagnostic(r)
    match sol["action"]:
        "ouvrir":
            if p.is_empty() or not p["type"] in ["deficit", "marge"]:
                return "Ce poste n'est plus nécessaire."
            if _libres() <= 0:
                return "Aucun adulte disponible."
            _pop.postes[sol["metier"]] = int(_pop.postes[sol["metier"]]) + 1
            evenement.emit("Poste de %s ouvert." % sol["metier"])
        "transferer":
            if p.is_empty() or not p["type"] in ["deficit", "marge"]:
                return "Ce changement n'est plus nécessaire."
            if int(_pop.postes.get(sol["de"], 0)) <= 0:
                return "Aucun %s à déplacer." % sol["de"]
            if not _peut_ceder(sol["de"], int(p["niveau"]) if r == ORDRE[0] else 0):
                return "Retirer un %s mettrait une autre ressource en danger." % sol["de"]
            _pop.postes[sol["de"]] = int(_pop.postes[sol["de"]]) - 1
            _pop.postes[sol["vers"]] = int(_pop.postes[sol["vers"]]) + 1
            evenement.emit("Un %s devient %s." % [sol["de"], sol["vers"]])
        "fermer":
            if p.is_empty() or p["type"] != "surplus" or _metier_en_trop(r, p["besoin"]) != sol["metier"]:
                return "Ce poste est encore utile."
            _pop.postes[sol["metier"]] = int(_pop.postes[sol["metier"]]) - 1
            evenement.emit("Poste de %s fermé (surplus)." % sol["metier"])
        "construire":
            if not _cons.lancer(sol["batiment"], -1, _res):
                return "Pas assez de matériaux pour construire."
            evenement.emit("Chantier lancé : %s." % sol["batiment"])
        _:
            return "Action inconnue."
    return ""

# ---------- Estimation (pour les propositions du chef) ----------

# Coût, effet et risque d'une solution. Ne change rien au jeu.
# Renvoie : cout (texte), effet (texte), risque (texte), faisable, raison.
const DE := {"eau": "d'eau", "nourriture": "de nourriture", "bois": "de bois"}

func _de(r: String) -> String:
    return DE.get(r, "de " + r)

func estimer(sol: Dictionary) -> Dictionary:
    var r: String = sol["ressource"]
    var u: String = _res.UNITES.get(r, "")
    var e := {"cout": "", "effet": "", "risque": "", "faisable": true, "raison": ""}
    match sol["action"]:
        "ouvrir":
            var gain := _rendement(sol["metier"], r)
            var perte := _rendement("sans métier", "nourriture")
            e["cout"] = "1 adulte sans métier"
            e["effet"] = "+%.0f %s %s par jour" % [gain, u, _de(r)]
            e["risque"] = "Le nouveau %s débute : rendement plus faible s'il n'a pas été initié. Petite cueillette perdue : -%.1f kg de nourriture par jour." % [sol["metier"], perte]
            if _libres() <= 0:
                e["faisable"] = false
                e["raison"] = "Aucun adulte disponible."
        "transferer":
            var gain := _rendement(sol["vers"], r)
            var pertes: PackedStringArray = []
            for r2 in ORDRE:
                var p := _rendement(sol["de"], r2)
                if p > 0.0:
                    pertes.append("-%.0f %s %s" % [p, _res.UNITES.get(r2, ""), _de(r2)])
            e["cout"] = "1 %s change de métier" % sol["de"]
            e["effet"] = "+%.0f %s %s par jour" % [gain, u, _de(r)]
            e["risque"] = "Par jour : %s. Compétence réduite de moitié dans son nouveau métier." % ", ".join(pertes)
            if not _peut_ceder(sol["de"], int(_diagnostic(r).get("niveau", 0)) if r == ORDRE[0] else 0):
                e["faisable"] = false
                e["raison"] = "Retirer un %s mettrait une autre ressource en danger." % sol["de"]
        "fermer":
            var perte := _rendement(sol["metier"], r)
            e["cout"] = "aucun"
            e["effet"] = "1 travailleur libéré"
            e["risque"] = "-%.0f %s %s par jour ; à surveiller quand la saison change." % [perte, u, _de(r)]
        "construire":
            var niv: Dictionary = _cons.definitions[sol["batiment"]]["niveaux"][0]
            var cout: Dictionary = niv["cout"]
            var morceaux: PackedStringArray = []
            for r2 in cout:
                morceaux.append("%d %s %s" % [int(cout[r2]), _res.UNITES.get(r2, ""), _de(r2)])
            var force := _travail_batisseurs()
            var jours := ceili(float(niv["travail"]) / force) if force > 0.0 else -1
            e["cout"] = ", ".join(morceaux)
            if r == "logement":
                e["effet"] = "%s : +%d places de logement" % [niv["nom"], int(niv["effet"].get("logement", 0))]
            else:
                e["effet"] = "%s : +%d %s de réserve %s" % [niv["nom"], int(niv["effet"].get("stock_" + r, 0)), u, _de(r)]
            if jours > 0:
                e["risque"] = "Bois payé tout de suite. Bâtisseurs occupés environ %d jours, sans couper de bois." % jours
            else:
                e["risque"] = "Aucun bâtisseur : le chantier n'avancera pas."
            if not _cons.peut_payer(cout, _res):
                e["faisable"] = false
                e["raison"] = "Pas assez de matériaux (%s)." % ", ".join(morceaux)
    return e

func _travail_batisseurs() -> float:
    var t := 0.0
    for h in _pop.habitants:
        if h["metier"] == "bâtisseur":
            t += 0.6 + float(h["competence"]) / 100.0 * 0.8
    return t

# ---------- Calculs ----------

func _metier_en_trop(r: String, besoin: float) -> String:
    for m in _metiers(r):
        if int(_pop.postes.get(m, 0)) <= 1 or _verrouille(m):
            continue
        if _production(r) - _rendement(m, r) >= besoin * (1.0 + MARGE_FERMETURE) and _peut_ceder(m):
            return m
    return ""

# Peut-on retirer un travailleur de m2 ? Oui si chaque ressource qu'il produit
# garde sa marge de sécurité, ou garde au moins sa propre réserve visée
# (90 jours de nourriture, 30 d'eau, 30 de bois) : on puise dans une réserve
# qui suffit, on ne sacrifie aucune ressource.

# En urgence d'eau (niveau 3), l'eau passe avant tout : on accepte de puiser
# dans une autre réserve tant qu'elle garde au moins 15 jours.
# Plus de postes que d'adultes (enfants morts, adultes devenus anciens) :
# on ferme le poste dont la ressource a la plus grande réserve.
# Trop de postes pour les adultes présents (expédition, décès...) : on ferme
# le poste dont la perte met le moins le clan en danger (v0.3.28).
# Pour chaque poste, on calcule combien de jours chaque besoin vital tiendrait
# SANS lui (production restante contre consommation, avec la réserve).
# Les postes qui ne produisent rien de vital partent en premier.
func _ajuster_postes() -> void:
    while _adultes() - _occupes() < 0:
        var choix := ""
        var max_jours := -1.0
        for m in _pop.postes:
            if int(_pop.postes[m]) <= 0:
                continue
            var jours := _score({m: -1}, false)
            if jours > max_jours:
                max_jours = jours
                choix = m
        if choix == "":
            return
        _pop.postes[choix] = int(_pop.postes[choix]) - 1
# Jours avant le danger pour un besoin vital, si on change les postes de "delta"
# ({métier: +1 ou -1}). Réserve / déficit, plus le temps qu'on survit sans
# (la soif tue plus vite que la faim). 99999 = la production suffit.
const SURVIE := {"eau": 25.0, "nourriture": 50.0, "bois": 60.0}
# Prévision (v0.3.33) : on prend la pire des deux saisons, celle d'aujourd'hui
# et celle dans 45 jours (saison sèche / saison des pluies).
func _jours(r: String, delta: Dictionary) -> float:
    var s_maintenant := _s
    var mois := ((_jour + 45) / 30) % 12
    var s_futur := 1 if mois >= 5 and mois <= 9 else 0
    var net := 1.0e9
    for s in [s_maintenant, s_futur]:
        _s = s
        var prod := _production(r)
        for m in delta:
            prod += float(delta[m]) * _rendement(m, r)
        net = minf(net, prod - _conso(r))
    _s = s_maintenant
    if net >= 0.0:
        return 99999.0
    return float(_res.stocks[r]) / -net + float(SURVIE[r])
# Urgence vitale : une réserve (eau, nourriture, bois) vide dans moins de 20 jours.
func _urgence() -> bool:
    for r in ORDRE:
        if _jours(r, {}) - float(SURVIE[r]) < URGENCE_JOURS:
            return true
    return false
# Le besoin le plus menacé décide.
func _pire(delta: Dictionary) -> float:
    var j := 99999.0
    for r in ORDRE:
        j = minf(j, _jours(r, delta))
    return j
# Règle générale du chef automatique (v0.3.28) : chaque mois, il déplace un
# travailleur si cela éloigne le danger le plus proche (eau, nourriture, bois).
# Il ne retire jamais quelqu'un d'un poste vital si cela rapproche un autre danger.
func _equilibrer() -> void:
    for i in 3:
        var base := _pire({})
        if base >= 120.0:
            return
        var meilleur := {}
        var gain := base
        for de in _pop.postes:
            if int(_pop.postes[de]) <= 0 or (_verrouille(de) and base > 40.0):
                continue
            for vers in _pop.postes:
                if vers == de or not _res.PRODUCTION.has(vers):
                    continue
                var d := {de: -1, vers: 1}
                var v := _pire(d)
                if v > gain + 1.0:
                    gain = v
                    meilleur = d
        if meilleur.is_empty():
            return
        var de2: String = ""
        var vers2: String = ""
        for m in meilleur:
            _pop.postes[m] = int(_pop.postes[m]) + int(meilleur[m])
            if int(meilleur[m]) < 0:
                de2 = m
            else:
                vers2 = m
        evenement.emit("Le conseiller réorganise : un %s devient %s." % [de2, vers2])

func _occupes() -> int:
    var n := 0
    for m in _pop.postes:
        n += int(_pop.postes[m])
    return n

func _peut_ceder(m2: String, urgence := 0) -> bool:
    for r2 in ORDRE:
        var rend := _rendement(m2, r2)
        if rend <= 0.0:
            continue
        var c := _conso(r2)
        if _production(r2) - rend < c * (1.0 + MARGES[0]):
            # En grande urgence (l'eau va manquer), on accepte une réserve courte ailleurs.
            var visee := 7.0 if urgence >= 3 else float(AUTONOMIE_VISEE.get(r2, 30.0))
            if c <= 0.0 or float(_res.stocks[r2]) / c < visee:
                return false
    return true

func _meilleur_metier(r: String, niveau: int) -> String:
    var meilleur := ""
    var max_rend := 0.0
    for m in _metiers(r):
        if not _pop.postes.has(m):
            continue
        if niveau < 3 and _verrouille(m):
            continue
        var rend := _rendement(m, r)
        if rend > max_rend:
            max_rend = rend
            meilleur = m
    return meilleur

# Le bâtiment fait pour cet effet (son premier effet), sinon un autre qui l'a.
# Ex. : pour l'eau, des jarres plutôt qu'une hutte.
func _batiment_pour(effet_cherche: String) -> String:
    var secours := ""
    for type in _cons.definitions:
        var effet: Dictionary = _cons.definitions[type]["niveaux"][0].get("effet", {})
        if not effet.has(effet_cherche):
            continue
        if effet.keys()[0] == effet_cherche:
            return type
        if secours == "":
            secours = type
    return secours

func _metiers(r: String) -> Array:
    var liste := []
    for m in _res.PRODUCTION:
        if _res.PRODUCTION[m].has(r) and not m in ["chef", "sans métier", "aide"]:
            liste.append(m)
    return liste

func _verrouille(m: String) -> bool:
    return _jour < int(verrou.get(m, -1))

func _efficacite(m: String) -> float:
    var total := 0.0
    var n := 0
    for h in _pop.habitants:
        if h["metier"] == m:
            total += 0.6 + float(h["competence"]) / 100.0 * 0.8
            n += 1
    return total / n if n > 0 else 0.7

func _rendement(m: String, r: String) -> float:
    var p: Dictionary = _res.PRODUCTION.get(m, {})
    if not p.has(r):
        return 0.0
    if m == "bâtisseur" and _chantier:
        return 0.0
    return float(p[r][_s]) * _efficacite(m) * _res.outils * _res._richesse(m, r)

func _adultes() -> int:
    var n := 0
    for h in _pop.habitants:
        # Un adulte parti en expédition ne travaille pas au village.
        if _pop.age(h, _jour) >= _pop.AGE_ADULTE and h["metier"] != "chef" and h["metier"] != "ancien" and not h.has("expedition"):
            n += 1
    return n

func _aides() -> int:
    var n := 0
    for h in _pop.habitants:
        if h["metier"] == "enfant" and _pop.age(h, _jour) >= _res.AGE_AIDE:
            n += 1
    return n

func _libres() -> int:
    var occupes := 0
    for m in _pop.postes:
        occupes += int(_pop.postes[m])
    return maxi(0, _adultes() - occupes)

func _conso(r: String) -> float:
    var c := 0.0
    for h in _pop.habitants:
        var table: Dictionary = _res.CONSO_ENFANT if _pop.age(h, _jour) < _pop.AGE_ADULTE else _res.CONSO_ADULTE
        c += float(table.get(r, 0.0))
    if r == "nourriture":
        c += float(_res.stocks[r]) * _res.taux_pertes()
    return c

func _production(r: String) -> float:
    var total := 0.0
    for m in _pop.postes:
        total += int(_pop.postes[m]) * _rendement(m, r)
    for h in _pop.habitants:
        if h["metier"] == "chef":
            total += _rendement("chef", r)
    total += _libres() * _rendement("sans métier", r)
    total += _aides() * float(_res.PRODUCTION["aide"].get(r, [0.0, 0.0])[_s]) * 0.7 * _res.outils
    if r == "eau" and _s == 1:
        total += 20.0
    return total

func _avis(cle: String, texte: String) -> void:
    if _jour - int(dernier_avis.get(cle, -9999)) < 360:
        return
    dernier_avis[cle] = _jour
    evenement.emit(texte)

# ---------- Planificateur unique (v0.3.34) ----------
# Un seul mécanisme décide des postes : il SIMULE les 60 prochains jours, jour par
# jour, pour chaque répartition envisagée (saison de chaque jour, pluie, eau qui
# s'évapore, viande et poisson qui se gâtent, bois brûlé, capacités de stockage),
# puis garde celle qui éloigne le plus le danger.
# Ordre des priorités (score) : 1) ni soif ni faim ni manque de bois pendant
# 60 jours ; 2) réserves en fin de période (nourriture d'abord) ; 3) un
# bâtisseur quand il y a des chantiers. Un changement doit gagner nettement.
const HORIZON := 60
const METIERS_VITAUX := ["porteur d'eau", "cueilleur", "chasseur", "pêcheur", "bâtisseur", "cultivateur"]
const GAIN_MIN := 40.0
var elevage = null                # v0.3.36 : les bêtes boivent, mangent, donnent lait et œufs
var paturage_ha := 0.0
var _cache := {}                  # rendements et consommation du mois
var _survie := 0.0                # jours sans pénurie de la dernière simulation
var _jour_plan := -1               # début de la période observée (prod_metier)
func _rend(m: String, r: String, s: int) -> float:
    var k := "%s|%s|%d" % [m, r, s]
    if not _cache.has(k):
        _cache[k] = _rend_calcul(m, r, s)
    return _cache[k]
func _rend_calcul(m: String, r: String, s: int) -> float:
    var p: Dictionary = _res.PRODUCTION.get(m, {})
    if not p.has(r):
        return 0.0
    return float(p[r][s]) * _efficacite(m) * _res.outils * _res._richesse(m, r) * _res._acces(m, r)
func _perte_frais() -> float:
    var p := 0.0
    for id in ["gibier", "poisson"]:
        p = maxf(p, float(_res.produits.get(id, {}).get("perte_jour", 0.2)))
    return p
# Score d'une répartition (postes actuels + delta). Plus c'est grand, mieux c'est.
func _score(delta: Dictionary, strict := true) -> float:
    var postes := {}
    var total := 0
    for m in _pop.postes:
        postes[m] = int(_pop.postes[m]) + int(delta.get(m, 0))
        if postes[m] < 0:
            return -1.0e9
        total += postes[m]
    for m in delta:
        if not postes.has(m):
            postes[m] = int(delta[m])
            total += int(delta[m])
    if not _cache.has("conso"):
        var cs := {"eau": _conso("eau"), "bois": _conso("bois"), "nourriture": 0.0, "adultes": _adultes(), "aides": _aides()}
        for h in _pop.habitants:
            var t: Dictionary = _res.CONSO_ENFANT if _pop.age(h, _jour) < _pop.AGE_ADULTE else _res.CONSO_ADULTE
            cs["nourriture"] += float(t["nourriture"])
        _cache["conso"] = cs
    var conso: Dictionary = _cache["conso"]
    if not _cache.has("calib"):
        _cache["calib"] = _calibrer()
    var k: Dictionary = _cache["calib"]
    var frais_ids: Array = _res._frais()
    var frais := 0.0
    for id in frais_ids:
        frais += float(_res.aliments[id]) * _res.facteur(id)
    var sec: float = _res.total_aliments() - frais
    var eau: float = float(_res.stocks["eau"])
    var bois: float = float(_res.stocks["bois"])
    var cap_eau: float = _res.capacite("eau")
    var cap_bois: float = _res.capacite("bois")
    var cap_n: float = _res.capacite("nourriture")
    var perte := _perte_frais()
    var tenue := {"eau": HORIZON + 1, "nourriture": HORIZON + 1, "bois": HORIZON + 1}
    var manque := {"eau": 0.0, "nourriture": 0.0, "bois": 0.0}   # jours de besoin non couverts
    var aides: int = int(conso["aides"])
    # Chantier en cours : les bâtisseurs y travaillent (pas de bois) jusqu'à la fin.
    var reste_chantier := 0.0
    for ch in _cons.chantiers:
        reste_chantier += float(ch["reste"])
    var force_bat: float = int(postes.get("bâtisseur", 0)) * _efficacite("bâtisseur")
    var libres: int = int(conso["adultes"]) - total
    if libres < 0:
        if strict:
            return -1.0e9
        libres = 0          # postes en trop (absents) : on compare seulement
    var chef := 0
    for h in _pop.habitants:
        if h["metier"] == "chef":
            chef += 1
    for j in HORIZON:
        var mois := ((_jour + j) / 30) % 12
        var s := 1 if mois >= 5 and mois <= 9 else 0
        var p_eau := 20.0 * s + aides * float(_res.PRODUCTION["aide"]["eau"][s]) * 0.7
        var p_sec := libres * _rend("sans métier", "nourriture", s) + aides * float(_res.PRODUCTION["aide"]["nourriture"][s]) * 0.7
        var p_frais := 0.0
        var p_bois := 0.0
        for m in postes:
            var n := int(postes[m])
            if n <= 0:
                continue
            p_eau += n * _rend(m, "eau", s)
            if not (m == "bâtisseur" and reste_chantier > 0.0):
                p_bois += n * _rend(m, "bois", s)
            var km: float = float(k["metier"].get(m, 1.0))
            if m in ["chasseur", "pêcheur"]:
                p_frais += n * _rend(m, "nourriture", s) * km
            else:
                p_sec += n * _rend(m, "nourriture", s) * km
        p_sec += chef * _rend("chef", "nourriture", s)
        if elevage != null and not elevage.animaux.is_empty():
            var ck := "elev|%d" % s
            if not _cache.has(ck):
                _cache[ck] = elevage.prevision(_jour, s == 1, paturage_ha)
            var ev: Dictionary = _cache[ck]
            p_eau -= float(ev["eau"])
            p_sec -= float(ev["grain"])
            p_frais += float(ev["frais"])
        p_eau *= float(k["eau"])
        p_bois *= float(k["bois"])
        reste_chantier = maxf(0.0, reste_chantier - force_bat)
        eau = minf(cap_eau, eau * (1.0 - _res.EVAPORATION_EAU) + p_eau - conso["eau"])
        bois = minf(cap_bois, bois + p_bois - conso["bois"])
        frais = (frais + p_frais) * (1.0 - perte)
        sec -= float(k["perte_sec"])
        var faim: float = conso["nourriture"]
        var pris := minf(frais, faim)
        frais -= pris
        faim -= pris
        # Sécheurs : le frais restant devient du sec (calories -5 %), bois et sel consommés.
        if int(postes.get("sécheur", 0)) > 0 and frais > 0.0 and float(_res.stocks["sel"]) > 1.0:
            var conv := minf(frais, int(postes["sécheur"]) * _res.SECHAGE_KG_JOUR * 0.8 * _res.facteur("gibier"))
            frais -= conv
            sec += conv * (1.0 - _res.PERTE_SECHAGE)
            bois -= conv / _res.facteur("gibier") * _res.SECHAGE_BOIS
        sec = minf(cap_n, sec + p_sec) - faim
        manque["eau"] += maxf(0.0, -eau) / maxf(0.1, conso["eau"])
        manque["bois"] += maxf(0.0, -bois) / maxf(0.1, conso["bois"])
        manque["nourriture"] += maxf(0.0, -sec) / maxf(0.1, conso["nourriture"])
        if eau < 0.0 and tenue["eau"] > HORIZON:
            tenue["eau"] = j
        if bois < 0.0 and tenue["bois"] > HORIZON:
            tenue["bois"] = j
        if sec < 0.0 and tenue["nourriture"] > HORIZON:
            tenue["nourriture"] = j
        eau = maxf(eau, 0.0)
        bois = maxf(bois, 0.0)
        sec = maxf(sec, 0.0)
    # Le manque de bois ne tue pas (il gêne) : la survie se juge sur l'eau et la nourriture.
    var survie := minf(tenue["eau"], tenue["nourriture"])
    _survie = survie
    # Le pire besoin d'abord, puis chaque besoin compte (l'eau avant la
    # nourriture, avant le bois) : sinon, un besoin déjà perdu masque les autres.
    var score: float = survie * 1000.0 + tenue["eau"] * 300.0 + tenue["nourriture"] * 200.0 + tenue["bois"] * 30.0
    score -= manque["eau"] * 300.0 + manque["nourriture"] * 200.0 + manque["bois"] * 30.0
    # Réserves en fin de période : la nourriture compte beaucoup (ne pas manger
    # la réserve pour autre chose), l'eau ensuite.
    score += minf(90.0, (sec + frais) / maxf(0.1, conso["nourriture"])) * 40.0
    score += minf(30.0, eau / maxf(0.1, conso["eau"])) * 10.0
    score += minf(30.0, bois / maxf(0.1, conso["bois"])) * 2.0
    # Éleveurs : sans eux, les bêtes meurent deux fois plus (bonus jusqu'au besoin).
    if elevage != null and not elevage.animaux.is_empty():
        var besoin_el := 0.0
        for a in elevage.animaux:
            besoin_el += 1.0 / float(elevage.especes[a["esp"]]["eleveur_pour"])
        score += minf(float(postes.get("éleveur", 0)), ceilf(besoin_el)) * 150.0
    if _chantier and int(postes.get("bâtisseur", 0)) >= 1:
        score += 30.0
    return score
# Calibrage sur le mois écoulé (registre des flux) : ce que le clan a VRAIMENT
# produit, comparé à ce que le modèle prévoyait pour les postes actuels
# (fruits qui pourrissent, gibier, efficacité réelle...). Borné de 0,5 à 1,2.
# Les pertes de nourriture du mois (hors viande et poisson) sont reprises aussi.
func _calibrer() -> Dictionary:
    var k := {"eau": 1.0, "bois": 1.0, "nourriture": 1.0, "perte_sec": 0.0, "metier": {}}
    # Nourriture : calibrage par métier (ce que chaque métier a vraiment rapporté).
    var jm := float(_jour - _jour_plan) if _jour_plan >= 0 and _jour > _jour_plan else 0.0
    if jm >= 10.0:
        for m in _res.prod_metier:
            var n := 0
            for h in _pop.habitants:
                if h["metier"] == m and not h.has("expedition"):
                    n += 1
            var prevu_m := 0.0
            for d in int(jm):
                var mo := ((_jour - int(jm) + d) / 30) % 12
                prevu_m += n * _rend(m, "nourriture", 1 if mo >= 5 and mo <= 9 else 0)
            if prevu_m > 1.0:
                k["metier"][m] = clampf(float(_res.prod_metier[m]) / prevu_m, 0.3, 1.2)
    var prod: Dictionary = _res.flux.get("production", {})
    var jours := float(_jour % 30) if _jour % 30 != 0 else 30.0
    for r in ["eau", "bois", "nourriture"]:
        var prevu := 0.0
        for m in _pop.postes:
            prevu += int(_pop.postes[m]) * _rend(m, r, _s)
        if r == "eau":
            prevu += 20.0 * _s
        var vu := float(prod.get(r, 0.0)) / jours
        if prevu > 0.5 and vu > 0.0:
            k[r] = clampf(vu / prevu, 0.5, 1.2)
    k["perte_sec"] = maxf(0.0, -float(_res.flux.get("perte", {}).get("nourriture", 0.0)) / jours * 0.5)
    return k
# Urgence : la simulation actuelle voit une pénurie dans moins de 20 jours.
func _urgence_plan() -> bool:
    _score({})
    return _survie < URGENCE_JOURS
# Jusqu'à 3 changements par décision : ouvrir un poste (adulte libre) ou
# déplacer un travailleur, seulement si le score gagne nettement.
func _planifier() -> void:
    var metiers: Array = []
    for m in _pop.postes:
        metiers.append(m)
    for m in METIERS_VITAUX:
        if not metiers.has(m) and _pop.postes.has(m):
            metiers.append(m)
    if elevage != null and not elevage.animaux.is_empty() and not metiers.has("éleveur"):
        metiers.append("éleveur")
    if not metiers.has("sécheur") and (int(_pop.postes.get("chasseur", 0)) + int(_pop.postes.get("pêcheur", 0))) > 0:
        metiers.append("sécheur")
    for i in 3:
        var base := _score({})
        var meilleur := {}
        var gain := base + GAIN_MIN
        for vers in metiers:
            if (not _res.PRODUCTION.has(vers) and not vers in ["sécheur", "éleveur"]) or (_verrouille(vers) and base > 40000.0):
                continue
            var d := {vers: 1}
            var v := _score(d)
            if v > gain:
                gain = v
                meilleur = d
            for de in metiers:
                if de == vers or int(_pop.postes.get(de, 0)) <= 0 or (_verrouille(de) and base > 40000.0):
                    continue
                d = {de: -1, vers: 1}
                v = _score(d)
                if v > gain:
                    gain = v
                    meilleur = d
        if meilleur.is_empty():
            return
        var de2 := ""
        var vers2 := ""
        for m in meilleur:
            _pop.postes[m] = int(_pop.postes.get(m, 0)) + int(meilleur[m])
            if int(meilleur[m]) < 0:
                de2 = m
            else:
                vers2 = m
        if de2 == "":
            evenement.emit("Le conseiller ouvre un poste de %s." % vers2)
        else:
            evenement.emit("Le conseiller réorganise : un %s devient %s." % [de2, vers2])
func vers_dict() -> Dictionary:
    return {"mode": mode, "verrou": verrou, "dernier_changement": dernier_changement}

func depuis_dict(d: Dictionary) -> void:
    dernier_changement = int(d.get("dernier_changement", -9999))
    mode = str(d.get("mode", "auto"))
    verrou = {}
    for m in d.get("verrou", {}):
        verrou[m] = int(d["verrou"][m])
