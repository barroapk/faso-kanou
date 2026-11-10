extends RefCounted

# Clôtures (v0.3.19 T3) : sécurité et décor, au libre choix du joueur.
# Une parcelle acquise n'a PAS besoin d'être clôturée. Le joueur décide quoi
# entourer (le village, un champ) et avec quoi. Une clôture a des passages
# (portes) : elle peut fermer un chemin ou en ouvrir un. Plus tard (T4), une
# route qui traverse une clôture devra passer par une porte.
# Chaque niveau coûte des matériaux et du travail (par mètre de clôture), et
# s'use : sans entretien annuel, il perd de sa protection.
# Effets aujourd'hui : un champ clôturé perd moins de récolte (bêtes, oiseaux,
# voleurs) ; l'enceinte du village donne la sécurité du village (utilisée
# ensuite pour les migrations, les intrusions et les conflits).
# Une clôture ralentit et filtre ; elle n'arrête jamais tout.

signal evenement(texte)

const NIVEAUX := {
    "haie": {"nom": "Haie d'épineux", "cout_m": {"bois": 0.3}, "travail_m": 0.02, "protection": 0.3},
    "palissade": {"nom": "Palissade en bois", "cout_m": {"bois": 2.0}, "travail_m": 0.05, "protection": 0.5},
    "banco": {"nom": "Mur en banco", "cout_m": {"argile": 6.0}, "travail_m": 0.10, "protection": 0.7},
    "pierre": {"nom": "Mur en pierre", "cout_m": {"pierre": 8.0}, "travail_m": 0.15, "protection": 0.85},
}
const ORDRE := ["haie", "palissade", "banco", "pierre"]
const USURE_AN := 0.1            # -10 % d'état par an sans entretien
const ENTRETIEN := 0.1           # entretien annuel : 10 % du coût de départ
const COUT_PORTE := {"bois": 10.0}
const PERTE_CHAMP := 0.12        # récolte perdue par un champ ouvert (bêtes, oiseaux, vols)

var enceintes := {}              # cible ("village" ou "champ_3") -> {niveau, portes, etat, longueur, travail_restant}

# Longueur à clôturer (m) : le tour du village ou d'un champ carré.
func longueur(cible: String, agriculture, construction) -> float:
    if cible == "village":
        var huttes: float = construction.nombre("hutte") + construction.nombre("grenier")
        return 2.0 * PI * (20.0 + 5.0 * huttes)
    var c: Dictionary = agriculture.champ(int(cible.trim_prefix("champ_")))
    if c.is_empty():
        return 0.0
    return 4.0 * sqrt(float(c["ha"]) * 10000.0)

func cout(niveau: String, metres: float) -> Dictionary:
    var c := {}
    for r in NIVEAUX[niveau]["cout_m"]:
        c[r] = float(NIVEAUX[niveau]["cout_m"][r]) * metres
    return c

func texte_cout(c: Dictionary) -> String:
    var t: PackedStringArray = []
    for r in c:
        t.append("%d %s" % [int(c[r]), r])
    return ", ".join(t)

func construire(cible: String, niveau: String, agriculture, construction, res) -> String:
    var m := longueur(cible, agriculture, construction)
    if m <= 0.0:
        return "Rien à clôturer ici."
    var c := cout(niveau, m)
    for r in c:
        if res.quantite(r) < c[r]:
            return "Il faut %s." % texte_cout(c)
    for r in c:
        res.retirer(r, c[r], "construction")
    var portes := int(enceintes.get(cible, {}).get("portes", 1))
    enceintes[cible] = {"niveau": niveau, "portes": portes, "etat": 1.0, "longueur": m,
        "travail_restant": float(NIVEAUX[niveau]["travail_m"]) * m, "cout": c}
    evenement.emit("Clôture commencée : %s autour de %s (%d m)." % [NIVEAUX[niveau]["nom"], _nom(cible), int(m)])
    return ""

# Ajouter un passage (porte) ou en fermer un.
func changer_portes(cible: String, delta: int, res) -> String:
    if not enceintes.has(cible):
        return "Il n'y a pas de clôture ici."
    var e: Dictionary = enceintes[cible]
    if delta > 0:
        for r in COUT_PORTE:
            if res.quantite(r) < COUT_PORTE[r]:
                return "Une porte coûte %s." % texte_cout(COUT_PORTE)
        for r in COUT_PORTE:
            res.retirer(r, COUT_PORTE[r], "construction")
    e["portes"] = maxi(0, int(e["portes"]) + delta)
    return ""

func _nom(cible: String) -> String:
    return "le village" if cible == "village" else "le champ %s" % cible.trim_prefix("champ_")

# Protection réelle (0 à 0,85) : 0 tant que la clôture n'est pas finie.
func protection(cible: String) -> float:
    if not enceintes.has(cible):
        return 0.0
    var e: Dictionary = enceintes[cible]
    if float(e["travail_restant"]) > 0.0:
        return 0.0
    var p := float(NIVEAUX[e["niveau"]]["protection"]) * float(e["etat"])
    return p * (1.0 - 0.05 * maxi(0, int(e["portes"]) - 1))   # chaque porte de plus est un point faible

# Part de récolte perdue par un champ (bêtes, oiseaux, vols).
func perte_champ(id_champ: int) -> float:
    return PERTE_CHAMP * (1.0 - protection("champ_%d" % id_champ))

# Chaque jour : les bâtisseurs libres (pas de chantier) montent les clôtures.
func jour_passe(travail: float) -> void:
    for cible in enceintes:
        var e: Dictionary = enceintes[cible]
        if float(e["travail_restant"]) <= 0.0:
            continue
        var fait := minf(travail, float(e["travail_restant"]))
        e["travail_restant"] = float(e["travail_restant"]) - fait
        travail -= fait
        if float(e["travail_restant"]) <= 0.0:
            evenement.emit("Clôture terminée autour de %s." % _nom(cible))
        if travail <= 0.0:
            return

# Chaque mois : usure ; entretien payé une fois par an si le clan le peut.
func mois_passe(res, mois: int) -> void:
    for cible in enceintes:
        var e: Dictionary = enceintes[cible]
        e["etat"] = maxf(0.2, float(e["etat"]) - USURE_AN / 12.0)
        if mois == 0:
            var ok := true
            for r in e["cout"]:
                if res.quantite(r) < float(e["cout"][r]) * ENTRETIEN:
                    ok = false
            if ok:
                for r in e["cout"]:
                    res.retirer(r, float(e["cout"][r]) * ENTRETIEN, "entretien")
                e["etat"] = 1.0

func vers_dict() -> Dictionary:
    return {"enceintes": enceintes}

func depuis_dict(d: Dictionary) -> void:
    enceintes = d.get("enceintes", {})
