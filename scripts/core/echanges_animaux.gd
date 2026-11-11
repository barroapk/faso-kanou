extends RefCounted
# Échanges d'animaux entre clans de l'ordinateur (même moteur elevage.gd).
# Un clan ne vend que son vrai surplus ; l'acheteur paie en nourriture réelle.

const PROBA_MOIS := 0.2
const PRIX_PAR_KG := 4.0
const MAX_PAR_ESPECE := 10
const RESERVE_ACHETEUR := 300.0

static func mois(voisins: Array, jour: int) -> void:
    for v in voisins:
        if not v.vivant() or not v.elevage.elevage_connu:
            continue
        if v.elevage.rng.randf() >= PROBA_MOIS:
            continue
        _vendre(v, voisins, jour)

static func _surplus(el, esp: String, jour: int) -> Dictionary:
    var males: Array = []
    var femelles: Array = []
    for a in el.animaux:
        if a["esp"] != esp or not el.adulte(a, jour):
            continue
        if a["sexe"] == "m":
            males.append(a)
        else:
            femelles.append(a)
    # noyau reproducteur : 1 mâle + 2 femelles au minimum
    if males.size() > 1 and femelles.size() >= 2:
        males.sort_custom(func(x, y): return int(x["ne"]) < int(y["ne"]))
        return males[0]   # le plus vieux part, les jeunes restent
    if males.size() >= 1 and femelles.size() > 3:
        for f in femelles:
            if int(f["gest_fin"]) < 0 and int(f["lact_fin"]) <= jour:
                return f
    return {}

static func _vendre(v, voisins: Array, jour: int) -> void:
    var el = v.elevage
    for esp in el.especes:
        var a: Dictionary = _surplus(el, esp, jour)
        if a.is_empty():
            continue
        var prix: float = float(el.especes[esp]["viande_kg"]) * PRIX_PAR_KG
        var acheteurs: Array = voisins.filter(func(c): return c != v and c.vivant() and c.elevage.elevage_connu and c.elevage.nombre(esp) < MAX_PAR_ESPECE and float(c.ressources.stocks["nourriture"]) >= prix + RESERVE_ACHETEUR)
        if acheteurs.is_empty():
            continue
        var b = acheteurs[el.rng.randi() % acheteurs.size()]
        if not b.ressources.retirer("nourriture", prix, "achat animal"):
            continue
        v.ressources.ajouter("nourriture", prix, "vente animal")
        el.animaux.erase(a)
        b.elevage.ajouter(esp, a["sexe"], jour, jour - int(a["ne"]))
        return
