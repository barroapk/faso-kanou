extends Node

var temps = preload("res://scripts/core/temps.gd").new()
var population = preload("res://scripts/core/population.gd").new()

func _ready() -> void:
    population.creer_clan_initial(temps.jour_total)
    temps.nouveau_mois.connect(_mois_passe)

func _mois_passe() -> void:
    population.mois_passe(temps.jour_total)

func _process(delta: float) -> void:
    temps.avancer(delta)
