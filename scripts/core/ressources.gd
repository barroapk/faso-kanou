extends RefCounted

# Stocks physiques du clan et consommation quotidienne.
# Nourriture : stockée produit par produit (data/produits.json), en kg réels.
# stocks["nourriture"] = total en kg équivalent mil (kgEM, 1 kgEM = 3400 kcal) :
# c'est ce que mangent les habitants et ce qu'utilisent besoins.gd et le chef.
# Sel : besoin à part (pas de calories). Eau, bois : inchangés.

signal penurie(ressource)

# Production par jour et par travailleur [saison sèche, saison des pluies].
# Pour la nourriture, en kgEM : la valeur nourrissante est la même qu'avant ;
# RECOLTE dit en quels produits elle arrive selon le mois.
const PRODUCTION := {
    "chasseur": {"nourriture": [3.0, 2.2]},
    "cueilleur": {"nourriture": [2.0, 3.5]},
    "chef": {"nourriture": [0.5, 0.5]},
    "sans métier": {"nourriture": [0.8, 1.2]},
    "porteur d'eau": {"eau": [50.0, 70.0]},
    "bâtisseur": {"bois": [12.0, 10.0]},
}
const CONSO_ADULTE := {"nourriture": 0.8, "eau": 5.0, "bois": 1.2}
const CONSO_ENFANT := {"nourriture": 0.5, "eau": 3.0, "bois": 0.6}
const SEL_PAR_PERSONNE := 0.005         # kg par jour (5 g)
const BASE := {"nourriture": 300.0, "eau": 600.0, "bois": 500.0, "sel": 200.0}
const UNITES := {"nourriture": "kg", "eau": "L", "bois": "kg", "sel": "kg"}
const KCAL_KGEM := 3400.0
# Pertes de stockage par jour (part du stock).
const PERTES_NOURRITURE := 0.001        # valeur moyenne, utilisée si le stock est vide
const PERTES_NOURRITURE_GRENIER := 0.0003
const COEF_GRENIER := 0.3               # un grenier divise les pertes des produits secs
const EVAPORATION_EAU := 0.002          # jarres et canaris : 0,2 % par jour
const CENDRES_PAR_KG_BOIS := 0.015      # le bois brûlé chaque jour laisse des cendres
const SEL_PAR_SEL_VEGETAL := 0.5        # simplification de jeu (pas une équivalence chimique) :
                                        # 1 kg de sel végétal remplace 0,5 kg de sel
# Sous-produits de la chasse, par kg de viande : os et cornes, peaux.
const OS_PAR_KG_VIANDE := 0.05
const PEAU_PAR_KG_VIANDE := 0.08

# Cueillette par mois (janvier = 0) : part de chaque produit, total = 1.
# Saison sèche : pulpe de baobab, tamarin, néré, miel. Début des pluies : karité.
# Pluies : feuilles de baobab, pastèque. Fin des pluies : fonio sauvage.
const CUEILLETTE := [
    {"baobab_pulpe": 0.5, "tamarin": 0.5},
    {"tamarin": 0.4, "nere_graine": 0.3, "baobab_pulpe": 0.3},
    {"nere_graine": 0.6, "miel": 0.2, "tamarin": 0.2},
    {"nere_graine": 0.5, "miel": 0.3, "karite_amande": 0.2},
    {"karite_amande": 0.6, "miel": 0.2, "nere_graine": 0.2},
    {"karite_amande": 0.7, "baobab_feuille": 0.3},
    {"karite_amande": 0.4, "baobab_feuille": 0.6},
    {"baobab_feuille": 0.7, "pasteque": 0.3},
    {"fonio_sauvage": 0.6, "baobab_feuille": 0.2, "pasteque": 0.2},
    {"fonio_sauvage": 0.8, "baobab_feuille": 0.2},
    {"fonio_sauvage": 0.4, "baobab_pulpe": 0.6},
    {"baobab_pulpe": 0.6, "tamarin": 0.4},
]
const CHASSE := {"gibier": 1.0}

var construction
var equipement      # outils (equipement.gd), branché par la civilisation
var produits := {}
var stocks := {"nourriture": 300.0, "eau": 120.0, "bois": 100.0, "sel": 20.0}
var aliments := {"fonio_sauvage": 200.0, "baobab_pulpe": 60.0, "karite_amande": 28.0}
var bilan := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0, "sel": 0.0}
var outils := 1.0
var faim := false
var soif := false
var jours_sans_sel := 0
var objets := {}   # tout ce qui n'est ni nourriture, ni eau, ni bois, ni sel (argile, canari...)

func _init() -> void:
    var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/produits.json"))
    if typeof(d) == TYPE_DICTIONARY:
        produits = d.get("produits", {})
    stocks["nourriture"] = total_aliments()

# ---------- Produits ----------

func facteur(id: String) -> float:
    return float(produits.get(id, {}).get("kcal_kg", KCAL_KGEM)) / KCAL_KGEM

func total_aliments() -> float:
    var t := 0.0
    for id in aliments:
        t += float(aliments[id]) * facteur(id)
    return t

func nom_produit(id: String) -> String:
    return str(produits.get(id, {}).get("nom", id))

# Ajoute une production en kgEM, répartie selon les parts (produit -> part).
func _recolter(kgem: float, parts: Dictionary) -> void:
    for id in parts:
        var f := facteur(id)
        if f <= 0.0:
            continue
        aliments[id] = float(aliments.get(id, 0.0)) + kgem * float(parts[id]) / f

# Repas (ou trop-plein) : d'abord les produits frais qui pourrissent vite
# (pertes de 1 % par jour ou plus), du plus fragile au moins fragile ;
# le reste est pris en proportion de chaque produit qui se garde.
const SEUIL_FRAIS := 0.01

func _frais() -> Array:
    var ids := []
    for id in aliments:
        if float(aliments[id]) > 0.0 and facteur(id) > 0.0 and float(produits.get(id, {}).get("perte_jour", 0.0)) >= SEUIL_FRAIS:
            ids.append(id)
    ids.sort_custom(func(a, b): return float(produits.get(a, {}).get("perte_jour", 0.0)) > float(produits.get(b, {}).get("perte_jour", 0.0)))
    return ids

# Retire kgem de nourriture. Renvoie ce qui manquait.
func _retirer(kgem: float) -> float:
    var reste := kgem
    for id in _frais():
        if reste <= 0.0:
            break
        var f := facteur(id)
        var pris := minf(float(aliments[id]) * f, reste)
        aliments[id] = float(aliments[id]) - pris / f
        reste -= pris
    if reste > 0.0:
        var durable := 0.0
        for id in aliments:
            if facteur(id) > 0.0:
                durable += float(aliments[id]) * facteur(id)
        if durable > 0.0:
            var k := minf(1.0, reste / durable)
            for id in aliments.keys():
                if facteur(id) > 0.0:
                    aliments[id] = float(aliments[id]) * (1.0 - k)
            reste = maxf(0.0, reste - durable * k)
    _nettoyer()
    return reste

func _nettoyer() -> void:
    for id in aliments.keys():
        if float(aliments[id]) < 0.0001:
            aliments.erase(id)

func _pertes_aliments() -> float:
    var grenier: bool = construction != null and construction.effet_total("conservation") > 0.0
    var perdu := 0.0
    for id in aliments.keys():
        var p: Dictionary = produits.get(id, {})
        var taux := float(p.get("perte_jour", PERTES_NOURRITURE))
        if grenier and bool(p.get("sec", false)):
            taux *= COEF_GRENIER
        var kg: float = float(aliments[id]) * taux
        aliments[id] = float(aliments[id]) - kg
        perdu += kg * facteur(id)
    _nettoyer()
    return perdu

# Si un autre module a changé stocks["nourriture"] directement,
# les produits sont ajustés en proportion (rien n'est inventé).
func _synchroniser() -> void:
    var t := total_aliments()
    var voulu: float = stocks["nourriture"]
    if absf(t - voulu) < 0.01:
        return
    if t > 0.0:
        var k := voulu / t
        for id in aliments:
            aliments[id] = float(aliments[id]) * k
    elif voulu > 0.0:
        aliments["fonio_sauvage"] = voulu / facteur("fonio_sauvage")
    _nettoyer()

# ---------- Inventaire général (pour les recettes) ----------
# Chaque identifiant du catalogue va au bon endroit :
# eau, bois, sel -> stocks ; aliments à calories -> aliments ; le reste -> objets.

func _lieu(id: String) -> String:
    if id == "eau" or id == "bois" or id == "sel":
        return "stocks"
    if equipement != null and equipement.est_outil(id):
        return "outils"
    var f: Dictionary = produits.get(id, {})
    if bool(f.get("alimentaire", false)) and float(f.get("kcal_kg", 0.0)) > 0.0:
        return "aliments"
    return "objets"

func quantite(id: String) -> float:
    match _lieu(id):
        "stocks":
            return float(stocks.get(id, 0.0))
        "aliments":
            return float(aliments.get(id, 0.0))
        "outils":
            return float(equipement.nombre(id))
    return float(objets.get(id, 0.0))

func ajouter(id: String, q: float) -> void:
    match _lieu(id):
        "stocks":
            stocks[id] = minf(float(stocks.get(id, 0.0)) + q, capacite(id))
        "aliments":
            aliments[id] = float(aliments.get(id, 0.0)) + q
            stocks["nourriture"] = total_aliments()
        "outils":
            equipement.ajouter(id, int(round(q)))
        _:
            objets[id] = float(objets.get(id, 0.0)) + q

# Retire q si c'est possible ; sinon ne retire rien et renvoie false.
func retirer(id: String, q: float) -> bool:
    if quantite(id) + 0.000001 < q:
        return false
    match _lieu(id):
        "stocks":
            stocks[id] = maxf(0.0, float(stocks[id]) - q)
        "aliments":
            aliments[id] = maxf(0.0, float(aliments[id]) - q)
            _nettoyer()
            stocks["nourriture"] = total_aliments()
        "outils":
            return equipement.retirer(id, int(round(q)))
        _:
            objets[id] = maxf(0.0, float(objets[id]) - q)
            if float(objets[id]) < 0.000001:
                objets.erase(id)
    return true

# ---------- Mesures ----------

func capacite(r: String) -> float:
    return BASE.get(r, 0.0) + construction.effet_total("stock_" + r)

# Taux de pertes moyen de la nourriture stockée (par kgEM), pour besoins.gd.
func taux_pertes() -> float:
    var t := total_aliments()
    if t <= 0.0:
        return PERTES_NOURRITURE
    var grenier: bool = construction.effet_total("conservation") > 0.0
    var p := 0.0
    for id in aliments:
        var fiche: Dictionary = produits.get(id, {})
        var taux := float(fiche.get("perte_jour", PERTES_NOURRITURE))
        if grenier and bool(fiche.get("sec", false)):
            taux *= COEF_GRENIER
        p += float(aliments[id]) * facteur(id) * taux
    return p / t

# Autonomie : nombre de jours tenables sur les stocks, sans produire ni importer.
func autonomie(population, jour: int) -> Dictionary:
    var conso := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0, "sel": 0.0}
    for h in population.habitants:
        var c: Dictionary = CONSO_ENFANT if population.age(h, jour) < 14 else CONSO_ADULTE
        for r in c:
            conso[r] += c[r]
        conso["sel"] += SEL_PAR_PERSONNE
    var a := {}
    for r in conso:
        a[r] = stocks[r] / conso[r] if conso[r] > 0.0 else 9999.0
    return a

# ---------- Journée ----------

func jour_passe(population, jour: int, pluie: bool, chantier_actif: bool) -> void:
    _synchroniser()
    var avant: float = total_aliments()
    var s := 1 if pluie else 0
    var mois := (jour / 30) % 12
    var variation := {"eau": 0.0, "bois": 0.0}
    var besoin_nourriture := 0.0
    var n: int = population.habitants.size()
    for h in population.habitants:
        var enfant: bool = population.age(h, jour) < 14
        var conso: Dictionary = CONSO_ENFANT if enfant else CONSO_ADULTE
        besoin_nourriture += conso["nourriture"]
        variation["eau"] -= conso["eau"]
        variation["bois"] -= conso["bois"]
        if h["metier"] == "bâtisseur" and chantier_actif:
            continue
        if h.get("occupe", false):
            continue
        var p = PRODUCTION.get(h["metier"], {})
        var efficacite := (0.6 + float(h["competence"]) / 100.0 * 0.8) * outils * float(h.get("bonus_outil", 1.0))
        for r in p:
            var q: float = p[r][s] * efficacite
            if r == "nourriture":
                _recolter(q, CHASSE if h["metier"] == "chasseur" else CUEILLETTE[mois])
                if h["metier"] == "chasseur":
                    var viande := q / facteur("gibier")
                    objets["os_corne"] = float(objets.get("os_corne", 0.0)) + viande * OS_PAR_KG_VIANDE
                    objets["peau"] = float(objets.get("peau", 0.0)) + viande * PEAU_PAR_KG_VIANDE
            else:
                variation[r] += q
    if pluie:
        variation["eau"] += 20.0
    # Nourriture : pertes sur le stock du jour, puis repas, puis trop-plein.
    _pertes_aliments()
    var manque := _retirer(besoin_nourriture)
    var trop := total_aliments() - capacite("nourriture")
    if trop > 0.0:
        _retirer(trop)
    stocks["nourriture"] = total_aliments()
    bilan["nourriture"] = stocks["nourriture"] - avant
    # Eau et bois.
    variation["eau"] -= stocks["eau"] * EVAPORATION_EAU
    var bois_brule := 0.0
    for h in population.habitants:
        bois_brule += (CONSO_ENFANT if population.age(h, jour) < 14 else CONSO_ADULTE)["bois"]
    if stocks["bois"] + variation["bois"] + bois_brule < bois_brule:
        bois_brule = maxf(0.0, stocks["bois"] + variation["bois"] + bois_brule)
    for r in variation:
        stocks[r] = clampf(stocks[r] + variation[r], 0.0, capacite(r))
        bilan[r] = variation[r]
    objets["cendres"] = float(objets.get("cendres", 0.0)) + bois_brule * CENDRES_PAR_KG_BOIS
    # Sel : le sel d'abord, puis le sel végétal (moins efficace).
    var sel_avant: float = stocks["sel"]
    var besoin_sel: float = n * SEL_PAR_PERSONNE
    var pris_sel := minf(stocks["sel"], besoin_sel)
    stocks["sel"] -= pris_sel
    besoin_sel -= pris_sel
    if besoin_sel > 0.0 and float(objets.get("sel_vegetal", 0.0)) > 0.0:
        var vegetal := minf(float(objets["sel_vegetal"]), besoin_sel / SEL_PAR_SEL_VEGETAL)
        objets["sel_vegetal"] = float(objets["sel_vegetal"]) - vegetal
        besoin_sel -= vegetal * SEL_PAR_SEL_VEGETAL
    bilan["sel"] = stocks["sel"] - sel_avant
    jours_sans_sel = jours_sans_sel + 1 if besoin_sel > 0.000001 and n > 0 else 0
    var avait_faim := faim
    var avait_soif := soif
    faim = manque > 0.001 or stocks["nourriture"] <= 0.0
    soif = stocks["eau"] <= 0.0
    if faim and not avait_faim:
        penurie.emit("nourriture")
    if soif and not avait_soif:
        penurie.emit("eau")
    if jours_sans_sel == 1:
        penurie.emit("sel")

# ---------- Affichage ----------

func texte() -> String:
    var morceaux: PackedStringArray = []
    for r in ["nourriture", "eau", "bois"]:
        var etat := ""
        if stocks[r] >= capacite(r):
            etat = "plein"
        else:
            etat = "%s%.1f/j" % ["+" if bilan[r] >= 0.0 else "", bilan[r]]
        morceaux.append("%s %d/%d %s (%s)" % [r.capitalize(), int(stocks[r]), int(capacite(r)), UNITES[r], etat])
    morceaux.append("Sel %.1f kg" % stocks["sel"])
    return "   ".join(morceaux)

# Les 3 produits alimentaires les plus abondants, pour l'affichage.
func texte_aliments() -> String:
    var ids := aliments.keys()
    ids.sort_custom(func(a, b): return float(aliments[a]) * facteur(a) > float(aliments[b]) * facteur(b))
    var morceaux: PackedStringArray = []
    for id in ids.slice(0, 3):
        morceaux.append("%s %d kg" % [nom_produit(id), int(aliments[id])])
    return ", ".join(morceaux)

# ---------- Sauvegarde ----------

func vers_dict() -> Dictionary:
    return {"stocks": stocks, "aliments": aliments, "objets": objets, "jours_sans_sel": jours_sans_sel, "outils": outils, "faim": faim, "soif": soif}

func depuis_dict(d: Dictionary) -> void:
    var st: Dictionary = d.get("stocks", {})
    for r in stocks:
        stocks[r] = float(st.get(r, stocks[r]))
    aliments = {}
    if d.has("aliments"):
        var al: Dictionary = d["aliments"]
        for id in al:
            aliments[str(id)] = float(al[id])
    elif stocks["nourriture"] > 0.0:
        # Ancienne sauvegarde : la nourriture devient du fonio sauvage.
        aliments["fonio_sauvage"] = stocks["nourriture"] / facteur("fonio_sauvage")
    stocks["nourriture"] = total_aliments()
    objets = {}
    var ob: Dictionary = d.get("objets", {})
    for id in ob:
        objets[str(id)] = float(ob[id])
    jours_sans_sel = int(d.get("jours_sans_sel", 0))
    outils = float(d.get("outils", 1.0))
    faim = bool(d.get("faim", false))
    soif = bool(d.get("soif", false))
