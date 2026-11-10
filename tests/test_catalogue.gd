extends SceneTree

# v0.3.8 : catalogue général des ressources.
const CATALOGUE = preload("res://scripts/core/catalogue.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const ANCIENS := ["fonio_sauvage", "mil", "sorgho", "fonio", "riz_africain", "mais", "ble", "niebe", "igname", "arachide", "gombo", "karite_amande", "nere_graine", "baobab_feuille", "baobab_pulpe", "tamarin", "miel", "pasteque", "mangue", "orange", "raisin", "datte", "gibier", "poisson", "pintade", "chevre", "boeuf", "lait", "beurre_karite", "soumbala", "viande_sechee", "farine_mil", "sel", "sel_vegetal", "sucre", "coton"]

var ok := 0
var rate := 0

func _initialize() -> void:
    var c = CATALOGUE.new()
    print("   catalogue version %d : %d ressources" % [c.version, c.fiches.size()])
    for cat in c.CATEGORIES:
        print("   %-12s %2d : %s" % [cat, c.par_categorie(cat).size(), ", ".join(c.par_categorie(cat).slice(0, 6))])
    var manquants := ANCIENS.filter(func(id): return not c.existe(id))
    _verifier("les 36 produits de la v0.3.7 sont tous là, mêmes identifiants", manquants.is_empty())
    var texte := FileAccess.get_file_as_string(c.FICHIER)
    var doublons := []
    for id in c.fiches:
        if texte.count("\n  \"%s\": {" % id) != 1:
            doublons.append(id)
    _verifier("aucun identifiant en double", doublons.is_empty())
    var invalides := []
    for id in c.fiches:
        var e: Array = c.erreurs(id)
        if not e.is_empty():
            invalides.append("%s (%s)" % [id, ", ".join(e)])
    if not invalides.is_empty():
        print("   " + "\n   ".join(invalides))
    _verifier("toutes les fiches sont valides et complètes", invalides.is_empty())
    _verifier("coton : non alimentaire", c.fiche("coton")["alimentaire"] == false and c.fiche("coton")["categorie"] == "agricole")
    _verifier("sel végétal : produit transformé (pas une ressource naturelle), tiré des cendres", c.fiche("sel_vegetal")["categorie"] == "transformee" and c.fiches["sel_vegetal"]["transforme_de"] == "cendres")
    _verifier("le catalogue accueille les époques futures (acier, ciment, pétrole, cellule solaire)", c.existe("acier") and c.existe("ciment") and c.existe("petrole") and c.existe("cellule_solaire"))
    _verifier("5 familles demandées présentes (naturelles, minières, agricoles, transformées, artisanales)", c.par_categorie("naturelle").size() > 0 and c.par_categorie("miniere").size() > 0 and c.par_categorie("agricole").size() > 0 and c.par_categorie("transformee").size() > 0 and c.par_categorie("artisanale").size() > 0)
    _verifier("âge de la pierre : %d ressources possibles, futuriste : %d" % [c.disponibles_a("pierre").size(), c.disponibles_a("futuriste").size()], c.disponibles_a("pierre").size() < c.disponibles_a("futuriste").size())
    var f: Dictionary = c.fiche("ressource_inconnue")
    _verifier("fiche absente : valeurs par défaut, pas de plantage", f["unite"] == "kg" and f["categorie"] == "naturelle")
    # Les stocks de nourriture lisent toujours les mêmes valeurs nutritives.
    var r = RESSOURCES.new()
    var kcal_ok := true
    for id in ANCIENS:
        if absf(r.facteur(id) - float(c.fiches[id]["kcal_kg"]) / 3400.0) > 0.0001:
            kcal_ok = false
    _verifier("valeur nourrissante des 36 produits inchangée pour le moteur", kcal_ok and absf(r.facteur("gibier") - 1500.0 / 3400.0) < 0.0001)
    print("RÉSULTAT : %d réussis, %d ratés" % [ok, rate])
    quit()

func _verifier(nom: String, condition: bool) -> void:
    if condition:
        ok += 1
    else:
        rate += 1
    print("%s %s" % ["OK  " if condition else "RATÉ", nom])
