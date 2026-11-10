extends PanelContainer

var boite: VBoxContainer
var etiquette_chantiers: Label

func _ready() -> void:
    anchor_left = 0.12
    anchor_right = 0.88
    anchor_top = 0.15
    anchor_bottom = 0.88
    var defil := ScrollContainer.new()
    add_child(defil)
    boite = VBoxContainer.new()
    boite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    boite.add_theme_constant_override("separation", 12)
    defil.add_child(boite)
    Civilisation.construction.evenement.connect(func(_t): if visible: remplir())

func _label(texte: String, taille: int) -> Label:
    var l := Label.new()
    l.text = texte
    l.add_theme_font_size_override("font_size", taille)
    return l

func _bouton(texte: String, actif: bool, action: Callable) -> Button:
    var b := Button.new()
    b.text = texte
    b.disabled = not actif
    b.add_theme_font_size_override("font_size", 26)
    b.pressed.connect(action)
    return b

func remplir() -> void:
    for c in boite.get_children():
        c.queue_free()
    var cons = Civilisation.construction
    var res = Civilisation.ressources
    boite.add_child(_label("Construction", 36))
    for type in cons.definitions:
        if not cons.disponible(type):
            continue
        var def: Dictionary = cons.definitions[type]
        var ligne := HBoxContainer.new()
        var l := _label("%s : %d" % [def["nom"], cons.nombre(type)], 30)
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        ligne.add_child(l)
        var n1: Dictionary = def["niveaux"][0]
        ligne.add_child(_bouton("Construire (%s, %d j)" % [cons.texte_cout(n1["cout"]), int(n1["travail"])], cons.peut_payer(n1["cout"], res), _agir.bind(type, -1)))
        var idx: int = cons.index_a_ameliorer(type)
        if idx >= 0:
            var niv: Dictionary = def["niveaux"][int(cons.batiments[idx]["niveau"])]
            ligne.add_child(_bouton("Améliorer (%s, %d j)" % [cons.texte_cout(niv["cout"]), int(niv["travail"])], cons.peut_payer(niv["cout"], res), _agir.bind(type, idx)))
        boite.add_child(ligne)
    etiquette_chantiers = _label("", 28)
    boite.add_child(etiquette_chantiers)

func _agir(type: String, index: int) -> void:
    Civilisation.construction.lancer(type, index, Civilisation.ressources)
    remplir()

func _process(_delta: float) -> void:
    if visible and etiquette_chantiers:
        etiquette_chantiers.text = Civilisation.construction.texte_chantiers(Civilisation.travail_batisseurs())
