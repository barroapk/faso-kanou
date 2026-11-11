extends RefCounted

# Mémoire historique du clan (v0.3.31).
# Le registre OBSERVE les modules (leurs messages et signaux) et garde
# seulement les événements qui marquent l'histoire. Il ne décide rien.
# Chaque événement : {id, cat, jour, an, texte}. Sauvegardé, jamais effacé
# au rechargement. Au-delà de 500, on retire d'abord les plus anciens
# événements secondaires ; fondation, époques et héros restent.

signal evenement(texte)

const MAX := 500
const MAJEURES := ["Fondation", "Époques", "Héros"]
# [module, début (ou contenu) du message, catégorie, une_fois]
# une_fois = true : on ne garde que la première fois (ex. premier port).
const REGLES := [
    ["decouvertes", "Découverte (", "Découvertes", true],
    ["decouvertes", "Savoir perdu", "Découvertes", false],
    ["expeditions", "Exploration : ", "Exploration", true],
    ["expeditions", "Tempête en mer", "Catastrophes", false],
    ["expeditions", "Le bateau de l'expédition n'est pas revenu", "Catastrophes", false],
    ["expeditions", "Le bateau disparu est retrouvé", "Catastrophes", false],
    ["expeditions", "Le bateau est perdu", "Catastrophes", false],
    ["diplomatie", "Relations joueur", "Diplomatie", false],
    ["construction", "Construction terminée", "Construction", true],
    ["defis", "NOUVELLE ÉPOQUE", "Époques", true],
    ["defis", "entre dans l'époque", "Époques", true],
    ["defis", "Alliance scellée", "Diplomatie", false],
    ["defis", "DÉCISION : Les pluies ne viennent pas", "Catastrophes", false],
    ["defis", "Marché conclu avec le marchand étranger", "Économie", true],
    ["rival", "Nous avons devancé", "Diplomatie", false],
    ["rival", "a gagné son défi", "Diplomatie", false],
    ["heros", "", "Héros", false],
    ["gisements", "Prospection réussie", "Construction", true],
    ["gisements", " ouvert.", "Construction", true],
    ["flotte", "mis à l'eau", "Construction", true],
    ["raids", "Raid de ", "Conflits", false],
    ["raids", "Raid : accord", "Conflits", false],
    ["gouvernement", " est nommé ", "Politique", false],
    ["gouvernement", " est vacant", "Politique", false],
    ["gouvernement", "Le Premier ministre nomme ", "Politique", false],
    ["gouvernement", "Délégation ", "Politique", false],
    ["finances", "Finances : ", "Économie", false],
    ["institutions", "Institutions : ", "Politique", false],
    ["gouvernement", " est relevé de ses fonctions", "Politique", false],
    ["routes", " terminé.", "Construction", true],
]
const IGNORER := ["Fête des ancêtres"]

var registre: Array = []
var vus := {}                    # textes déjà gardés (règles une_fois)
var prochain_id := 1
var record := 10                 # population record annoncé (par dizaines)
var premier_enfant := false
var _C = null

func observer(C) -> void:
    _C = C
    var modules := {}
    for r in REGLES:
        modules[r[0]] = true
    for m in modules:
        var mod = C.get(m)
        if mod != null and mod.has_signal("evenement"):
            mod.evenement.connect(_message.bind(m))
    C.population.naissance.connect(_naissance)
    C.population.deces.connect(_deces)

func _message(texte: String, module: String) -> void:
    for x in IGNORER:
        if texte.find(x) >= 0:
            return
    for r in REGLES:
        if r[0] != module or (r[1] != "" and texte.find(r[1]) < 0):
            continue
        var t := texte.trim_prefix("DÉCISION : ").replace(" — ouvrez le conseil.", "")
        if texte.find("entre dans l'époque") >= 0 and not _clan_connu(texte):
            return
        if module == "defis" and texte.begins_with("DÉCISION : Les pluies"):
            t = "Sécheresse : les pluies ne viennent pas."
        if bool(r[3]):
            if vus.has(t):
                return
            vus[t] = true
        noter(r[2], t)
        return

# Un clan inconnu du joueur n'entre pas dans son histoire (v0.3.32).
func _clan_connu(texte: String) -> bool:
    for v in _C.voisins:
        if texte.find(v.nom + " ") >= 0:
            return int(_C.expeditions.connues.get(v.agriculture.ile_id, 0)) >= 1
    return false
func _naissance(h: Dictionary) -> void:
    if not premier_enfant:
        premier_enfant = true
        noter("Démographie", "Premier enfant né sur l'île : %s." % h.get("prenom", "?"))

func _deces(h: Dictionary) -> void:
    if h.get("metier", "") == "chef":
        noter("Démographie", "Mort du Premier ministre %s %s." % [h.get("prenom", "?"), h.get("nom", "")])

func noter(cat: String, texte: String) -> void:
    if _C == null:
        return
    var jour: int = _C.temps.jour_total
    registre.append({"id": prochain_id, "cat": cat, "jour": jour, "an": _C.temps.annee(), "texte": texte})
    prochain_id += 1
    if registre.size() > MAX:
        for i in registre.size():
            if not registre[i]["cat"] in MAJEURES:
                registre.remove_at(i)
                break
        if registre.size() > MAX:
            for i in registre.size():
                if registre[i]["cat"] != "Fondation":
                    registre.remove_at(i)
                    break

func mois_passe(C) -> void:
    if not registre.any(func(e): return e["cat"] == "Fondation"):
        registre.push_front({"id": 0, "cat": "Fondation", "jour": 0, "an": 1, "texte": "Fondation : le clan s'installe sur %s." % C.agriculture.ile.get("nom", "son île")})
    var n: int = C.population.habitants.size()
    if n >= record + 10:
        record = (n / 10) * 10
        noter("Démographie", "Le clan compte désormais %d habitants." % n)

# Du plus récent au plus ancien.
func texte(n := 15) -> String:
    var l: PackedStringArray = []
    for i in range(registre.size() - 1, maxi(-1, registre.size() - 1 - n), -1):
        var e: Dictionary = registre[i]
        l.append("An %d · %s — %s" % [int(e["an"]), e["cat"], e["texte"]])
    if l.is_empty():
        return "Histoire du clan : rien encore."
    return "Histoire du clan (%d événements) :\n%s" % [registre.size(), "\n".join(l)]

func vers_dict() -> Dictionary:
    return {"registre": registre, "vus": vus, "id": prochain_id, "record": record, "premier_enfant": premier_enfant}

func depuis_dict(d: Dictionary) -> void:
    registre = d.get("registre", [])
    vus = d.get("vus", {})
    prochain_id = int(d.get("id", 1))
    record = int(d.get("record", 10))
    premier_enfant = bool(d.get("premier_enfant", false))
