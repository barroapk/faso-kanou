extends RefCounted

signal nouveau_jour
signal nouveau_mois
signal nouvelle_annee

const JOURS_PAR_MOIS := 30
const MOIS_PAR_AN := 12
const SECONDES_PAR_JOUR := 1.6
const VITESSES := [0.0, 1.0, 3.0, 8.0]
const NOMS_MOIS := ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]

var jour_total := 0
var vitesse := 1
var _cumul := 0.0

func avancer(delta: float) -> void:
    if vitesse == 0:
        return
    _cumul += delta * VITESSES[vitesse]
    while _cumul >= SECONDES_PAR_JOUR:
        _cumul -= SECONDES_PAR_JOUR
        _passer_un_jour()

func _passer_un_jour() -> void:
    jour_total += 1
    nouveau_jour.emit()
    if jour_total % JOURS_PAR_MOIS == 0:
        nouveau_mois.emit()
        if jour_total % (JOURS_PAR_MOIS * MOIS_PAR_AN) == 0:
            nouvelle_annee.emit()

func jour() -> int:
    return jour_total % JOURS_PAR_MOIS + 1

func mois() -> int:
    return (jour_total / JOURS_PAR_MOIS) % MOIS_PAR_AN

func annee() -> int:
    return jour_total / (JOURS_PAR_MOIS * MOIS_PAR_AN) + 1

func saison_des_pluies() -> bool:
    var m := mois()
    return m >= 5 and m <= 9

func texte() -> String:
    var saison := "saison des pluies" if saison_des_pluies() else "saison sèche"
    return "%d %s, an %d · %s" % [jour(), NOMS_MOIS[mois()], annee(), saison]

func vers_dict() -> Dictionary:
    return {"jour_total": jour_total, "vitesse": vitesse}

func depuis_dict(d: Dictionary) -> void:
    jour_total = int(d.get("jour_total", 0))
    vitesse = int(d.get("vitesse", 1))
