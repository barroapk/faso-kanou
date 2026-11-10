extends RefCounted

signal nouveau_jour
signal nouveau_mois
signal nouvelle_annee

const JOURS_PAR_MOIS := 30
const MOIS_PAR_AN := 12
const SECONDES_PAR_JOUR := 1.6
const VITESSES := [0.0, 1.0, 3.0, 8.0, 30.0, 100.0]
const NOMS_MOIS := ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]

var jour_total := 0
var vitesse := 1
var _cumul := 0.0
var annee_seche := -1         # année de sécheresse sur tout l'archipel (-1 = aucune)

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

func mois_de_pluie() -> bool:
    var m := mois()
    return m >= 5 and m <= 9

# Jour de pluie. Une année de sécheresse, il ne pleut qu'un jour sur trois.
func saison_des_pluies() -> bool:
    if not mois_de_pluie():
        return false
    if annee() == annee_seche:
        return jour_total % 3 == 0
    return true

func secheresse() -> bool:
    return annee() == annee_seche and mois_de_pluie()

func texte() -> String:
    var saison := "saison des pluies" if mois_de_pluie() else "saison sèche"
    if secheresse():
        saison += " (sécheresse)"
    return "%d %s, an %d · %s" % [jour(), NOMS_MOIS[mois()], annee(), saison]

func vers_dict() -> Dictionary:
    return {"jour_total": jour_total, "vitesse": vitesse, "annee_seche": annee_seche}

func depuis_dict(d: Dictionary) -> void:
    jour_total = int(d.get("jour_total", 0))
    vitesse = int(d.get("vitesse", 1))
    annee_seche = int(d.get("annee_seche", -1))
