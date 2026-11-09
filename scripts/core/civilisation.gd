extends Node

var temps = preload("res://scripts/core/temps.gd").new()

func _process(delta: float) -> void:
    temps.avancer(delta)
