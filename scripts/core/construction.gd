extends RefCounted

signal evenement(texte)

var definitions := {}
var connaissances   # decouvertes.gd : certains bâtiments demandent une découverte
var batiments: Array = []
var chantiers: Array = []

# ---------- Danger des greniers (cadre v0.4, règles 1, 2, 5) ----------
const ETAT_FRAGILE := 40          # sous ce niveau : fragile, stockage réduit de moitié
const ETAT_USE := 70              # sous ce niveau : usé (aucun effet, simple signal)
const PART_FRAGILE := 0.5
const PART_REPARATION := 0.3      # part du coût et du travail de construction
const ETAT_APRES_REPARATION := 20
const ORDRE_DEFAUT := ["grenier", "jarres", "hutte"]
var ordre_entretien: Array = []   # types dans l'ordre choisi par le joueur ; vide = ORDRE_DEFAUT

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
        var part := PART_FRAGILE if int(b["etat"]) < ETAT_FRAGILE and cle.begins_with("stock_") else 1.0
        total += float(niv["effet"].get(cle, 0.0)) * part
    return total

# Bâtiment possible seulement si sa découverte est faite (fourneau, forge...).
func disponible(type: String) -> bool:
    var dec: String = definitions.get(type, {}).get("decouverte", "")
    return dec == "" or (connaissances != null and connaissances.connait(dec))

func _quantite(ressources, r: String) -> float:
    if ressources.has_method("quantite_commune"):
        return ressources.quantite_commune(r)
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
    if bool(c.get("reparation", false)):
        var br: Dictionary = batiments[int(c["index"])]
        br["etat"] = ETAT_APRES_REPARATION
        evenement.emit("Réparation terminée : %s (état %d, fragile : à entretenir)." % [definitions[br["type"]]["nom"], ETAT_APRES_REPARATION])
    elif int(c["index"]) < 0:
        batiments.append({"type": c["type"], "niveau": 1, "etat": 100})
        evenement.emit("Construction terminée : %s" % nom)
    else:
        var b: Dictionary = batiments[int(c["index"])]
        b["niveau"] = int(c["niveau"])
        b["etat"] = 100
        evenement.emit("Amélioration terminée : %s" % nom)

# Règle 1 : le dernier jour du mois, chaque bâtiment est payé en entier ou pas du tout,
# dans l'ordre d'entretien ; un bâtiment suspendu ou impayé perd 20 ; un bâtiment en
# ruine ne coûte rien et ne remonte plus seul (il faut une réparation, règle 5).
func mois_passe(ressources) -> void:
    for i in ordre_paiement():
        var b: Dictionary = batiments[i]
        var avant := int(b["etat"])
        if avant <= 0:
            continue
        var entretien: Dictionary = _niveau(b["type"], int(b["niveau"]))["entretien"]
        if not bool(b.get("suspendu", false)) and peut_payer(entretien, ressources):
            _payer(ressources, entretien, "entretien")
            b["etat"] = mini(100, avant + 10)
        else:
            b["etat"] = maxi(0, avant - 20)
        var nom: String = definitions[b["type"]]["nom"]
        if avant > 0 and int(b["etat"]) == 0:
            evenement.emit("En ruine faute d'entretien : %s. Il ne stocke plus rien ; il faut le réparer (Construire)." % nom)
        elif avant >= ETAT_FRAGILE and int(b["etat"]) < ETAT_FRAGILE:
            evenement.emit("ALERTE : %s fragile (état %d) : son stockage tombe de moitié. Ajoutez un bâtisseur ou mettez-le en tête de l'entretien." % [nom, int(b["etat"])])

func palier(etat: int) -> String:
    if etat <= 0:
        return "En ruine"
    if etat < ETAT_FRAGILE:
        return "Fragile"
    if etat < ETAT_USE:
        return "Usé"
    return "Bon"

func ordre_types() -> Array:
    var l: Array = ordre_entretien.duplicate() if not ordre_entretien.is_empty() else ORDRE_DEFAUT.duplicate()
    for t in definitions:
        if not l.has(t):
            l.append(t)
    return l

# Indices des bâtiments dans l'ordre de paiement (par type, puis dans l'ordre de construction).
func ordre_paiement() -> Array:
    var res: Array = []
    for t in ordre_types():
        for i in batiments.size():
            if batiments[i]["type"] == t:
                res.append(i)
    return res

# Monter (-1) ou descendre (+1) un type dans l'ordre d'entretien.
func deplacer_type(type: String, sens: int) -> void:
    var l := ordre_types()
    var i := l.find(type)
    var j := i + sens
    if i < 0 or j < 0 or j >= l.size():
        return
    l[i] = l[j]
    l[j] = type
    ordre_entretien = l

func basculer_suspension(index: int) -> void:
    var b: Dictionary = batiments[index]
    if bool(b.get("suspendu", false)):
        b.erase("suspendu")
    else:
        b["suspendu"] = true

# Bois demandé par l'entretien du mois (bâtiments ni en ruine ni suspendus).
func entretien_mois(r := "bois") -> float:
    var t := 0.0
    for b in batiments:
        if int(b["etat"]) <= 0 or bool(b.get("suspendu", false)):
            continue
        t += float(_niveau(b["type"], int(b["niveau"]))["entretien"].get(r, 0.0))
    return t

# Règle 4 : prévision (ce n'est pas une garantie : le paiement se fait sur le stock réel).
func prevision_entretien(ressources, jours_restants: int) -> Dictionary:
    var e := entretien_mois()
    var moy := 0.0
    var h: Array = ressources.hist_prod_bois
    for q in h:
        moy += float(q)
    moy = moy / h.size() if not h.is_empty() else 0.0
    var prevu: float = float(ressources.stocks["bois"]) + (moy - float(ressources.bois_brule_jour)) * jours_restants
    # Deux déficits distincts : l'entretien (ce qui manquera pour le payer, jamais plus que
    # l'entretien lui-même) et le bois en général (feux des habitants), signalé à part.
    var manque_entretien := clampf(e - maxf(prevu, 0.0), 0.0, e)
    return {"entretien": e, "prevu": prevu, "manque": manque_entretien, "manque_general": maxf(0.0, -prevu)}

# Règle 5 : coût d'une réparation (30 % du coût et du travail du niveau).
func cout_reparation(index: int) -> Dictionary:
    var b: Dictionary = batiments[index]
    var niv := _niveau(b["type"], int(b["niveau"]))
    var c := {}
    for r in niv["cout"]:
        c[r] = ceilf(float(niv["cout"][r]) * PART_REPARATION)
    return {"cout": c, "travail": ceilf(float(niv["travail"]) * PART_REPARATION)}

func en_reparation(index: int) -> bool:
    for c in chantiers:
        if bool(c.get("reparation", false)) and int(c["index"]) == index:
            return true
    return false

# Lance la réparation d'un bâtiment en ruine par la file des chantiers. "" si fait, sinon la raison.
func lancer_reparation(index: int, ressources) -> String:
    if index < 0 or index >= batiments.size():
        return "Bâtiment inconnu."
    var b: Dictionary = batiments[index]
    if int(b["etat"]) > 0:
        return "Ce bâtiment n'est pas en ruine."
    if en_reparation(index):
        return "Réparation déjà en cours."
    var rep := cout_reparation(index)
    if not peut_payer(rep["cout"], ressources):
        return "Pas assez de bois (%s)." % texte_cout(rep["cout"])
    _payer(ressources, rep["cout"], "entretien")
    chantiers.append({"type": b["type"], "index": index, "niveau": int(b["niveau"]), "reste": float(rep["travail"]), "reparation": true})
    return ""

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

# Premier bâtiment en ruine non encore en réparation, dans l'ordre d'entretien (-1 : aucun).
func premiere_ruine() -> int:
    for i in ordre_paiement():
        if int(batiments[i]["etat"]) <= 0 and not en_reparation(i):
            return i
    return -1

# Règle 6 (clans de l'ordinateur) : une réparation à la fois, greniers d'abord, seulement
# si le bois dépasse l'entretien du mois plus le coût, et hors crise immédiate.
# crise : {"bloque": crise indépendante de la ruine, "causes": ressources en crise faute de capacité}.
func reparation_auto(ressources, crise: Dictionary) -> bool:
    if bool(crise.get("bloque", false)):
        return false
    for c in chantiers:
        if bool(c.get("reparation", false)):
            return false
    var causes: Array = crise.get("causes", [])
    var i := -1
    for j in ordre_paiement():
        if int(batiments[j]["etat"]) > 0 or en_reparation(j):
            continue
        if causes.is_empty() or _stocke_une(j, causes):
            i = j
            break
    if i < 0:
        return false
    var cout: Dictionary = cout_reparation(i)["cout"]
    if _quantite(ressources, "bois") <= entretien_mois() + float(cout.get("bois", 0.0)):
        return false
    if lancer_reparation(i, ressources) != "":
        return false
    if not causes.is_empty():
        evenement.emit("Réparation lancée malgré la crise (capacité perdue : %s) : %s." % [", ".join(PackedStringArray(causes)), definitions[batiments[i]["type"]]["nom"]])
    return true

# Le bâtiment stocke-t-il une des ressources en crise ?
func _stocke_une(index: int, ressources_crise: Array) -> bool:
    var b: Dictionary = batiments[index]
    var effet: Dictionary = _niveau(b["type"], int(b["niveau"]))["effet"]
    for r in ressources_crise:
        if float(effet.get("stock_" + str(r), 0.0)) > 0.0:
            return true
    return false

func vers_dict() -> Dictionary:
    return {"batiments": batiments, "chantiers": chantiers, "ordre_entretien": ordre_entretien}

func depuis_dict(d: Dictionary) -> void:
    batiments = []
    for b in d.get("batiments", []):
        var nb := {"type": b["type"], "niveau": int(b["niveau"]), "etat": int(b["etat"])}
        if bool(b.get("suspendu", false)):
            nb["suspendu"] = true
        batiments.append(nb)
    ordre_entretien = []
    for t in d.get("ordre_entretien", []):
        ordre_entretien.append(str(t))
    chantiers = []
    for c in d.get("chantiers", []):
        var nc := {"type": c["type"], "index": int(c["index"]), "niveau": int(c["niveau"]), "reste": float(c["reste"])}
        if bool(c.get("reparation", false)):
            nc["reparation"] = true
        chantiers.append(nc)
    if batiments.is_empty():
        etat_initial()
