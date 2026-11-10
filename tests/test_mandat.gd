extends SceneTree

# Vérifie qu'il n'y a pas de messages de mandat à répétition,
# avec un joueur qui ne nomme jamais personne (100 ans).
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")
const CONSEIL = preload("res://scripts/core/conseil.gd")

var messages_mois := 0
var max_mois := 0
var total := {}

func _initialize() -> void:
    var pop = POPULATION.new()
    var res = RESSOURCES.new()
    var cons = CONSTRUCTION.new()
    res.construction = cons
    var besoins = BESOINS.new()
    var conseil = CONSEIL.new()
    pop.creer_clan_initial(0)
    cons.etat_initial()
    conseil.etat_initial(pop, 0)
    conseil.evenement.connect(_compter)
    var jour := 0
    for an in 100:
        for j in 360:
            jour += 1
            var pluie: bool = (jour / 30) % 12 >= 5 and (jour / 30) % 12 <= 9
            res.jour_passe(pop, jour, pluie, false)
            pop.jour_passe(res.faim, res.soif)
            if jour % 30 == 0:
                cons.mois_passe(res)
                pop.mois_passe(jour, res.stocks["nourriture"] > 100.0 and pop.habitants.size() < cons.effet_total("logement"))
                messages_mois = 0
                conseil.mois_passe(pop, jour)
                max_mois = maxi(max_mois, messages_mois)
                besoins.mois_passe(pop, res, cons, jour, pluie, false)
                pop.repartir(jour)
    for k in total:
        print("%s : %d" % [k, total[k]])
    print("Messages de mandat au maximum dans un même mois : %d" % max_mois)
    print("Confiance finale : %.0f" % conseil.confiance)
    quit()

func _compter(t: String) -> void:
    var k := "autre"
    if t.contains("intérim de"):
        k = "fin d'intérim"
    elif t.contains("assure l'intérim"):
        k = "début d'intérim"
    elif t.begins_with("Rappel"):
        k = "rappel annuel"
    elif t.contains("se termine"):
        k = "fin de mandat"
    if k != "autre":
        messages_mois += 1
    total[k] = int(total.get(k, 0)) + 1
