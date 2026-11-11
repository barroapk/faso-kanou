extends RefCounted

# Élevage (v0.3.36). Un animal est un capital vivant : il mange, boit, vieillit,
# peut mourir. Rien n'est gratuit :
#   - reproduction : un mâle ET une femelle adultes, une gestation à la fois,
#     les petits ne produisent rien avant l'âge adulte ;
#   - nourriture : pâture sur nos parcelles libres (moitié en saison sèche),
#     sinon fourrage ou grain retirés des stocks ; sinon l'animal maigrit puis meurt ;
#   - eau retirée des réserves ; sans eau, il maigrit vite ;
#   - lait (femelles qui allaitent), œufs (pintades adultes), fumier (bêtes vivantes) ;
#   - viande seulement après un abattage réel.
# Les valeurs sont dans data/especes.json (ajustables).

signal evenement(texte)

var especes := {}
var animaux: Array = []          # {id, esp, sexe, ne, gest_fin, lact_fin, derniere, etat}
var prochain_id := 1
var rng := RandomNumberGenerator.new()
var elevage_connu := false
# v0.3.77 (H2a) : régulation de la reproduction par le Premier ministre d'un clan de l'ordinateur.
# quota_naissances : espèce -> nombre de nouvelles gestations permises ce mois-ci
# (absente = aucune limite, comme avant). Le joueur n'est jamais limité.
var quota_naissances := {}
var prod_kgem_mois := 0.0     # lait et œufs produits ce mois-ci, en kg équivalent mil
# Animaux affectés à un service (ex. transport : espèce -> nombre). Vide aujourd'hui :
# aucune espèce ne porte de charge dans le jeu. Place réservée pour le transport futur.
var service := {"transport": {}}

func _init() -> void:
    rng.seed = 5151
    var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/especes.json"))
    if typeof(d) == TYPE_DICTIONARY:
        for k in d:
            if not str(k).begins_with("_"):
                especes[k] = d[k]

func adulte(a: Dictionary, jour: int) -> bool:
    return jour - int(a["ne"]) >= int(especes[a["esp"]]["adulte_j"])

func nombre(esp := "") -> int:
    return animaux.filter(func(a): return esp == "" or a["esp"] == esp).size()

func ajouter(esp: String, sexe: String, jour: int, age_j := -1) -> void:
    if age_j < 0:
        age_j = int(especes[esp]["adulte_j"])
    animaux.append({"id": prochain_id, "esp": esp, "sexe": sexe, "ne": jour - age_j, "gest_fin": -1, "lact_fin": -1, "derniere": -9999, "etat": 1.0})
    prochain_id += 1

# Besoins prévus par jour (pour le planificateur du chef).
func prevision(jour: int, pluie: bool, paturage_ha: float, ajouts := {}) -> Dictionary:
    var eau := 0.0
    var grain := 0.0
    var frais := 0.0
    var dem := 0.0
    for a in animaux:
        var e: Dictionary = especes[a["esp"]]
        eau += float(e["eau_jour"])
        grain += float(e["grain_kgem_jour"])
        dem += float(e["paturage_ha"])
        if a["sexe"] == "f" and adulte(a, jour):
            frais += float(e["oeufs_an"]) / 365.0 * 0.05 * 1430.0 / 3400.0
            if jour < int(a["lact_fin"]):
                frais += float(e["lait_kg_jour"]) * 650.0 / 3400.0
    # ajouts : bêtes à venir (espèce -> nombre), pour prévoir le coût des gestations en cours.
    for esp in ajouts:
        var ea: Dictionary = especes[esp]
        var na: float = float(ajouts[esp])
        eau += na * float(ea["eau_jour"])
        grain += na * float(ea["grain_kgem_jour"])
        dem += na * float(ea["paturage_ha"])
    var dispo := paturage_ha * (1.0 if pluie else 0.5)
    if dem > dispo:
        for a in animaux:
            var e: Dictionary = especes[a["esp"]]
            if float(e["paturage_ha"]) > 0.0:
                grain += float(e["fourrage_kgem"]) * (1.0 - dispo / dem)
        for esp in ajouts:
            var eb: Dictionary = especes[esp]
            if float(eb["paturage_ha"]) > 0.0:
                grain += float(ajouts[esp]) * float(eb["fourrage_kgem"]) * (1.0 - dispo / dem)
    return {"eau": eau, "grain": grain, "frais": frais}

# Petits attendus d'une gestation (portée moyenne x survie), pour les budgets.
func petits_attendus(esp: String) -> float:
    var e: Dictionary = especes[esp]
    return (float(e["portee"][0]) + float(e["portee"][1])) / 2.0 * float(e["survie_petits"])

func _quota_permet(esp: String) -> bool:
    return not quota_naissances.has(esp) or int(quota_naissances[esp]) > 0

func _quota_utiliser(esp: String) -> void:
    if quota_naissances.has(esp):
        quota_naissances[esp] = int(quota_naissances[esp]) - 1

func _retirer_grain(res, kgem: float) -> float:
    var reste := kgem
    for id in res.aliments.keys():
        if reste <= 0.0:
            break
        if not bool(res.produits.get(id, {}).get("sec", false)):
            continue
        var f: float = res.facteur(id)
        var pris := minf(float(res.aliments[id]) * f, reste)
        res.aliments[id] = float(res.aliments[id]) - pris / f
        reste -= pris
    res.noter("elevage", "nourriture", -(kgem - reste))
    return kgem - reste

func jour_passe(res, pop, jour: int, pluie: bool, paturage_ha: float) -> void:
    if animaux.is_empty():
        return
    var besoin_eleveurs := 0.0
    for a in animaux:
        besoin_eleveurs += 1.0 / float(especes[a["esp"]]["eleveur_pour"])
    var eleveurs := 0
    for h in pop.habitants:
        if h["metier"] == "éleveur" and not h.get("occupe", false) and not h.has("expedition"):
            eleveurs += 1
            res.travail_du_jour[int(h["id"])] = true
    # Seul le soin donné par les éleveurs dépend du travail (donc de la stabilité) ; la reproduction reste biologique.
    var soin := clampf(float(eleveurs) * res.facteur_stabilite / maxf(0.01, besoin_eleveurs), 0.0, 1.0)
    if res.travail != null and eleveurs > 0:
        res.travail.noter_travail("éleveur", float(eleveurs), float(eleveurs) * res.facteur_stabilite, float(eleveurs) * (1.0 - res.facteur_stabilite))
    # Pâture partagée, puis fourrage/grain pour le reste.
    var dem := 0.0
    for a in animaux:
        dem += float(especes[a["esp"]]["paturage_ha"])
    var part_pat := 1.0 if dem <= 0.0 else minf(1.0, paturage_ha * (1.0 if pluie else 0.5) / dem)
    var eau_dem := 0.0
    var grain_dem := 0.0
    for a in animaux:
        var e: Dictionary = especes[a["esp"]]
        eau_dem += float(e["eau_jour"])
        grain_dem += float(e["grain_kgem_jour"]) + (float(e["fourrage_kgem"]) * (1.0 - part_pat) if float(e["paturage_ha"]) > 0.0 else 0.0)
    var eau_ok := minf(1.0, float(res.stocks["eau"]) / maxf(0.01, eau_dem))
    res.stocks["eau"] = float(res.stocks["eau"]) - eau_dem * eau_ok
    res.noter("elevage", "eau", -eau_dem * eau_ok)
    var grain_ok := 1.0
    if grain_dem > 0.0:
        grain_ok = _retirer_grain(res, grain_dem) / grain_dem
    var morts: Array = []
    var naissances: Array = []
    var lait := 0.0
    var oeufs := 0.0
    var fumier := 0.0
    for a in animaux:
        var e: Dictionary = especes[a["esp"]]
        var nourri := grain_ok
        if float(e["paturage_ha"]) > 0.0:
            var part_grain := 1.0 - part_pat
            nourri = part_pat + part_grain * grain_ok
        var ok := minf(nourri, eau_ok)
        a["etat"] = clampf(float(a["etat"]) + (0.01 if ok >= 0.99 else -(1.0 - ok) * (0.15 if eau_ok < 0.99 else 0.04)), 0.0, 1.0)
        var age := jour - int(a["ne"])
        if float(a["etat"]) <= 0.0 or age > int(e["vie_j"]) or rng.randf() < float(e["mortalite_an"]) / 365.0 * (2.0 - soin):
            morts.append(a)
            continue
        fumier += float(e["fumier_kg_jour"])
        if a["sexe"] != "f" or not adulte(a, jour):
            continue
        # Mise bas.
        if int(a["gest_fin"]) >= 0 and jour >= int(a["gest_fin"]):
            a["gest_fin"] = -1
            a["derniere"] = jour
            a["lact_fin"] = jour + int(e["lactation_j"])
            var n := rng.randi_range(int(e["portee"][0]), int(e["portee"][1]))
            for i in n:
                if rng.randf() < float(e["survie_petits"]) * (0.5 + 0.5 * soin) * float(a["etat"]):
                    naissances.append(a["esp"])
        # Nouvelle gestation : un mâle adulte de l'espèce, une seule à la fois.
        elif int(a["gest_fin"]) < 0 and jour - int(a["derniere"]) >= int(e["intervalle_j"]) and float(a["etat"]) > 0.6 and rng.randf() < 1.0 / 60.0:
            if animaux.any(func(m): return m["esp"] == a["esp"] and m["sexe"] == "m" and adulte(m, jour)) and _quota_permet(a["esp"]):
                a["gest_fin"] = jour + int(e["gestation_j"])
                _quota_utiliser(a["esp"])
        if jour < int(a["lact_fin"]):
            lait += float(e["lait_kg_jour"]) * float(a["etat"])
        if int(a["gest_fin"]) < 0 and float(e["oeufs_an"]) > 0.0:
            oeufs += float(e["oeufs_an"]) / 365.0 * 0.05 * float(a["etat"])   # œuf de 50 g
    for a in morts:
        animaux.erase(a)
    for esp in naissances:
        ajouter(esp, "f" if rng.randf() < 0.5 else "m", jour, 0)
    prod_kgem_mois += lait * 650.0 / 3400.0 + oeufs * 1430.0 / 3400.0
    if lait > 0.0:
        res.ajouter("lait", lait, "production")
    if oeufs > 0.0:
        res.ajouter("oeuf", oeufs, "production")
    if fumier > 0.0:
        res.objets["fumier"] = float(res.objets.get("fumier", 0.0)) + fumier
        res.noter("production", "fumier", fumier)
    if morts.size() > 0:
        evenement.emit("Élevage : %d bête(s) morte(s) (âge, maladie ou manque)." % morts.size())

# Abattage réel. On garde un couple reproducteur, et on n'abat pas les
# femelles gestantes ou allaitantes (sauf urgence grave).
func abattre(esp: String, res, jour: int, urgence_grave := false) -> String:
    var adultes_m: Array = animaux.filter(func(a): return a["esp"] == esp and a["sexe"] == "m" and adulte(a, jour))
    var adultes_f: Array = animaux.filter(func(a): return a["esp"] == esp and a["sexe"] == "f" and adulte(a, jour))
    var choix = null
    for a in animaux:
        if a["esp"] != esp:
            continue
        if a["sexe"] == "f" and (int(a["gest_fin"]) >= 0 or jour < int(a["lact_fin"])) and not urgence_grave:
            continue
        if adulte(a, jour) and ((a["sexe"] == "m" and adultes_m.size() <= 1) or (a["sexe"] == "f" and adultes_f.size() <= 1)) and not urgence_grave:
            continue
        if choix == null or float(a["etat"]) < float(choix["etat"]):
            choix = a
    if choix == null:
        return "Aucune bête à abattre sans menacer le troupeau."
    var e: Dictionary = especes[esp]
    var kg: float = float(e["viande_kg"]) * (0.5 + 0.5 * float(choix["etat"])) * (1.0 if adulte(choix, jour) else 0.4)
    animaux.erase(choix)
    res.ajouter(e["viande_id"], kg, "abattage")
    evenement.emit("Abattage : 1 %s (%.1f kg de viande)." % [str(e["nom"]).to_lower(), kg])
    return ""

# Le chef n'abat qu'en urgence alimentaire (moins de 10 jours de nourriture).
func mois_passe(res, pop, jour: int) -> void:
    var j: float = float(res.autonomie(pop, jour).get("nourriture", 99.0))
    if j >= 10.0 or animaux.is_empty():
        return
    for esp in ["zebu", "chevre", "pintade"]:
        if nombre(esp) > 0 and abattre(esp, res, jour, j < 3.0) == "":
            return

# Capture d'une pintade sauvage par un chasseur (rare), une fois l'élevage connu.
func capture(pop, jour: int) -> void:
    if not elevage_connu:
        return
    for h in pop.habitants:
        if h["metier"] == "chasseur" and not h.get("occupe", false) and rng.randf() < 0.003:
            ajouter("pintade", "f" if rng.randf() < 0.5 else "m", jour)
            evenement.emit("%s a capturé une pintade vivante : elle rejoint l'élevage." % h["prenom"])

func texte(jour: int) -> String:
    if animaux.is_empty():
        return "Élevage : aucun animal." + ("" if elevage_connu else " (il faut d'abord découvrir l'élevage)")
    var l: PackedStringArray = []
    for esp in especes:
        var n := nombre(esp)
        if n == 0:
            continue
        var f := animaux.filter(func(a): return a["esp"] == esp and a["sexe"] == "f").size()
        var g := animaux.filter(func(a): return a["esp"] == esp and int(a["gest_fin"]) >= 0).size()
        l.append("%s : %d (%d femelles, %d gestantes)" % [especes[esp]["nom"], n, f, g])
    return "Élevage — " + " ; ".join(l)

func vers_dict() -> Dictionary:
    return {"animaux": animaux, "id": prochain_id, "connu": elevage_connu, "graine": rng.seed, "etat": rng.state}

func depuis_dict(d: Dictionary) -> void:
    animaux = d.get("animaux", [])
    prochain_id = int(d.get("id", 1))
    elevage_connu = bool(d.get("connu", false))
    if d.has("graine"):
        rng.seed = int(d["graine"])
        rng.state = int(d["etat"])
