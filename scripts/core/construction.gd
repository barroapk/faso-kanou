extends RefCounted

signal evenement(texte)

var definitions := {}
var connaissances   # decouvertes.gd : certains bâtiments demandent une découverte
var batiments: Array = []
var chantiers: Array = []

func _init() -> void:
    var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/batiments.json"))
    if typeof(d) == TYPE_DICTIONARY:
        definitions = d

func etat_initial() -> void:
    batiments = []
    chantiers = []
    for i in 4:
        batiments.append({"type": "hutte", "niveau": 1, "etat": 100})

func _niveau(type: String, niveau: int) -> Dictionary:
    return definitions[type]["niveaux"][niveau - 1]

func niveau_max(type: String) -> int:
    return definitions[type]["niveaux"].size()

func nombre(type: String) -> int:
    var n := 0
    for b in batiments:
        if b["type"] == type:
            n += 1
    return n

func effet_total(cle: String) -> float:
    var total := 0.0
    for b in batiments:
        if int(b["etat"]) <= 0:
            continue
        var niv := _niveau(b["type"], int(b["niveau"]))
        total += float(niv["effet"].get(cle, 0.0))
    return total

# Bâtiment possible seulement si sa découverte est faite (fourneau, forge...).
func disponible(type: String) -> bool:
    var dec: String = definitions.get(type, {}).get("decouverte", "")
    return dec == "" or (connaissances != null and connaissances.connait(dec))

func _quantite(ressources, r: String) -> float:
    if ressources.has_method("quantite"):
        return ressources.quantite(r)
    return float(ressources.stocks.get(r, 0.0))

func _payer(ressources, cout: Dictionary, motif := "construction") -> void:
    for r in cout:
        if ressources.has_method("retirer"):
            ressources.retirer(r, float(cout[r]), motif)
        else:
            ressources.stocks[r] -= float(cout[r])

func peut_payer(cout: Dictionary, ressources) -> bool:
    for r in cout:
        if _quantite(ressources, r) < float(cout[r]):
            return false
    return true

func texte_cout(cout: Dictionary) -> String:
    var morceaux: PackedStringArray = []
    for r in cout:
        morceaux.append("%d %s" % [int(cout[r]), r])
    return ", ".join(morceaux)

func index_a_ameliorer(type: String) -> int:
    var vises := {}
    for c in chantiers:
        vises[int(c["index"])] = true
    var meilleur := -1
    for i in batiments.size():
        var b: Dictionary = batiments[i]
        if b["type"] != type or vises.has(i) or int(b["niveau"]) >= niveau_max(type):
            continue
        if meilleur < 0 or int(b["niveau"]) < int(batiments[meilleur]["niveau"]):
            meilleur = i
    return meilleur

func lancer(type: String, index: int, ressources) -> bool:
    var niveau_cible := 1 if index < 0 else int(batiments[index]["niveau"]) + 1
    if niveau_cible > niveau_max(type):
        return false
    if not disponible(type):
        return false
    var niv := _niveau(type, niveau_cible)
    if not peut_payer(niv["cout"], ressources):
        return false
    _payer(ressources, niv["cout"])
    chantiers.append({"type": type, "index": index, "niveau": niveau_cible, "reste": float(niv["travail"])})
    return true

func jour_passe(travail: float) -> void:
    if chantiers.is_empty() or travail <= 0.0:
        return
    var c: Dictionary = chantiers[0]
    c["reste"] = float(c["reste"]) - travail
    if float(c["reste"]) > 0.0:
        return
    chantiers.pop_front()
    var nom: String = _niveau(c["type"], int(c["niveau"]))["nom"]
    if int(c["index"]) < 0:
        batiments.append({"type": c["type"], "niveau": 1, "etat": 100})
        evenement.emit("Construction terminée : %s" % nom)
    else:
        var b: Dictionary = batiments[int(c["index"])]
        b["niveau"] = int(c["niveau"])
        b["etat"] = 100
        evenement.emit("Amélioration terminée : %s" % nom)

func mois_passe(ressources) -> void:
    for b in batiments:
        var entretien: Dictionary = _niveau(b["type"], int(b["niveau"]))["entretien"]
        if peut_payer(entretien, ressources):
            _payer(ressources, entretien, "entretien")
            b["etat"] = mini(100, int(b["etat"]) + 10)
        else:
            var avant := int(b["etat"])
            b["etat"] = maxi(0, avant - 20)
            if avant > 0 and int(b["etat"]) == 0:
                evenement.emit("En ruine faute d'entretien : %s" % definitions[b["type"]]["nom"])

func texte_chantiers(travail: float) -> String:
    if chantiers.is_empty():
        return "Aucun chantier en cours."
    var lignes: PackedStringArray = []
    for i in chantiers.size():
        var c: Dictionary = chantiers[i]
        var nom: String = _niveau(c["type"], int(c["niveau"]))["nom"]
        if i == 0 and travail > 0.0:
            lignes.append("En cours : %s, encore %d jours" % [nom, ceili(float(c["reste"]) / travail)])
        elif i == 0:
            lignes.append("En cours : %s, arrêté (aucun bâtisseur, voir Travail)" % nom)
        else:
            lignes.append("En attente : %s" % nom)
    return "\n".join(lignes)

func vers_dict() -> Dictionary:
    return {"batiments": batiments, "chantiers": chantiers}

func depuis_dict(d: Dictionary) -> void:
    batiments = []
    for b in d.get("batiments", []):
        batiments.append({"type": b["type"], "niveau": int(b["niveau"]), "etat": int(b["etat"])})
    chantiers = []
    for c in d.get("chantiers", []):
        chantiers.append({"type": c["type"], "index": int(c["index"]), "niveau": int(c["niveau"]), "reste": float(c["reste"])})
    if batiments.is_empty():
        etat_initial()
