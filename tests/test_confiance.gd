extends SceneTree

# Vérifie la confiance autour de l'intérim et de la nomination, mois par mois.
const POPULATION = preload("res://scripts/core/population.gd")
const CONSEIL = preload("res://scripts/core/conseil.gd")

var ok := 0
var rate := 0

func _initialize() -> void:
    var pop = POPULATION.new()
    pop.creer_clan_initial(0)
    var c = CONSEIL.new()
    c.etat_initial(pop, 0)
    var jour := 30
    # 1. Mort du chef au mois 1 : intérim d'un an.
    pop.habitants.erase(c.habitant(pop, c.chef_id))
    c.mois_passe(pop, jour)
    _verifier("intérim actif après la mort du chef", c.interim and c.chef_id >= 0)
    var baisse_pendant_interim := false
    for m in 11:
        jour += 30
        var avant: float = c.confiance
        c.mois_passe(pop, jour)
        if c.confiance < avant:
            baisse_pendant_interim = true
    _verifier("aucune baisse pendant l'intérim (11 mois)", not baisse_pendant_interim)
    # 2. Intérim terminé, personne nommé pendant 4 mois : la confiance baisse.
    for m in 4:
        jour += 30
        c.mois_passe(pop, jour)
    print("confiance après 4 mois sans chef nommé : %.0f" % c.confiance)
    _verifier("baisse après la fin de l'intérim", c.confiance < 70.0)
    # 3. Nomination officielle : plus aucune baisse pendant les 5 ans du mandat.
    var bas: float = c.confiance
    var choisi: int = -1
    for id in c.membres:
        if id != c.chef_id:
            choisi = id
            break
    _verifier("nomination acceptée", c.nommer(choisi, pop, jour) == "")
    _verifier("pas de pénalité pour remplacer un intérim", c.confiance == bas)
    var baisse_mandat := false
    for m in 59:
        jour += 30
        var avant: float = c.confiance
        c.mois_passe(pop, jour)
        if c.confiance < avant:
            baisse_mandat = true
    _verifier("aucune baisse pendant le mandat de 5 ans", not baisse_mandat)
    _verifier("la confiance remonte à 70", c.confiance == 70.0)
    # 4. Fin du mandat sans renouvellement : la baisse reprend.
    jour += 60
    c.mois_passe(pop, jour)
    _verifier("baisse après la fin du mandat", c.confiance < 70.0)
    print("RÉSULTAT : %d réussis, %d ratés" % [ok, rate])
    quit()

func _verifier(nom: String, condition: bool) -> void:
    if condition:
        ok += 1
    else:
        rate += 1
    print("%s %s" % ["OK  " if condition else "RATÉ", nom])
