extends PanelContainer

var lignes := {}
var libres: Label

func _ready() -> void:
    anchor_left = 0.25
    anchor_right = 0.75
    anchor_top = 0.2
    anchor_bottom = 0.8
    var boite := VBoxContainer.new()
    boite.add_theme_constant_override("separation", 14)
    add_child(boite)
    var titre := Label.new()
    titre.text = "Postes de travail"
    titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    titre.add_theme_font_size_override("font_size", 36)
    boite.add_child(titre)
    for m in Civilisation.population.metiers_choisis():
        if m == "sans métier":
            continue
        var ligne := HBoxContainer.new()
        var l := Label.new()
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        l.add_theme_font_size_override("font_size", 30)
        ligne.add_child(l)
        for delta in [-1, 1]:
            var b := Button.new()
            b.text = "-" if delta < 0 else "+"
            b.custom_minimum_size = Vector2(90, 0)
            b.add_theme_font_size_override("font_size", 34)
            b.pressed.connect(_changer_postes.bind(m, delta))
            ligne.add_child(b)
        boite.add_child(ligne)
        lignes[m] = l
    libres = Label.new()
    libres.add_theme_font_size_override("font_size", 30)
    boite.add_child(libres)

func _changer_postes(m: String, delta: int) -> void:
    Civilisation.population.changer_postes(m, delta, Civilisation.temps.jour_total)

func _process(_delta: float) -> void:
    if not visible:
        return
    var pop = Civilisation.population
    for m in lignes:
        var nom: String = m
        lignes[m].text = "%s : %d travailleurs / %d postes" % [nom[0].to_upper() + nom.substr(1), pop.nombre(m), int(pop.postes[m])]
    libres.text = "Sans métier disponibles : %d" % pop.nombre("sans métier")
