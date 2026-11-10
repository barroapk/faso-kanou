extends SceneTree

# Vérifie que le diagnostic détecte les pénuries d'eau, de nourriture et de bois,
# et qu'il ne change aucun poste en mode conseil.
# Lancer : godot --headless --path . --script tests/test_diagnostic.gd

const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")

var reussis := 0
var rates := 0

func _initialize() -> void:
    _cas("Eau : aucun porteur, 40 L", func(pop, res, cons): pop.postes["porteur d'eau"] = 0; res.stocks["eau"] = 40.0, "eau", "deficit", false, false)
    _cas("Nourriture : 10 kg, saison sèche", func(pop, res, cons): pop.postes["chasseur"] = 0; pop.postes["cueilleur"] = 0; pop.postes["porteur d'eau"] = 4; res.stocks["nourriture"] = 10.0, "nourriture", "deficit", false, false)
    _cas("Bois : chantier en cours, 5 kg", func(pop, res, cons): res.stocks["bois"] = 5.0, "bois", "deficit", false, true)
    _cas("Eau : 3 porteurs, stock plein mais petit", func(pop, res, cons): pop.postes["porteur d'eau"] = 3; res.stocks["eau"] = 600.0, "eau", "stockage", false, false)
    _cas("Eau : 1 porteur, marge trop faible", func(pop, res, cons): res.stocks["eau"] = 600.0, "eau", "marge", false, false)
    _cas("Nourriture : 3 chasseurs, 3 cueilleurs", func(pop, res, cons): pop.postes["chasseur"] = 3; pop.postes["cueilleur"] = 3; pop.postes["porteur d'eau"] = 0; pop.postes["bâtisseur"] = 0, "nourriture", "surplus", false, false)
    _cas("Nourriture : départ du jeu, marge faible", func(pop, res, cons): pass, "nourriture", "marge", false, false)
    _cas("Eau : saison des pluies, rien à signaler", func(pop, res, cons): res.stocks["eau"] = 300.0, "eau", "", true, false)
    print("RÉSULTAT : %d réussis, %d ratés" % [reussis, rates])
    quit()

func _cas(nom: String, preparer: Callable, r: String, attendu: String, pluie: bool, chantier: bool) -> void:
    var pop = POPULATION.new()
    var res = RESSOURCES.new()
    var cons = CONSTRUCTION.new()
    res.construction = cons
    pop.creer_clan_initial(0)
    cons.etat_initial()
    preparer.call(pop, res, cons)
    var b = BESOINS.new()
    b.mode = "conseil"
    var avant: Dictionary = pop.postes.duplicate()
    b.mois_passe(pop, res, cons, 0, pluie, chantier)
    var trouve := ""
    var detail := ""
    for p in b.problemes:
        if p["ressource"] == r:
            trouve = p["type"]
            detail = "conso %.1f, prod %.1f, réserve %.1f j, solutions %s" % [p["conso"], p["production"], p["jours_reserve"], str(p["solutions"])]
    var ok: bool = trouve == attendu and avant == pop.postes
    if ok:
        reussis += 1
    else:
        rates += 1
    print("%s | %s : attendu '%s', trouvé '%s', postes inchangés %s | %s" % ["OK " if ok else "RATÉ", nom, attendu, trouve, str(avant == pop.postes), detail])
