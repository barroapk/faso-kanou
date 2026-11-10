extends Node

const DOSSIER := "user://"
const FICHIER := "partie.json"
const VERSION := 4
const TEMPS = preload("res://scripts/core/temps.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")
const CONSEIL = preload("res://scripts/core/conseil.gd")
const CHEF = preload("res://scripts/core/chef.gd")
const MIGRATION = preload("res://scripts/core/migration.gd")

var temps
var population
var ressources
var construction
var besoins
var conseil
var chef
var migration

func _ready() -> void:
    if not _charger(FICHIER) and not _charger(FICHIER + ".bak"):
        _nouvelle()
    _brancher()

func _creer_modules() -> void:
    temps = TEMPS.new()
    population = POPULATION.new()
    ressources = RESSOURCES.new()
    construction = CONSTRUCTION.new()
    besoins = BESOINS.new()
    conseil = CONSEIL.new()
    chef = CHEF.new()
    migration = MIGRATION.new()
    migration.initialiser(2026)
    ressources.construction = construction

func _nouvelle() -> void:
    _creer_modules()
    population.creer_clan_initial(temps.jour_total)
    construction.etat_initial()
    conseil.etat_initial(population, temps.jour_total)

func _brancher() -> void:
    temps.nouveau_jour.connect(_jour_passe)
    temps.nouveau_mois.connect(_mois_passe)

func nouvelle_partie() -> void:
    _nouvelle()
    _brancher()
    sauvegarder()
    get_tree().reload_current_scene()

func travail_batisseurs() -> float:
    var t := 0.0
    for h in population.habitants:
        if h["metier"] == "bâtisseur":
            t += 0.6 + float(h["competence"]) / 100.0 * 0.8
    return t

# Décisions du joueur sur les propositions du chef (écran du chef, v0.3.4).
func appliquer_proposition(cle: String, index: int) -> String:
    besoins.actualiser(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), not construction.chantiers.is_empty())
    var raison: String = chef.appliquer_proposition(cle, index, besoins, temps.jour_total)
    if raison == "":
        population.repartir(temps.jour_total)
    return raison

func ignorer_alerte(cle: String) -> String:
    return chef.ignorer(cle, temps.jour_total)

func _jour_passe() -> void:
    var chantier_actif: bool = not construction.chantiers.is_empty()
    ressources.jour_passe(population, temps.jour_total, temps.saison_des_pluies(), chantier_actif)
    construction.jour_passe(travail_batisseurs())
    population.jour_passe(ressources.faim, ressources.soif)
    if temps.jour_total % chef.REVUE_JOURS == 0:
        besoins.actualiser(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), chantier_actif)
        chef.revue(conseil, population, besoins, temps.jour_total)
    if population.habitants.is_empty(): temps.vitesse = 0

func _mois_passe() -> void:
    construction.mois_passe(ressources)
    var logement: float = construction.effet_total("logement")
    population.mois_passe(temps.jour_total, ressources.stocks["nourriture"] > 100.0, int(logement))
    conseil.mois_passe(population, temps.jour_total)
    besoins.mois_passe(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), not construction.chantiers.is_empty())
    migration.mois_passe(population, ressources, construction, temps.jour_total)
    population.repartir(temps.jour_total)
    sauvegarder()

func _process(delta: float) -> void:
    temps.avancer(delta)

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
        sauvegarder()

func sauvegarder() -> void:
    var donnees := {
        "version": VERSION,
        "temps": temps.vers_dict(),
        "population": population.vers_dict(),
        "ressources": ressources.vers_dict(),
        "construction": construction.vers_dict(),
        "besoins": besoins.vers_dict(),
        "conseil": conseil.vers_dict(),
        "chef": chef.vers_dict(),
        "migration": migration.vers_dict(),
    }
    var f := FileAccess.open(DOSSIER + FICHIER + ".tmp", FileAccess.WRITE)
    if f == null:
        push_error("Sauvegarde impossible")
        return
    f.store_string(JSON.stringify(donnees))
    f.close()
    var d := DirAccess.open(DOSSIER)
    if d.file_exists(FICHIER):
        d.rename(FICHIER, FICHIER + ".bak")
    d.rename(FICHIER + ".tmp", FICHIER)

func _charger(nom: String) -> bool:
    var chemin := DOSSIER + nom
    if not FileAccess.file_exists(chemin):
        return false
    var donnees = JSON.parse_string(FileAccess.get_file_as_string(chemin))
    if typeof(donnees) != TYPE_DICTIONARY:
        return false
    _creer_modules()
    temps.depuis_dict(donnees.get("temps", {}))
    population.depuis_dict(donnees.get("population", {}))
    ressources.depuis_dict(donnees.get("ressources", {}))
    construction.depuis_dict(donnees.get("construction", {}))
    besoins.depuis_dict(donnees.get("besoins", {}))
    conseil.depuis_dict(donnees.get("conseil", {}), population, temps.jour_total)
    chef.depuis_dict(donnees.get("chef", {}))
    migration.depuis_dict(donnees.get("migration", {}), 2026)
    temps.vitesse = 1
    return true
