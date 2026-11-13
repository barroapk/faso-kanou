extends PanelContainer

# Fiche d'un habitant (v0.4) : identité, métiers possibles avec leur production,
# aperçu avant décision, confirmation. L'affectation protège la personne 90 jours.

signal fermee

const NOMS_RES := {"eau": "eau", "nourriture": "nourriture", "bois": "bois"}

var habitant: Dictionary = {}
var choix := ""            # métier choisi, pas encore confirmé
var boite: VBoxContainer
var infos: Label
var lignes: VBoxContainer
var apercu: Label
var avis: Label
var bouton_ok: Button
var _bilan := ""           # dernier résultat affiché après confirmation

func _ready() -> void:
    anchor_left = 0.05
    anchor_right = 0.95
    anchor_top = 0.05
    anchor_bottom = 0.95
    # Fond opaque : on ne doit pas voir l'écran du jeu à travers la fiche.
    var fond := StyleBoxFlat.new()
    fond.bg_color = Color(0.07, 0.09, 0.12, 1.0)
    fond.border_color = Color(0.85, 0.65, 0.25)
    fond.set_border_width_all(3)
    fond.set_corner_radius_all(12)
    fond.set_content_margin_all(24)
    add_theme_stylebox_override("panel", fond)
    var defil := ScrollContainer.new()
    defil.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(defil)
    boite = VBoxContainer.new()
    boite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    boite.add_theme_constant_override("separation", 14)
    defil.add_child(boite)
    infos = _label(28)
    boite.add_child(infos)
    boite.add_child(HSeparator.new())
    # Aperçu et alerte en haut : on les voit sans faire défiler.
    avis = _label(32)
    avis.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
    boite.add_child(avis)
    apercu = _label(28)
    apercu.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
    boite.add_child(apercu)
    var bas := HBoxContainer.new()
    bas.add_theme_constant_override("separation", 16)
    boite.add_child(bas)
    bouton_ok = Button.new()
    bouton_ok.text = "Confirmer"
    bouton_ok.add_theme_font_size_override("font_size", 32)
    bouton_ok.pressed.connect(_confirmer)
    bas.add_child(bouton_ok)
    var annuler := Button.new()
    annuler.text = "Annuler le choix"
    annuler.add_theme_font_size_override("font_size", 32)
    annuler.pressed.connect(_annuler)
    bas.add_child(annuler)
    var retour := Button.new()
    retour.text = "Retour à la liste"
    retour.add_theme_font_size_override("font_size", 32)
    retour.pressed.connect(func(): fermee.emit())
    bas.add_child(retour)
    boite.add_child(HSeparator.new())
    var t := _label(30)
    t.text = "Métiers possibles (production par jour)"
    boite.add_child(t)
    lignes = VBoxContainer.new()
    lignes.add_theme_constant_override("separation", 6)
    boite.add_child(lignes)

func _label(taille: int) -> Label:
    var l := Label.new()
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    l.add_theme_font_size_override("font_size", taille)
    return l

func ouvrir(h: Dictionary) -> void:
    habitant = h
    choix = ""
    _bilan = ""
    remplir()

func _jour() -> int:
    return Civilisation.temps.jour_total

func _famille_texte() -> String:
    var pop = Civilisation.population
    var morceaux: PackedStringArray = []
    var pere: Dictionary = pop.par_id(int(habitant.get("pere", -1)))
    var mere: Dictionary = pop.par_id(int(habitant.get("mere", -1)))
    if not pere.is_empty():
        morceaux.append("père : %s" % pere["prenom"])
    if not mere.is_empty():
        morceaux.append("mère : %s" % mere["prenom"])
    var c: Dictionary = pop.couple_actif(habitant)
    if not c.is_empty():
        var autre: Dictionary = pop.par_id(int(c["femme"]) if int(c["mari"]) == int(habitant["id"]) else int(c["mari"]))
        if not autre.is_empty():
            morceaux.append("conjoint : %s" % autre["prenom"])
    var enfants := 0
    for x in pop.habitants:
        if int(x.get("pere", -1)) == int(habitant["id"]) or int(x.get("mere", -1)) == int(habitant["id"]):
            enfants += 1
    if enfants > 0:
        morceaux.append("%d enfant(s)" % enfants)
    return ", ".join(morceaux) if not morceaux.is_empty() else "aucune parenté connue"

func _texte_production(prod: Dictionary) -> String:
    var l: PackedStringArray = []
    for r in prod:
        l.append("%s %.1f" % [NOMS_RES.get(r, r), float(prod[r])])
    return ", ".join(l) if not l.is_empty() else "rien"

func remplir() -> void:
    var pop = Civilisation.population
    var jour := _jour()
    if habitant.is_empty() or pop.par_id(int(habitant["id"])).is_empty():
        infos.text = "Cette personne n'est plus là."
        for c in lignes.get_children():
            c.queue_free()
        return
    var protection := ""
    if pop.est_protege(habitant, jour):
        protection = "\nAffectation décidée par vous : protégée encore %d jours." % (int(habitant["protege_jusqu"]) - jour)
    infos.text = "%s %s · %d ans · santé %d · compétence %d\nMétier : %s\nFamille : %s%s" % [habitant["prenom"], habitant["nom"], pop.age(habitant, jour), int(habitant["sante"]), int(habitant["competence"]), pop.nom_metier(habitant), _famille_texte(), protection]
    for c in lignes.get_children():
        c.queue_free()
    var pluie: bool = Civilisation.temps.saison_des_pluies()
    var options: Array = pop.metiers_choisis()
    options.append("sans métier")
    for m in options:
        var ligne := HBoxContainer.new()
        var l := _label(26)
        var prod: Dictionary = Civilisation.ressources.apercu_metier(habitant, m, pop, pluie)
        var niveau: float = pop.savoir(habitant, pop.savoir_du_metier(m))
        l.text = "%s%s — niveau %d — %s" % ["▶ " if m == choix else "", pop.nom_metier({"metier": m, "sexe": habitant["sexe"]}), int(niveau), _texte_production(prod)]
        if m == habitant["metier"]:
            l.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
        elif m == choix:
            l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
        ligne.add_child(l)
        var raison: String = pop.raison_affectation(habitant, m, jour)
        var b := Button.new()
        b.add_theme_font_size_override("font_size", 28)
        if raison != "":
            b.text = raison
            b.disabled = true
        else:
            b.text = "Choisir"
            b.pressed.connect(_choisir.bind(m))
        ligne.add_child(b)
        lignes.add_child(ligne)
    _maj_apercu()

func _choisir(m: String) -> void:
    choix = m
    _bilan = ""
    remplir()

func _annuler() -> void:
    choix = ""
    remplir()

func _maj_apercu() -> void:
    var pop = Civilisation.population
    avis.text = ""
    bouton_ok.disabled = choix == ""
    if choix == "":
        apercu.text = _bilan
        return
    var pluie: bool = Civilisation.temps.saison_des_pluies()
    var perdu: Dictionary = Civilisation.ressources.apercu_metier(habitant, habitant["metier"], pop, pluie)
    var gagne: Dictionary = Civilisation.ressources.apercu_metier(habitant, choix, pop, pluie)
    var delta := {}
    for r in perdu:
        delta[r] = float(delta.get(r, 0.0)) - float(perdu[r])
    for r in gagne:
        delta[r] = float(delta.get(r, 0.0)) + float(gagne[r])
    var l: PackedStringArray = []
    for r in delta:
        l.append("%s %+.1f /jour" % [NOMS_RES.get(r, r), float(delta[r])])
    apercu.text = "Si vous le faites passer de %s à %s : %s.\n%s" % [habitant["metier"], choix, ", ".join(l) if not l.is_empty() else "aucun changement de production", _reserves_texte()]
    avis.text = _alerte()

# Réserves en jours, à la consommation actuelle seule (sans la production).
func _reserves_texte() -> String:
    var res = Civilisation.ressources
    var pop = Civilisation.population
    var jour := _jour()
    var conso := {"eau": 0.0, "nourriture": 0.0, "bois": 0.0}
    for x in pop.habitants:
        var c: Dictionary = res.CONSO_ENFANT if pop.age(x, jour) < 14 else res.CONSO_ADULTE
        for r in conso:
            conso[r] += float(c[r])
    var l: PackedStringArray = []
    for r in ["eau", "bois"]:
        if conso[r] > 0.0:
            l.append("%s : %d jours sans production" % [r, int(float(res.stocks[r]) / conso[r])])
    return "Réserves : " + ", ".join(l) + "."

# Prévient (sans interdire) si l'on vide un poste vital.
func _alerte() -> String:
    var pop = Civilisation.population
    var ancien: String = habitant["metier"]
    if ancien in ["porteur d'eau", "cultivateur"] and pop.nombre(ancien) <= 1:
        return "ATTENTION : %s est le dernier %s du clan. Si vous confirmez, plus personne ne fera ce travail." % [habitant["prenom"], ancien]
    return ""

func _confirmer() -> void:
    if choix == "":
        return
    var pop = Civilisation.population
    var ancien: String = habitant["metier"]
    var avant_a: int = pop.nombre(ancien)
    var avant_n: int = pop.nombre(choix)
    var raison: String = pop.affecter(habitant, choix, _jour())
    if raison != "":
        avis.text = raison
        return
    _bilan = "Fait : %s est maintenant %s, protégé %d jours. %s : %d → %d ; %s : %d → %d." % [habitant["prenom"], choix, pop.PROTECTION_JOURS, ancien, avant_a, pop.nombre(ancien), choix, avant_n, pop.nombre(choix)]
    choix = ""
    remplir()
