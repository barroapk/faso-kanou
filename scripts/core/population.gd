extends RefCounted

signal naissance(habitant)
signal deces(habitant)

const JOURS_PAR_AN := 360
const PRENOMS_H := ["Ousmane", "Issa", "Adama", "Moussa", "Salif", "Karim", "Boukary", "Noaga", "Idrissa", "Seydou"]
const PRENOMS_F := ["Aminata", "Fatimata", "Mariam", "Awa", "Salimata", "Rasmata", "Zalissa", "Assita", "Kadiatou", "Bintou"]

var habitants: Array = []
var prochain_id := 1
var rng := RandomNumberGenerator.new()

func creer_clan_initial(jour: int) -> void:
    rng.seed = 2026
    _ajouter("Ousmane", "Ouédraogo", "H", 35, 1, "chef", jour)
    _ajouter("Aminata", "Ouédraogo", "F", 30, 1, "cueilleuse", jour)
    _ajouter("Issa", "Ouédraogo", "H", 8, 1, "enfant", jour)
    _ajouter("Awa", "Ouédraogo", "F", 5, 1, "enfant", jour)
    _ajouter("Adama", "Kaboré", "H", 28, 2, "chasseur", jour)
    _ajouter("Mariam", "Kaboré", "F", 24, 2, "cueilleuse", jour)
    _ajouter("Salif", "Kaboré", "H", 2, 2, "enfant", jour)
    _ajouter("Boukary", "Zongo", "H", 26, 3, "bâtisseur", jour)
    _ajouter("Fatimata", "Zongo", "F", 22, 3, "porteuse d'eau", jour)
    _ajouter("Tenga", "Zongo", "H", 58, 3, "ancien", jour)

func _ajouter(prenom: String, nom: String, sexe: String, age_ans: int, famille: int, metier: String, jour: int, decaler := true) -> Dictionary:
    var ecart := rng.randi_range(0, JOURS_PAR_AN - 1) if decaler else 0
    var h := {
        "id": prochain_id,
        "prenom": prenom,
        "nom": nom,
        "sexe": sexe,
        "naissance": jour - age_ans * JOURS_PAR_AN - ecart,
        "famille": famille,
        "metier": metier,
        "sante": 100,
    }
    prochain_id += 1
    habitants.append(h)
    return h

func age(h: Dictionary, jour: int) -> int:
    return int((jour - int(h["naissance"])) / JOURS_PAR_AN)

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
            nes.append([f, pere["nom"]])

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
        var bebe := _ajouter(liste[rng.randi() % liste.size()], n[1], sexe, 0, n[0], "enfant", jour, false)
        naissance.emit(bebe)

    for h in habitants:
        if h["metier"] == "enfant" and age(h, jour) >= 14:
            h["metier"] = "sans métier"

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
        if h["sante"] == 0:
            morts.append(h)
    for h in morts:
        habitants.erase(h)
        deces.emit(h)
