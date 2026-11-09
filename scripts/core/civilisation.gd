extends Node

const DOSSIER := "user://"
const FICHIER := "partie.json"
const VERSION := 1
const TEMPS = preload("res://scripts/core/temps.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")

var temps
var population
var ressources

func _ready() -> void:
    if not _charger(FICHIER) and not _charger(FICHIER + ".bak"):
        _nouvelle()
    _brancher()

func _nouvelle() -> void:
    temps = TEMPS.new()
    population = POPULATION.new()
    ressources = RESSOURCES.new()
    population.creer_clan_initial(temps.jour_total)

func _brancher() -> void:
    temps.nouveau_jour.connect(_jour_passe)
    temps.nouveau_mois.connect(_mois_passe)

func nouvelle_partie() -> void:
    _nouvelle()
    _brancher()
    sauvegarder()
    get_tree().reload_current_scene()

func _jour_passe() -> void:
    ressources.jour_passe(population, temps.jour_total, temps.saison_des_pluies())
    population.jour_passe(ressources.faim, ressources.soif)

func _mois_passe() -> void:
    population.mois_passe(temps.jour_total, ressources.stocks["nourriture"] > 100.0)
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
    temps = TEMPS.new()
    population = POPULATION.new()
    ressources = RESSOURCES.new()
    temps.depuis_dict(donnees.get("temps", {}))
    population.depuis_dict(donnees.get("population", {}))
    ressources.depuis_dict(donnees.get("ressources", {}))
    temps.vitesse = 1
    return true
