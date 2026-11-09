extends Node3D

const DIST_MIN := 6.0
const DIST_MAX := 1700.0
const INCLINAISON := 55.0
const LIMITE_ILE := 950.0

var distance := 20.0
var camera: Camera3D
var doigts := {}

func _ready() -> void:
    camera = Camera3D.new()
    camera.far = 6000.0
    camera.near = 1.0
    add_child(camera)
    _placer_camera()

func _placer_camera() -> void:
    var angle := deg_to_rad(INCLINAISON)
    camera.position = Vector3(0, sin(angle) * distance, cos(angle) * distance)
    camera.look_at(global_position)

func _ecart_doigts() -> float:
    var p: Array = doigts.values()
    return p[0].distance_to(p[1])

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            doigts[event.index] = event.position
        else:
            doigts.erase(event.index)
    elif event is InputEventScreenDrag:
        if doigts.size() == 2:
            var avant := _ecart_doigts()
            doigts[event.index] = event.position
            var apres := _ecart_doigts()
            if apres > 0.0:
                distance = clamp(distance * avant / apres, DIST_MIN, DIST_MAX)
                _placer_camera()
        else:
            doigts[event.index] = event.position
            var vitesse := distance * 0.0015
            position.x = clamp(position.x - event.relative.x * vitesse, -LIMITE_ILE, LIMITE_ILE)
            position.z = clamp(position.z - event.relative.y * vitesse, -LIMITE_ILE, LIMITE_ILE)
