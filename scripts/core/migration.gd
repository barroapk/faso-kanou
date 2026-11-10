extends RefCounted

# Migrations minimales (v0.3.x) : entre clans voisins et le clan du joueur.
#   Clan prospère (nourriture, eau, logement) -> des habitants d'autres clans viennent.
#   Clan pauvre (faim, soif, réserves vides, surpeuplement) -> des foyers partent.
# Rien n'est créé pour sauver le clan : sans prospérité, personne ne vient.
# Les arrivants sont de vraies personnes : nom, lignée, âge, origine.
# Plus tard : frontières, gardes, ports (décisions du joueur).

signal evenement(texte)

const ARRIVEES_AN_MAX := 0.5       # arrivées par an quand le clan est très attractif
const DEPARTS_AN_MAX := 1.5        # départs par an quand le clan est dans la misère
const PART_FAMILLES := 0.4         # part des arrivées qui sont des familles entières
const CLANS_VOISINS := [
    ["Sawadogo", "Yatenga"], ["Compaoré", "Ziniaré"], ["Ilboudo", "Boussé"],
    ["Traoré", "Bobo"], ["Diallo", "Djibo"], ["Sanou", "Banfora"],
    ["Konaté", "Dédougou"], ["Coulibaly", "Sikasso"], ["Nikiéma", "Koudougou"],
    ["Tapsoba", "Kaya"],
]

var actif := false   # désactivée par défaut (v0.3.x), voir cahier des charges
var arrivees := 0
var departs := 0
var prochaine_lignee := 100
var rng := RandomNumberGenerator.new()

func initialiser(graine: int) -> void:
    rng.seed = graine + 7919

# ---------- Mesures ----------

static func sante_moyenne(pop) -> float:
    if pop.habitants.is_empty():
        return 0.0
    var t := 0.0
    for h in pop.habitants:
        t += float(h["sante"])
    return t / pop.habitants.size()

# 0 à 1. Il faut à la fois de la place, des habitants en bonne santé
# (pas de faim ni de soif récente) et des réserves de nourriture.
func attractivite(pop, res, places: int) -> float:
    var a_l := 0.0
    if places >= 3:
        a_l = 1.0
    elif places >= 1:
        a_l = 0.5
    var a_s := clampf((sante_moyenne(pop) - 90.0) / 10.0, 0.0, 1.0)
    var jours_nourriture: float = res.stocks["nourriture"] / (maxi(1, pop.habitants.size()) * 0.8)
    var a_n := 0.5 + 0.5 * clampf(jours_nourriture / 60.0, 0.0, 1.0)
    return a_l * a_s * a_n

# 0 à 1. La misère se voit à la santé (faim, soif) et au surpeuplement,
# pas seulement à un stock bas un jour donné.
func misere(pop, res, places: int) -> float:
    var m := clampf((90.0 - sante_moyenne(pop)) / 30.0, 0.0, 1.0)
    if places < 0:
        m = maxf(m, 0.5)
    return m

# ---------- Mois ----------

func mois_passe(pop, res, cons, jour: int) -> void:
    if not actif or pop.habitants.is_empty():
        return
    var places: int = int(cons.effet_total("logement")) - pop.habitants.size() - pop.grossesses()
    var mis := misere(pop, res, places)
    if mis > 0.0 and rng.randf() < DEPARTS_AN_MAX / 12.0 * mis:
        _depart(pop, jour)
        return
    var attr := attractivite(pop, res, places)
    if attr > 0.0 and rng.randf() < ARRIVEES_AN_MAX / 12.0 * attr:
        _arrivee(pop, jour, places)

func _arrivee(pop, jour: int, places: int) -> void:
    var clan: Array = CLANS_VOISINS[rng.randi() % CLANS_VOISINS.size()]
    var lignee := prochaine_lignee
    prochaine_lignee += 1
    if rng.randf() < PART_FAMILLES and places >= 3:
        var age_h := rng.randi_range(22, 40)
        var age_f := clampi(age_h - rng.randi_range(0, 8), 18, 40)
        var mari: Dictionary = _personne(pop, "H", clan[0], lignee, age_h, jour)
        var femme: Dictionary = _personne(pop, "F", clan[0], lignee, age_f, jour)
        var c: Dictionary = pop.nouveau_couple(mari, femme, jour - rng.randi_range(1, maxi(1, age_f - 17)) * 360)
        var nb := mini(rng.randi_range(0, 3), places - 2)
        var age_enfant := mini(age_f - 18, 12)
        for i in nb:
            if age_enfant < 0:
                break
            var e: Dictionary = _personne(pop, "H" if rng.randf() < 0.5 else "F", clan[0], lignee, age_enfant, jour)
            e["metier"] = "enfant" if age_enfant < pop.AGE_ADULTE else "sans métier"
            e["pere"] = int(mari["id"])
            e["mere"] = int(femme["id"])
            c["enfants"].append(int(e["id"]))
            c["dernier_enfant"] = int(e["naissance"])
            age_enfant -= rng.randi_range(2, 4)
        arrivees += 2 + c["enfants"].size()
        evenement.emit("La famille %s, venue de %s, s'installe dans le clan (%d personnes)." % [clan[0], clan[1], 2 + c["enfants"].size()])
    else:
        var sexe := "H" if rng.randf() < 0.5 else "F"
        var h: Dictionary = _personne(pop, sexe, clan[0], lignee, rng.randi_range(16, 28), jour)
        arrivees += 1
        evenement.emit("%s %s, venu%s de %s, s'installe dans le clan." % [h["prenom"], h["nom"], "e" if sexe == "F" else "", clan[1]])

func _personne(pop, sexe: String, nom: String, lignee: int, age_ans: int, jour: int) -> Dictionary:
    var liste: Array = pop.PRENOMS_H if sexe == "H" else pop.PRENOMS_F
    var h: Dictionary = pop._ajouter(liste[rng.randi() % liste.size()], nom, sexe, age_ans, lignee, "sans métier", jour)
    h["origine"] = nom
    pop.faire_entrer(h)
    return h

# Un foyer part : un couple avec ses enfants mineurs, ou un adulte seul.
# Le chef ne part pas.
func _depart(pop, jour: int) -> void:
    var candidats := []
    for h in pop.habitants:
        if h["metier"] != "chef" and pop.age(h, jour) >= 16:
            candidats.append(h)
    if candidats.is_empty():
        return
    var h: Dictionary = candidats[rng.randi() % candidats.size()]
    var groupe := [h]
    var c: Dictionary = pop.couple_actif(h)
    if not c.is_empty():
        var autre: Dictionary = pop.par_id(int(c["femme"]) if int(c["mari"]) == int(h["id"]) else int(c["mari"]))
        if not autre.is_empty() and autre["metier"] != "chef":
            groupe.append(autre)
            for id in c["enfants"]:
                var e: Dictionary = pop.par_id(int(id))
                if not e.is_empty() and pop.age(e, jour) < 16:
                    groupe.append(e)
    for p in groupe:
        pop.faire_sortir(p, jour)
    departs += groupe.size()
    evenement.emit("Misère : %s %s quitte le clan%s." % [h["prenom"], h["nom"], " avec sa famille (%d personnes)" % groupe.size() if groupe.size() > 1 else ""])

# ---------- Sauvegarde ----------

func vers_dict() -> Dictionary:
    return {"actif": actif, "arrivees": arrivees, "departs": departs, "prochaine_lignee": prochaine_lignee, "graine": str(rng.seed), "etat": str(rng.state)}

func depuis_dict(d: Dictionary, graine: int) -> void:
    if d.is_empty():
        initialiser(graine)
        return
    actif = bool(d.get("actif", true))
    arrivees = int(d.get("arrivees", 0))
    departs = int(d.get("departs", 0))
    prochaine_lignee = int(d.get("prochaine_lignee", 100))
    rng.seed = int(d.get("graine", "0"))
    rng.state = int(d.get("etat", "0"))
