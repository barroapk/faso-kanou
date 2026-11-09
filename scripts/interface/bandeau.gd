extends CanvasLayer

var etiquette_date: Label
var etiquette_pop: Label
var message: Label
var temps_message := 0.0
var panneau: PanelContainer
var liste: VBoxContainer

func _ready() -> void:
    var barre := HBoxContainer.new()
    barre.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    barre.alignment = BoxContainer.ALIGNMENT_END
    barre.offset_top = 20
    barre.offset_right = -20
    barre.add_theme_constant_override("separation", 16)
    add_child(barre)

    etiquette_pop = _etiquette(barre)
    etiquette_date = _etiquette(barre)

    var clan := Button.new()
    clan.text = "Clan"
    clan.add_theme_font_size_override("font_size", 30)
    clan.pressed.connect(_basculer_panneau)
    barre.add_child(clan)

    var groupe := ButtonGroup.new()
    var noms := ["Pause", "Jouer"]
    for i in noms.size():
        var b := Button.new()
        b.text = noms[i]
        b.toggle_mode = true
        b.button_group = groupe
        b.button_pressed = i == Civilisation.temps.vitesse
        b.add_theme_font_size_override("font_size", 30)
        b.pressed.connect(_changer_vitesse.bind(i))
        barre.add_child(b)

    message = Label.new()
    message.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    message.offset_top = -90
    message.offset_bottom = -30
    message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    message.add_theme_font_size_override("font_size", 34)
    add_child(message)

    panneau = PanelContainer.new()
    panneau.anchor_left = 0.25
    panneau.anchor_right = 0.75
    panneau.anchor_top = 0.15
    panneau.anchor_bottom = 0.85
    panneau.visible = false
    add_child(panneau)
    var defil := ScrollContainer.new()
    panneau.add_child(defil)
    liste = VBoxContainer.new()
    liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    defil.add_child(liste)

    Civilisation.population.naissance.connect(func(h): _afficher_message("Naissance : %s %s" % [h["prenom"], h["nom"]]))
    Civilisation.population.deces.connect(func(h): _afficher_message("Décès : %s %s" % [h["prenom"], h["nom"]]))

func _etiquette(parent: Control) -> Label:
    var l := Label.new()
    l.add_theme_font_size_override("font_size", 32)
    parent.add_child(l)
    return l

func _changer_vitesse(i: int) -> void:
    Civilisation.temps.vitesse = i

func _afficher_message(texte: String) -> void:
    message.text = texte
    temps_message = 5.0
    if panneau.visible:
        _remplir_liste()

func _basculer_panneau() -> void:
    panneau.visible = not panneau.visible
    if panneau.visible:
        _remplir_liste()

func _remplir_liste() -> void:
    for ligne in liste.get_children():
        ligne.queue_free()
    var pop = Civilisation.population
    var jour: int = Civilisation.temps.jour_total
    for h in pop.habitants:
        var l := Label.new()
        l.text = "%s %s · %d ans · %s" % [h["prenom"], h["nom"], pop.age(h, jour), h["metier"]]
        l.add_theme_font_size_override("font_size", 28)
        liste.add_child(l)

func _process(delta: float) -> void:
    etiquette_pop.text = "Habitants : %d" % Civilisation.population.habitants.size()
    etiquette_date.text = Civilisation.temps.texte()
    if temps_message > 0.0:
        temps_message -= delta
        if temps_message <= 0.0:
            message.text = ""
