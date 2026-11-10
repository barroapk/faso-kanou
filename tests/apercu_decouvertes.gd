extends SceneTree
# Contrôle léger : une découverte se produit quand ses conditions sont réunies,
# débloque ses recettes, puis se perd si plus personne ne pratique.
const CIV = preload("res://scripts/core/civilisation.gd")
func _initialize() -> void:
    var c = CIV.new()
    c._nouvelle()
    c._brancher()
    c.decouvertes.evenement.connect(func(t): print("   ", t))
    var h: Dictionary = c.population.habitants[1]
    print("Avant : ", c.decouvertes.manque("charbonnage", c.population, c.ressources, c.recettes, 0))
    print("Fourneau constructible ? ", c.construction.disponible("fourneau"))
    c.population.donner_savoir(h, "artisanat", 45.0)
    c.recettes.faites["canari"] = 10
    for m in 600:
        c.ressources.stocks["bois"] = maxf(c.ressources.stocks["bois"], 300.0)
        for j in 30:
            c.temps._passer_un_jour()
        if c.decouvertes.connait("charbonnage"):
            print("Charbonnage découvert au mois %d ; charbon connu : %s" % [m + 1, c.recettes.connues.has("charbon_bois")])
            break
    print("Métallurgie : ", c.decouvertes.manque("metallurgie", c.population, c.ressources, c.recettes, c.temps.jour_total))
    c.free()
    quit()
