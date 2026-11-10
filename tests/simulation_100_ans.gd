extends SceneTree

# Simule 100 ans et affiche un bilan par an.
# Lancer : godot --headless --path . --script tests/simulation_100_ans.gd -- competent
# Scénarios : auto (chef automatique actuel), competent (joueur qui applique
# les conseils par appliquer()), negligent (joueur qui ignore tout),
# suit_chef (joueur qui accepte toujours la 1re proposition du chef).

const TEMPS = preload("res://scripts/core/temps.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")
const CONSEIL = preload("res://scripts/core/conseil.gd")
const CHEF = preload("res://scripts/core/chef.gd")

var scenario := "competent"
var temps
var population
var ressources
var construction
var besoins
var conseil
var chef
var alertes_chef := 0
var premiere_alerte := ""
var naissances := 0
var deces := 0
var jours_faim := 0
var jours_soif := 0
var mini_nourriture := 0.0
var mini_eau := 0.0
var alertes := 0
var actions := 0
var refus := 0
var modifs_cachees := 0
var total_deces := 0

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() > 0:
        scenario = args[0]
    temps = TEMPS.new()
    population = POPULATION.new()
    ressources = RESSOURCES.new()
    construction = CONSTRUCTION.new()
    ressources.construction = construction
    besoins = BESOINS.new()
    besoins.mode = "auto" if scenario == "auto" else "conseil"
    population.creer_clan_initial(temps.jour_total)
    construction.etat_initial()
    conseil = CONSEIL.new()
    conseil.etat_initial(population, 0)
    chef = CHEF.new()
    chef.evenement.connect(_alerte_chef)
    population.naissance.connect(func(_h): naissances += 1)
    population.deces.connect(func(_h): deces += 1)
    print("Scénario : %s" % scenario)
    print("an | hab | naiss | deces | nourr mini | eau mini | faim | soif | postes")
    var fin := 100
    for an in range(1, 101):
        naissances = 0
        deces = 0
        jours_faim = 0
        jours_soif = 0
        mini_nourriture = 99999.0
        mini_eau = 99999.0
        for j in 360:
            temps.jour_total += 1
            _jour()
            if temps.jour_total % 30 == 0:
                _mois()
        total_deces += deces
        print("%3d | %3d | %2d | %2d | %5.0f | %5.0f | %3d | %3d | %s" % [an, population.habitants.size(), naissances, deces, mini_nourriture, mini_eau, jours_faim, jours_soif, _postes()])
        if population.habitants.is_empty():
            print("Le clan a disparu.")
            fin = an
            break
    print("BILAN %s : fin an %d, habitants %d, décès %d, alertes %d, actions %d, refus %d, modifications sans accord %d, alertes du chef %d, manquées (danger < 10 j) dans ses missions %d, hors missions %d" % [scenario, fin, population.habitants.size(), total_deces, alertes, actions, refus, modifs_cachees, alertes_chef, chef.manquees, chef.hors_mission])
    if premiere_alerte != "": print(premiere_alerte)
    quit()

func _postes() -> String:
    var t := []
    for m in population.postes:
        t.append("%s %d" % [m.substr(0, 4), population.postes[m]])
    return ", ".join(t)

func _travail() -> float:
    var t := 0.0
    for h in population.habitants:
        if h["metier"] == "bâtisseur":
            t += 0.6 + float(h["competence"]) / 100.0 * 0.8
    return t

func _jour() -> void:
    ressources.jour_passe(population, temps.jour_total, temps.saison_des_pluies(), not construction.chantiers.is_empty())
    construction.jour_passe(_travail())
    population.jour_passe(ressources.faim, ressources.soif)
    if ressources.faim: jours_faim += 1
    if ressources.soif: jours_soif += 1
    mini_nourriture = minf(mini_nourriture, ressources.stocks["nourriture"])
    mini_eau = minf(mini_eau, ressources.stocks["eau"])
    if temps.jour_total % chef.REVUE_JOURS == 0:
        besoins.actualiser(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), not construction.chantiers.is_empty())
        chef.revue(conseil, population, besoins, temps.jour_total)
        if scenario == "suit_chef":
            for a in chef.alertes.duplicate():
                if a["propositions"].size() > 0:
                    besoins.actualiser(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), not construction.chantiers.is_empty())
                    var raison: String = chef.appliquer_proposition(a["cle"], 0, besoins, temps.jour_total)
                    if raison == "":
                        actions += 1
                        population.repartir(temps.jour_total)
                    else:
                        refus += 1

func _mois() -> void:
    construction.mois_passe(ressources)
    var logement: float = construction.effet_total("logement")
    population.mois_passe(temps.jour_total, ressources.stocks["nourriture"] > 100.0 and population.habitants.size() < logement)
    var avant: Dictionary = population.postes.duplicate()
    besoins.mois_passe(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), not construction.chantiers.is_empty())
    if besoins.mode == "conseil" and avant != population.postes:
        modifs_cachees += 1
    for p in besoins.problemes:
        if p["type"] == "deficit":
            alertes += 1
    conseil.mois_passe(population, temps.jour_total)
    if scenario == "competent":
        _joueur_competent()
    population.repartir(temps.jour_total)

func _joueur_competent() -> void:
    for r in besoins.ORDRE:
        for i in 3:
            var p := {}
            for q in besoins.diagnostiquer():
                if q["ressource"] == r:
                    p = q
            if p.is_empty() or p["solutions"].is_empty():
                break
            var raison: String = besoins.appliquer(p["solutions"][0])
            if raison != "":
                refus += 1
                break
            actions += 1

func _alerte_chef(t: String) -> void:
    alertes_chef += 1
    if scenario == "negligent":
        print("    an %d, jour %d : %s" % [temps.annee(), temps.jour_total % 360, t])
