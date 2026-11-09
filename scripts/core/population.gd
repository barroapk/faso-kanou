extends RefCounted

signal naissance(habitant)
signal deces(habitant)

const JOURS_PAR_AN := 360
const AGE_ADULTE := 14
const PRENOMS_H := ["Ousmane", "Issa", "Adama", "Moussa", "Salif", "Karim", "Boukary", "Noaga", "Idrissa", "Seydou"]
const PRENOMS_F := ["Aminata", "Fatimata", "Mariam", "Awa", "Salimata", "Rasmata", "Zalissa", "Assita", "Kadiatou", "Bintou"]
const FEMININ := {"chasseur": "chasseuse", "cueilleur": "cueilleuse", "porteur d'eau": "porteuse d'eau", "bâtisseur": "bâtisseuse"}
const METIERS_CHOISIS := ["chasseur", "cueilleur", "porteur d'eau", "bâtisseur", "sans métier"]

var habitants: Array = []
var prochain_id := 1
var postes := {"chasseur": 1, "cueilleur": 2, "porteur d'eau": 1, "bâtisseur": 1}
var rng := RandomNumberGenerator.new()

func creer_clan_initial(jour: int) -> void:
    rng.seed = 2026
    _ajouter("Ousmane", "Ouédraogo", "H", 35, 1, "chef", jour)
    _ajouter("Aminata", "Ouédraogo", "F", 30, 1, "cueilleur", jour)
    _ajouter("Issa", "Ouédraogo", "H", 8, 1, "enfant", jour, true, "chasseur")
    _ajouter("Awa", "Ouédraogo", "F", 5, 1, "enfant", jour, true, "cueilleur")
    _ajouter("Adama", "Kaboré", "H", 28, 2, "chasseur", jour)
    _ajouter("Mariam", "Kaboré", "F", 24, 2, "cueilleur", jour)
    _ajouter("Salif", "Kaboré", "H", 2, 2, "enfant", jour, true, "chasseur")
    _ajouter("Boukary", "Zongo", "H", 26, 3, "bâtisseur", jour)
    _ajouter("Fatimata", "Zongo", "F", 22, 3, "porteur d'eau", jour)
    _ajouter("Tenga", "Zongo", "H", 58, 3, "ancien", jour)

func _ajouter(prenom: String, nom: String, sexe: String, age_ans: int, famille: int, metier: String, jour: int, decaler := true, initie := "") -> Dictionary:
    var ecart := rng.randi_range(0, JOURS_PAR_AN - 1) if decaler else 0
    var h := {
        "id": prochain_id,
        "prenom": prenom,
        "nom": nom,
        "sexe": sexe,
        "naissance": jour - age_ans * JOURS_PAR_AN - ecart,
        "famille": famille,
        "metier": metier,
        "initie": initie,
        "sante": 100,
        "competence": float(clampi(age_ans * 2, 0, 70)),
    }
    prochain_id += 1
    habitants.append(h)
    return h

func age(h: Dictionary, jour: int) -> int:
    return int((jour - int(h["naissance"])) / JOURS_PAR_AN)

func nombre(m: String) -> int:
    var n := 0
    for h in habitants:
        if h["metier"] == m:
            n += 1
    return n

func mois_passe(jour: int, peut_naitre := true) -> void:
    var nes := []
    var familles := {}
    for h in habitants:
        familles[h["famille"]] = true
    for f in familles.keys():
        var mere = null
        var pere = null
        var plus_jeune := 999
        for h in habitants:
            if h["famille"] != f:
                continue
            var a := age(h, jour)
            if h["sexe"] == "F" and a >= 18 and a <= 42 and mere == null:
                mere = h
            elif h["sexe"] == "H" and a >= 18 and a <= 60 and pere == null:
                pere = h
            if h["metier"] == "enfant":
                plus_jeune = mini(plus_jeune, a)
        if peut_naitre and mere != null and pere != null and plus_jeune >= 2 and rng.randf() < 1.0 / 30.0:
            nes.append([f, pere, mere])

    var morts := []
    for h in habitants:
        var a := age(h, jour)
        var risque := 0.0
        if a < 1:
            risque = 0.003
        elif a >= 55:
            risque = (a - 50) * 0.0008
        if rng.randf() < risque:
            morts.append(h)
    for h in morts:
        habitants.erase(h)
        deces.emit(h)

    for n in nes:
        var sexe := "H" if rng.randf() < 0.5 else "F"
        var liste: Array = PRENOMS_H if sexe == "H" else PRENOMS_F
        var parent: Dictionary = n[1] if sexe == "H" else n[2]
        var initie: String = parent["metier"] if postes.has(parent["metier"]) else ""
        var bebe := _ajouter(liste[rng.randi() % liste.size()], n[1]["nom"], sexe, 0, n[0], "enfant", jour, false, initie)
        naissance.emit(bebe)

    for h in habitants:
        if h["metier"] == "enfant" and age(h, jour) >= AGE_ADULTE:
            h["metier"] = "sans métier"
            h["competence"] = 25.0 if h.get("initie", "") != "" else 10.0

func repartir(jour: int) -> void:
    for m in postes:
        var travailleurs := []
        for h in habitants:
            if h["metier"] == m:
                travailleurs.append(h)
        travailleurs.sort_custom(func(a, b): return float(a["competence"]) > float(b["competence"]))
        while travailleurs.size() > int(postes[m]):
            var h = travailleurs.pop_back()
            h["metier"] = "sans métier"
    for m in postes:
        var manque := int(postes[m]) - nombre(m)
        while manque > 0:
            var candidat = _meilleur_candidat(m, jour)
            if candidat == null:
                break
            if candidat.get("initie", "") != m:
                candidat["competence"] = float(candidat["competence"]) * 0.5
            candidat["metier"] = m
            manque -= 1

func _meilleur_candidat(m: String, jour: int):
    var meilleur = null
    var score_max := -1.0
    for h in habitants:
        if h["metier"] != "sans métier" or age(h, jour) < AGE_ADULTE:
            continue
        var score := float(h["competence"]) + (100.0 if h.get("initie", "") == m else 0.0)
        if score > score_max:
            score_max = score
            meilleur = h
    return meilleur

func changer_postes(m: String, delta: int, jour: int) -> void:
    postes[m] = maxi(0, int(postes[m]) + delta)
    repartir(jour)

func jour_passe(faim: bool, soif: bool) -> void:
    var morts := []
    for h in habitants:
        var s := int(h["sante"])
        if soif:
            s -= 4
        elif faim:
            s -= 2
        else:
            s += 1
        h["sante"] = clampi(s, 0, 100)
        if h["metier"] != "enfant" and h["metier"] != "ancien": h["competence"] = minf(float(h["competence"]) + 0.02, 100.0)
        if h["sante"] == 0:
            morts.append(h)
    for h in morts:
        habitants.erase(h)
        deces.emit(h)

func metiers_choisis() -> Array:
    return METIERS_CHOISIS

func nom_metier(h: Dictionary) -> String:
    var m: String = h["metier"]
    return FEMININ.get(m, m) if h["sexe"] == "F" else m

func peut_changer(h: Dictionary, jour: int) -> bool:
    return age(h, jour) >= AGE_ADULTE and h["metier"] != "chef"

func changer_metier(h: Dictionary, m: String) -> void:
    var ancien: String = h["metier"]
    if ancien == m:
        return
    if postes.has(ancien):
        postes[ancien] = maxi(0, int(postes[ancien]) - 1)
    if postes.has(m):
        postes[m] = int(postes[m]) + 1
    h["metier"] = m
    h["competence"] = float(h["competence"]) * 0.5

func vers_dict() -> Dictionary:
    return {"habitants": habitants, "prochain_id": prochain_id, "postes": postes, "graine": str(rng.seed), "etat": str(rng.state)}

func depuis_dict(d: Dictionary) -> void:
    habitants = []
    for h in d.get("habitants", []):
        for cle in ["id", "naissance", "famille", "sante"]:
            h[cle] = int(h[cle])
        h["competence"] = float(h.get("competence", 50.0))
        h["metier"] = _migrer_metier(h["metier"])
        h["initie"] = _migrer_metier(h.get("initie", ""))
        habitants.append(h)
    prochain_id = int(d.get("prochain_id", 1))
    var p: Dictionary = d.get("postes", {})
    for m in postes:
        postes[m] = int(p.get(m, nombre(m)))
    rng.seed = int(d.get("graine", "2026"))
    rng.state = int(d.get("etat", "0"))

func _migrer_metier(m: String) -> String:
    match m:
        "cueilleuse":
            return "cueilleur"
        "porteuse d'eau":
            return "porteur d'eau"
    return m
