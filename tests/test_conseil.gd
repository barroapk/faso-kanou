extends SceneTree

# Vérifie le Conseil des cinq : composition, notes, nomination, succession sur 100 ans.
# Lancer : godot --headless --path . --script tests/test_conseil.gd

const TEMPS = preload("res://scripts/core/temps.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")
const CONSEIL = preload("res://scripts/core/conseil.gd")

var pop
var res
var cons
var besoins
var conseil
var jour := 0
var ok := 0
var rate := 0
var entrees := 0
var interims := 0

func _initialize() -> void:
    pop = POPULATION.new()
    res = RESSOURCES.new()
    cons = CONSTRUCTION.new()
    res.construction = cons
    besoins = BESOINS.new()
    conseil = CONSEIL.new()
    pop.creer_clan_initial(0)
    cons.etat_initial()
    conseil.etat_initial(pop, 0)
    print("--- Conseil de départ ---")
    _afficher()
    _verifier("5 sièges occupés", conseil.membres.size() == 5)
    _verifier("le chef est Ousmane", conseil.habitant(pop, conseil.chef_id)["prenom"] == "Ousmane")
    _verifier("Tenga (ancien) est au conseil", _membre("Tenga"))
    _verifier("refus : nommer un non-membre", conseil.nommer(_id("Issa"), pop, 0) != "")
    _verifier("refus : renouveler trop tôt", conseil.renouveler(pop, 0) != "")
    var id_aminata := _id("Aminata")
    var conf: float = conseil.confiance
    _verifier("nommer Aminata accepté", conseil.nommer(id_aminata, pop, 0) == "")
    _verifier("Aminata devient chef", conseil.habitant(pop, id_aminata)["metier"] == "chef")
    _verifier("Ousmane redevient travailleur", conseil.habitant(pop, _id("Ousmane"))["metier"] == "sans métier")
    _verifier("confiance baisse de 10", conseil.confiance == conf - 10.0)
    var sauve: Dictionary = conseil.vers_dict()
    var copie = CONSEIL.new()
    copie.depuis_dict(JSON.parse_string(JSON.stringify(sauve)), pop, 0)
    _verifier("sauvegarde relue identique", copie.membres == conseil.membres and copie.chef_id == conseil.chef_id)
    print("--- 100 ans ---")
    var sans_chef := 0
    var sieges_vides := 0
    conseil.evenement.connect(_compter)
    for an in 100:
        for j in 360:
            jour += 1
            res.jour_passe(pop, jour, (jour / 30) % 12 >= 5 and (jour / 30) % 12 <= 9, not cons.chantiers.is_empty())
            pop.jour_passe(res.faim, res.soif)
            if jour % 30 == 0:
                cons.mois_passe(res)
                pop.mois_passe(jour, res.stocks["nourriture"] > 100.0 and pop.habitants.size() < cons.effet_total("logement"))
                besoins.mois_passe(pop, res, cons, jour, (jour / 30) % 12 >= 5 and (jour / 30) % 12 <= 9, false)
                conseil.mois_passe(pop, jour)
                if jour >= conseil.mandat_fin and jour < conseil.mandat_fin + 30:
                    conseil.renouveler(pop, jour)
                pop.repartir(jour)
                if conseil.chef_id < 0:
                    sans_chef += 1
                if conseil.membres.size() < 5:
                    sieges_vides += 1
        if an % 25 == 24:
            print("An %d : %d habitants" % [an + 1, pop.habitants.size()])
            _afficher()
    _verifier("toujours un chef sur 100 ans", sans_chef == 0)
    _verifier("5 sièges occupés sur 100 ans", sieges_vides == 0)
    _verifier("succession : nouveaux membres entrés", entrees > 0)
    print("Entrées au conseil : %d, intérims après décès du chef : %d" % [entrees, interims])
    print("RÉSULTAT : %d réussis, %d ratés" % [ok, rate])
    quit()

func _afficher() -> void:
    for id in conseil.membres:
        var h = conseil.habitant(pop, id)
        var n: Dictionary = conseil.notes(h, pop, jour)
        print("  %s%s %s, %d ans, %s, %s | intel %d gest %d prev %d infl %d loy %d exp %d" % ["[CHEF] " if id == conseil.chef_id else "", h["prenom"], h["nom"], pop.age(h, jour), h["metier"], h["caractere"], n["intelligence"], n["gestion"], n["prevoyance"], n["influence"], n["loyaute"], n["experience"]])

func _id(prenom: String) -> int:
    for h in pop.habitants:
        if h["prenom"] == prenom:
            return int(h["id"])
    return -1

func _membre(prenom: String) -> bool:
    return conseil.membres.has(_id(prenom))

func _verifier(nom: String, condition: bool) -> void:
    if condition:
        ok += 1
    else:
        rate += 1
    print("%s %s" % ["OK  " if condition else "RATÉ", nom])

func _compter(t: String) -> void:
    if t.ends_with("entre au conseil."):
        entrees += 1
    if t.contains("intérim"):
        interims += 1
