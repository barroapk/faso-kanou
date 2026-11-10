extends RefCounted

# Catalogue général des ressources (v0.3.8) : data/produits.json.
# Ce fichier décrit les ressources ; il ne produit rien.
# Les recettes (transformations) viendront à l'étape 2.
# Règle : un identifiant n'est jamais renommé ni supprimé (sauvegardes).

const FICHIER := "res://data/produits.json"
const CATEGORIES := ["alimentaire", "naturelle", "miniere", "agricole", "transformee", "artisanale"]
const UNITES := ["kg", "L", "g", "piece"]
const EPOQUES := ["pierre", "fer", "royaumes", "industriel", "contemporain", "technologique", "futuriste"]
const DISPONIBILITES := ["locale", "introduite", "commerce", "transformation"]
# Valeurs par défaut : une fiche ancienne ou incomplète reste utilisable.
const DEFAUTS := {
    "nom": "",
    "categorie": "naturelle",
    "sous_categorie": "",
    "alimentaire": false,
    "kcal_kg": 0,
    "unite": "kg",
    "masse_unite_kg": 1.0,
    "perte_jour": 0.0,
    "sec": true,
    "valeur": 0.0,
    "epoque": "pierre",
    "disponibilite": "locale",
    "terrains": [],
    "saisons": [],
    "usages": [],
    "obtention": "",
}

var fiches := {}
var version := 1

func _init() -> void:
    var d = JSON.parse_string(FileAccess.get_file_as_string(FICHIER))
    if typeof(d) == TYPE_DICTIONARY:
        fiches = d.get("produits", {})
        version = int(d.get("version_catalogue", 1))

func existe(id: String) -> bool:
    return fiches.has(id)

# Fiche complète, avec les valeurs par défaut pour les champs absents.
func fiche(id: String) -> Dictionary:
    var f: Dictionary = DEFAUTS.duplicate(true)
    f["nom"] = id
    for cle in fiches.get(id, {}):
        f[cle] = fiches[id][cle]
    return f

func par_categorie(categorie: String) -> Array:
    var ids := []
    for id in fiches:
        if fiche(id)["categorie"] == categorie:
            ids.append(id)
    return ids

func disponibles_a(epoque: String) -> Array:
    var limite := EPOQUES.find(epoque)
    var ids := []
    for id in fiches:
        if EPOQUES.find(fiche(id)["epoque"]) <= limite:
            ids.append(id)
    return ids

# Liste des erreurs de la fiche (vide = fiche valide).
func erreurs(id: String) -> Array:
    var e := []
    var brut: Dictionary = fiches.get(id, {})
    for cle in DEFAUTS:
        if not brut.has(cle):
            e.append("champ manquant : %s" % cle)
    var f := fiche(id)
    if not CATEGORIES.has(f["categorie"]):
        e.append("catégorie inconnue : %s" % f["categorie"])
    if not UNITES.has(f["unite"]):
        e.append("unité inconnue : %s" % f["unite"])
    if not EPOQUES.has(f["epoque"]):
        e.append("époque inconnue : %s" % f["epoque"])
    if not DISPONIBILITES.has(f["disponibilite"]):
        e.append("disponibilité inconnue : %s" % f["disponibilite"])
    if float(f["masse_unite_kg"]) <= 0.0:
        e.append("masse nulle")
    if float(f["valeur"]) < 0.0:
        e.append("valeur négative")
    for m in f["saisons"]:
        if int(m) < 0 or int(m) > 11:
            e.append("mois impossible : %s" % str(m))
    if bool(f["alimentaire"]) != (float(f["kcal_kg"]) > 0.0) and id != "sel" and id != "sel_vegetal":
        e.append("alimentaire et calories incohérents")
    var t: String = brut.get("transforme_de", "")
    if t != "" and not fiches.has(t):
        e.append("transforme_de inconnu : %s" % t)
    if f["obtention"] == "":
        e.append("obtention vide")
    return e
