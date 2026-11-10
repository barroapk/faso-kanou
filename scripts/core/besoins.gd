extends RefCounted

# Diagnostic des besoins du clan.
# Chaque mois : calcule consommation, production prévue et réserves,
# puis liste les problèmes avec leurs solutions possibles :
#   deficit  : la production prévue ne couvre pas la consommation
#   marge    : elle la couvre, mais sans la marge de sécurité
#   stockage : la réserve maximale tient moins de 30 jours
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

var mode := "auto"
var verrou := {}
var problemes: Array = []
var dernier_avis := {}

var _pop
var _res
var _cons
var _jour := 0
var _s := 0
var _chantier := false

func verrouiller(m: String, jour: int) -> void:
    verrou[m] = jour + MOIS_VERROU * 30

func mois_passe(population, ressources, construction, jour: int, pluie: bool, chantier_actif: bool) -> void:
    _contexte(population, ressources, construction, jour, pluie, chantier_actif)
    if mode == "auto":
        for r in ORDRE:
            for i in 3:
                var p := _diagnostic(r)
                if p.is_empty() or i >= ACTIONS_MAX[p["niveau"]]:
                    break
                var sol := _premiere_action(p)
                if sol.is_empty():
                    break
                if appliquer(sol) != "":
                    break
    problemes = diagnostiquer()
    for p in problemes:
        if p["type"] == "stockage":
            _avis(p["ressource"], "Réserve de %s trop petite pour 30 jours : construisez du stockage." % p["ressource"])
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
    if plein and capacite / conso < 30.0:
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
    if niveau >= 2:
        for m2 in _pop.postes:
            if m2 == m or int(_pop.postes[m2]) <= 0:
                continue
            if niveau < 3 and _verrouille(m2):
                continue
            if _peut_ceder(m2):
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
            if not _peut_ceder(sol["de"]):
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
            if not _peut_ceder(sol["de"]):
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

func _peut_ceder(m2: String) -> bool:
    for r2 in ORDRE:
        var rend := _rendement(m2, r2)
        if rend <= 0.0:
            continue
        if _production(r2) - rend < _conso(r2) * (1.0 + MARGES[0]):
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

func _batiment_pour(effet_cherche: String) -> String:
    for type in _cons.definitions:
        var effet: Dictionary = _cons.definitions[type]["niveaux"][0].get("effet", {})
        if effet.has(effet_cherche):
            return type
    return ""

func _metiers(r: String) -> Array:
    var liste := []
    for m in _res.PRODUCTION:
        if _res.PRODUCTION[m].has(r) and m != "chef" and m != "sans métier":
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
    return float(p[r][_s]) * _efficacite(m) * _res.outils

func _adultes() -> int:
    var n := 0
    for h in _pop.habitants:
        if _pop.age(h, _jour) >= _pop.AGE_ADULTE and h["metier"] != "chef" and h["metier"] != "ancien":
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
    if r == "eau" and _s == 1:
        total += 20.0
    return total

func _avis(cle: String, texte: String) -> void:
    if _jour - int(dernier_avis.get(cle, -9999)) < 360:
        return
    dernier_avis[cle] = _jour
    evenement.emit(texte)

func vers_dict() -> Dictionary:
    return {"mode": mode, "verrou": verrou}

func depuis_dict(d: Dictionary) -> void:
    mode = str(d.get("mode", "auto"))
    verrou = {}
    for m in d.get("verrou", {}):
        verrou[m] = int(d["verrou"][m])
