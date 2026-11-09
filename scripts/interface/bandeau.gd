extends CanvasLayer

var etiquette_date: Label

func _ready() -> void:
    var barre := HBoxContainer.new()
    barre.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    barre.alignment = BoxContainer.ALIGNMENT_END
    barre.offset_top = 20
    barre.offset_right = -20
    barre.add_theme_constant_override("separation", 12)
    add_child(barre)

    etiquette_date = Label.new()
    etiquette_date.add_theme_font_size_override("font_size", 32)
    barre.add_child(etiquette_date)

    var groupe := ButtonGroup.new()
    var noms := ["Pause", "x1", "x3", "x8"]
    for i in noms.size():
        var b := Button.new()
        b.text = noms[i]
        b.toggle_mode = true
        b.button_group = groupe
        b.button_pressed = i == Civilisation.temps.vitesse
        b.add_theme_font_size_override("font_size", 30)
        b.pressed.connect(_changer_vitesse.bind(i))
        barre.add_child(b)

func _changer_vitesse(i: int) -> void:
    Civilisation.temps.vitesse = i

func _process(_delta: float) -> void:
    etiquette_date.text = Civilisation.temps.texte()
