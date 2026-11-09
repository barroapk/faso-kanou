extends Node

var temps = preload("res://scripts/core/temps.gd").new()
var population = preload("res://scripts/core/population.gd").new()
var ressources = preload("res://scripts/core/ressources.gd").new()

func _ready() -> void:
    population.creer_clan_initial(temps.jour_total)
    temps.nouveau_jour.connect(_jour_passe)
    temps.nouveau_mois.connect(_mois_passe)

func _jour_passe() -> void:
    ressources.jour_passe(population, temps.jour_total, temps.saison_des_pluies())
    population.jour_passe(ressources.faim, ressources.soif)

func _mois_passe() -> void:
    population.mois_passe(temps.jour_total, ressources.stocks["nourriture"] > 100.0)

func _process(delta: float) -> void:
    temps.avancer(delta)
