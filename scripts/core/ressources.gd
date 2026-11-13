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
    # Enfants de 8 à 13 ans : ils aident (cueillette, corvée d'eau), comme
    # dans les villages sahéliens. Environ un quart d'un adulte.
    "aide": {"nourriture": [0.5, 0.8], "eau": [12.0, 16.0]},
    # Pêche à la pirogue et au filet (multipliée par le poisson de l'île).
    "pêcheur": {"nourriture": [3.0, 2.5]},   # + sel marin, voir SEL_MARIN
    # Hors des travaux des champs (saison sèche), le cultivateur cueille et
    # entretient son jardin ; en saison des pluies, il est aux champs.
    "cultivateur": {"nourriture": [1.5, 0.3]},
}
const AGE_AIDE := 8
# Les pêcheurs font aussi du sel marin (eau de mer évaporée sur la plage) :
# kg par pêcheur et par jour, multiplié par le sel de l'île (amorti).
const SEL_MARIN := 0.03
const CONSO_ADULTE := {"nourriture": 0.8, "eau": 5.0, "bois": 1.2}
var honneur_grenier := 0.0     # héritage d'un héros (v0.3.30), recalculé par heros.gd
var honneur_route := 0.0
var ration := 1.0              # 0.8 = rationnement (chacun mange 20 % de moins)
var ration_jusqu := -1
const CONSO_ENFANT := {"nourriture": 0.5, "eau": 3.0, "bois": 0.6}
const SEL_PAR_PERSONNE := 0.005         # kg par jour (5 g)
const BASE := {"nourriture": 300.0, "eau": 600.0, "bois": 500.0, "sel": 200.0}
const UNITES := {"nourriture": "kg", "eau": "L", "bois": "kg", "sel": "kg"}
const KCAL_KGEM := 3400.0
# Pertes de stockage par jour (part du stock).
const PERTES_NOURRITURE := 0.001        # valeur moyenne, utilisée si le stock est vide
const PERTES_NOURRITURE_GRENIER := 0.0003
# Séchage et fumage (v0.3.35) : le sécheur transforme la viande et le poisson
# frais qui restent après le repas. Calories conservées (moins 5 %) : seule
# l'eau part. Capacité : 20 kg frais par sécheur et par jour. Coûts réels :
# 0,03 kg de sel et 0,3 kg de bois par kg frais ; on garde 5 jours de bois.
const SECHAGE := {"gibier": "viande_sechee", "poisson": "poisson_fume"}
const SECHAGE_KG_JOUR := 20.0
const SECHAGE_SEL := 0.03
const SECHAGE_BOIS := 0.3
const PERTE_SECHAGE := 0.05
const COEF_GRENIER := 0.3               # un grenier divise les pertes des produits secs
const EVAPORATION_EAU := 0.002          # jarres et canaris : 0,2 % par jour
const CENDRES_PAR_KG_BOIS := 0.015      # le bois brûlé chaque jour laisse des cendres
const SEL_PAR_SEL_VEGETAL := 0.5        # simplification de jeu (pas une équivalence chimique) :
                                        # 1 kg de sel végétal remplace 0,5 kg de sel
# Sous-produits de la chasse, par kg de viande : os et cornes, peaux.
const OS_PAR_KG_VIANDE := 0.05
const PLANTES_JOUR := 0.03             # kg de plantes médicinales cueillis par jour (v0.3.45)
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
var couverture_eau := 1.0          # eau réellement distribuée / besoin du jour (0 à 1)
var facteur_stabilite := 1.0       # effet de la stabilité sur le travail (0,9 à 1), posé par la civilisation
var travail_du_jour := {}          # id des habitants ayant réellement travaillé (remis à zéro chaque jour par la civilisation)
var travail                        # journal du travail (travail.gd), branché par la civilisation
var couverture_nourriture := 1.0   # nourriture réellement distribuée / besoin théorique avant rationnement (0 à 1)
var soif := false
var jours_sans_sel := 0.0         # compteur de manque de sel (D-2) : + part non couverte, - SEL_RECUP par jour couvert

# ---------- Danger du sel (D-2) ----------
signal evenement(texte)
const SEL_RECUP := 3.0               # baisse du compteur par jour entièrement couvert
const SEL_COMPTEUR_MAX := 270.0      # au-delà, la santé est déjà à son plancher (60)
const SEL_SEUIL_EFFET := 36.0        # compteur où le plafond de santé passe sous 100
const SEL_ALERTE_JOURS := 120.0      # alerte d'anticipation : effet sanitaire prévu dans moins de 120 jours
const SEL_FIN_ALERTE_JOURS := 150.0  # l'alerte de niveau 1 se lève au-dessus (pas de va-et-vient)
var hist_sel_prod: Array = []        # sel produit (pêche, gisement, sel végétal), 7 derniers jours
var hist_sel_sechage: Array = []     # sel utilisé par le séchage, 7 derniers jours
var _sel_prod_jour := 0.0
var _sel_sechage_jour := 0.0
var alerte_sel := 0                  # 0 aucune, 1 réserve basse, 2 pénurie, 3 santé touchée
var sel_attendu := 0.0               # sel acheté encore en route (posé par la civilisation), jamais compté dans le stock
# Danger des greniers (v0.4) : stock au-dessus de la capacité (bâtiment fragile ou en ruine).
const PERTE_EXCEDENT := 0.1        # part de l'excédent perdue chaque jour (règle 3)
var hist_prod_bois: Array = []     # production de bois des 7 derniers jours (prévision d'entretien, règle 4)
var bois_brule_jour := 0.0
var richesse := {}   # richesse naturelle de l'île (data/iles.json), 1 = normal
var routes = null    # routes.gd : une route vers l'eau ou la forêt rend le travail plus efficace
var objets := {}   # tout ce qui n'est ni nourriture, ni eau, ni bois, ni sel (argile, canari...)
# Flux du mois, pour la comptabilité (economie.gd) : motif -> {ressource: quantité}
# (+ entrée, - sortie). La nourriture est comptée en kgEM sous "nourriture".
var flux := {}
var finances = null              # finances.gd : journal comptable (v0.3.59)
var budget = null                # budget.gd : caisse commune hors stocks (v0.3.40)
var prod_metier := {}            # nourriture produite par métier depuis le dernier plan du chef (v0.3.34)

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
    noter("ajustement", "nourriture", voulu - t)
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

# Ce que l'île donne : forêts (bois), gibier (chasse), poisson (pêche), fruits
# et graines (cueillette). L'effet est amorti (0,5 + 0,5 × richesse) : une île
# pauvre rend la vie plus dure, sans la rendre impossible.
func _richesse(metier: String, r: String) -> float:
    var cle := ""
    if r == "bois":
        cle = "bois"
    elif metier == "chasseur":
        cle = "chasse"
    elif metier == "pêcheur":
        cle = "poisson"
    elif r == "nourriture":
        cle = "cueillette"
    if cle == "":
        return 1.0
    return 0.5 + 0.5 * float(richesse.get(cle, 1.0))

# Sans route, on porte l'eau et le bois à pied ; une route fait gagner du temps.
func _acces(metier: String, r: String) -> float:
    if routes == null:
        return 1.0
    if metier == "porteur d'eau" and r == "eau":
        return 1.0 + routes.bonus("eau") + honneur_route
    if metier == "bâtisseur" and r == "bois":
        return 1.0 + routes.bonus("foret")
    return 1.0

func quantite(id: String) -> float:
    match _lieu(id):
        "stocks":
            return float(stocks.get(id, 0.0))
        "aliments":
            return float(aliments.get(id, 0.0))
        "outils":
            return float(equipement.nombre(id))
    return float(objets.get(id, 0.0))

func ajouter(id: String, q: float, motif := "transfert") -> void:
    if id == "sel" and motif == "extraction":
        _sel_prod_jour += maxf(0.0, minf(float(stocks["sel"]) + q, capacite("sel")) - float(stocks["sel"]))
    elif id == "sel_vegetal" and motif == "fabrication":
        _sel_prod_jour += q * SEL_PAR_SEL_VEGETAL
    if _lieu(id) != "outils":
        var reel := q
        if _lieu(id) == "stocks":
            reel = maxf(float(stocks.get(id, 0.0)), minf(float(stocks.get(id, 0.0)) + q, capacite(id))) - float(stocks.get(id, 0.0))
        noter(motif, _cle_compte(id), _q_compte(id, reel))
    match _lieu(id):
        "stocks":
            stocks[id] = maxf(float(stocks.get(id, 0.0)), minf(float(stocks.get(id, 0.0)) + q, capacite(id)))
        "aliments":
            aliments[id] = float(aliments.get(id, 0.0)) + q
            stocks["nourriture"] = total_aliments()
        "outils":
            equipement.ajouter(id, int(round(q)))
        _:
            objets[id] = float(objets.get(id, 0.0)) + q

# Stock + caisse commune : ce dont les chantiers et l'entretien disposent vraiment.
func quantite_commune(id: String) -> float:
    return quantite(id) + (budget.quantite(id) if budget != null else 0.0)

# Retire q si c'est possible ; sinon ne retire rien et renvoie false.
func retirer(id: String, q: float, motif := "transfert") -> bool:
    var q0 := q
    if budget != null and q > 0.0:
        q -= budget.depenser(id, q, motif)
        if q <= 0.000001:
            _compter(id, q0, motif)
            return true
    if quantite(id) + 0.000001 < q:
        return false
    _compter(id, q0, motif)
    if _lieu(id) != "outils":
        noter(motif, _cle_compte(id), -_q_compte(id, minf(q, quantite(id))))
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

# Vivres en kgEM : la « nourriture » n'est pas un produit, c'est la somme des aliments.
# Dépense publique (chantiers, entretien) : écrite une seule fois au journal, quelle que soit la source des biens.
func _compter(id: String, q: float, motif: String) -> void:
    if finances != null and (motif == "construction" or motif == "entretien"):
        finances.noter("dep", motif, id, q)

func retirer_vivres(kgem: float, motif := "transfert") -> bool:
    if kgem <= 0.0 or total_aliments() + 0.000001 < kgem:
        return false
    _retirer(kgem)
    stocks["nourriture"] = total_aliments()
    noter(motif, "nourriture", -kgem)
    return true

func ajouter_vivres(kgem: float, motif := "transfert", id := "mil") -> void:
    if kgem <= 0.0:
        return
    var f: float = maxf(0.01, facteur(id))
    aliments[id] = float(aliments.get(id, 0.0)) + kgem / f
    stocks["nourriture"] = total_aliments()
    noter(motif, "nourriture", kgem)

# ---------- Comptabilité des mouvements ----------

func noter(motif: String, r: String, q: float) -> void:
    if absf(q) < 0.0000001:
        return
    if not flux.has(motif):
        flux[motif] = {}
    flux[motif][r] = float(flux[motif].get(r, 0.0)) + q

func _cle_compte(id: String) -> String:
    return "nourriture" if _lieu(id) == "aliments" else id

func _q_compte(id: String, q: float) -> float:
    return q * facteur(id) if _lieu(id) == "aliments" else q

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
    return p / t * (1.0 - honneur_grenier)

func _secher(population, jour: int) -> void:
    var cap := 0.0
    for h in population.habitants:
        if h["metier"] == "sécheur" and not h.get("occupe", false):
            cap += SECHAGE_KG_JOUR * (0.6 + float(h["competence"]) / 100.0 * 0.8)
    if cap <= 0.0:
        return
    for id in SECHAGE:
        var q: float = minf(float(aliments.get(id, 0.0)), cap)
        q = minf(q, float(stocks["sel"]) / SECHAGE_SEL)
        q = minf(q, maxf(0.0, float(stocks["bois"]) - 5.0 * _conso_jour(population, jour, "bois")) / SECHAGE_BOIS)
        if q <= 0.01:
            continue
        var out: String = SECHAGE[id]
        var kgem: float = q * facteur(id)
        aliments[id] = float(aliments[id]) - q
        aliments[out] = float(aliments.get(out, 0.0)) + kgem * (1.0 - PERTE_SECHAGE) / facteur(out)
        stocks["sel"] = float(stocks["sel"]) - q * SECHAGE_SEL
        _sel_sechage_jour += q * SECHAGE_SEL
        stocks["bois"] = float(stocks["bois"]) - q * SECHAGE_BOIS
        noter("transformation", "nourriture", -kgem * PERTE_SECHAGE)
        noter("transformation", "sel", -q * SECHAGE_SEL)
        noter("transformation", "bois", -q * SECHAGE_BOIS)
        cap -= q
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

func _conso_jour(population, jour: int, r: String) -> float:
    var c := 0.0
    for h in population.habitants:
        c += float((CONSO_ENFANT if population.age(h, jour) < 14 else CONSO_ADULTE)[r])
    return c

# ---------- Journée ----------

# Efficacité d'une personne pour une compétence donnée (v0.4 : partagée avec l'aperçu
# d'affectation, pour qu'il n'y ait qu'une seule formule).
func efficacite_de(h: Dictionary, competence: float, population) -> float:
    return (0.6 + competence / 100.0 * 0.8) * outils * float(h.get("bonus_outil", 1.0)) * population.part_libre(h) * (float(budget.facteur_productivite()) if budget != null else 1.0) * facteur_stabilite

# Quantité produite en un jour par un métier pour une ressource (s : 1 pluie, 0 sec).
func quantite_jour(metier: String, r: String, base: Array, s: int, efficacite: float) -> float:
    return float(base[s]) * efficacite * _richesse(metier, r) * _acces(metier, r)

# Production par jour d'une personne dans un métier (aperçu du joueur) :
# {ressource: quantité}. Même formule que le jeu ; "sans métier" ne produit rien.
func apercu_metier(h: Dictionary, metier: String, population, pluie: bool) -> Dictionary:
    var res := {}
    var p: Dictionary = PRODUCTION.get(metier, {})
    if p.is_empty():
        return res
    # Déjà dans ce métier : sa compétence actuelle ; sinon celle que lui donnerait le changement.
    var comp: float = float(h["competence"]) if h["metier"] == metier else population.savoir(h, population.savoir_du_metier(metier))
    var eff: float = efficacite_de(h, comp, population)
    for r in p:
        res[r] = quantite_jour(metier, r, p[r], 1 if pluie else 0, eff)
    return res

func jour_passe(population, jour: int, pluie: bool, chantier_actif: bool) -> void:
    _synchroniser()
    var avant: float = total_aliments()
    var debut := {"eau": float(stocks["eau"]), "bois": float(stocks["bois"])}
    var prod_bois := 0.0
    var s := 1 if pluie else 0
    var mois := (jour / 30) % 12
    var variation := {"eau": 0.0, "bois": 0.0}
    var besoin_nourriture := 0.0
    var n: int = population.habitants.size()
    var besoin_eau := 0.0
    for h in population.habitants:
        var enfant: bool = population.age(h, jour) < 14
        var conso: Dictionary = CONSO_ENFANT if enfant else CONSO_ADULTE
        besoin_nourriture += conso["nourriture"]
        variation["eau"] -= conso["eau"]
        besoin_eau += conso["eau"]
        variation["bois"] -= conso["bois"]
        if h["metier"] == "bâtisseur" and chantier_actif:
            travail_du_jour[int(h["id"])] = true
            continue
        if h.get("occupe", false):
            travail_du_jour[int(h["id"])] = true
            continue
        var p = PRODUCTION.get(h["metier"], {})
        if h["metier"] == "enfant":
            p = PRODUCTION["aide"] if population.age(h, jour) >= AGE_AIDE else {}
        if not p.is_empty():
            travail_du_jour[int(h["id"])] = true
        var efficacite: float = efficacite_de(h, float(h["competence"]), population)
        if travail != null and not p.is_empty():
            travail.noter_travail(str(h["metier"]), 1.0, efficacite, efficacite / facteur_stabilite - efficacite)
        for r in p:
            var q: float = quantite_jour(h["metier"], r, p[r], s, efficacite)
            if travail != null:
                travail.noter_prod(str(h["metier"]), r, q, q / facteur_stabilite - q)
            if r == "nourriture":
                if h["metier"] == "pêcheur":
                    _recolter(q, {"poisson": 1.0})
                    var sel_jour := SEL_MARIN * efficacite * (0.5 + 0.5 * float(richesse.get("sel", 1.0)))
                    _sel_prod_jour += maxf(0.0, minf(float(stocks["sel"]) + sel_jour, capacite("sel")) - float(stocks["sel"]))
                    stocks["sel"] = minf(float(stocks["sel"]) + sel_jour, capacite("sel"))
                    noter("production", "sel", sel_jour)
                else:
                    _recolter(q, CHASSE if h["metier"] == "chasseur" else CUEILLETTE[mois])
                noter("production", "nourriture", q)
                prod_metier[h["metier"]] = float(prod_metier.get(h["metier"], 0.0)) + q
                if h["metier"] == "chasseur":
                    var viande := q / facteur("gibier")
                    objets["os_corne"] = float(objets.get("os_corne", 0.0)) + viande * OS_PAR_KG_VIANDE
                    objets["peau"] = float(objets.get("peau", 0.0)) + viande * PEAU_PAR_KG_VIANDE
                    noter("production", "os_corne", viande * OS_PAR_KG_VIANDE)
                    noter("production", "peau", viande * PEAU_PAR_KG_VIANDE)
                if h["metier"] == "cueilleur":
                    var plantes: float = PLANTES_JOUR * efficacite
                    objets["plantes_medicinales"] = float(objets.get("plantes_medicinales", 0.0)) + plantes
                    noter("production", "plantes_medicinales", plantes)
            else:
                variation[r] += q
                noter("production", r, q)
                if r == "bois":
                    prod_bois += q
    if pluie:
        variation["eau"] += 20.0
        noter("production", "eau", 20.0)
    noter("consommation", "eau", -_conso_jour(population, jour, "eau"))
    noter("consommation", "bois", -_conso_jour(population, jour, "bois"))
    # Nourriture : pertes sur le stock du jour, puis repas, puis trop-plein.
    noter("perte", "nourriture", -_pertes_aliments())
    if jour > ration_jusqu:
        ration = 1.0
    var besoin_brut := besoin_nourriture   # besoin théorique, avant rationnement
    besoin_nourriture *= ration
    var manque := _retirer(besoin_nourriture)
    noter("consommation", "nourriture", -(besoin_nourriture - manque))
    # Trop-plein (règle 3) : ce qui dépasse la capacité est perdu, sauf le stock qui y
    # était déjà au début du jour (capacité qui vient de baisser) : de cet excédent,
    # recalculé après les repas, on perd 10 % par jour. La récolte n'agrandit jamais l'excédent.
    var cap_n: float = capacite("nourriture")
    var limite_n: float = maxf(cap_n, avant)
    var trop := maxf(0.0, total_aliments() - limite_n)
    var excedent := minf(total_aliments(), limite_n) - cap_n
    if excedent > 0.0:
        trop += excedent * PERTE_EXCEDENT
    if trop > 0.0:
        _retirer(trop)
        noter("trop_plein", "nourriture", -trop)
    _secher(population, jour)
    stocks["nourriture"] = total_aliments()
    bilan["nourriture"] = stocks["nourriture"] - avant
    # Eau et bois.
    variation["eau"] -= stocks["eau"] * EVAPORATION_EAU
    noter("perte", "eau", -stocks["eau"] * EVAPORATION_EAU)
    var bois_brule := 0.0
    for h in population.habitants:
        bois_brule += (CONSO_ENFANT if population.age(h, jour) < 14 else CONSO_ADULTE)["bois"]
    bois_brule_jour = bois_brule    # besoin du jour (avant la limite du stock) : sert à la prévision
    if stocks["bois"] + variation["bois"] + bois_brule < bois_brule:
        bois_brule = maxf(0.0, stocks["bois"] + variation["bois"] + bois_brule)
    hist_prod_bois.append(prod_bois)
    if hist_prod_bois.size() > 7:
        hist_prod_bois.pop_front()
    for r in variation:
        var brut: float = stocks[r] + variation[r]
        var cap: float = capacite(r)
        var v: float = clampf(brut, 0.0, maxf(cap, float(debut[r])))
        if v > cap:
            v -= (v - cap) * PERTE_EXCEDENT    # règle 3 : 10 % de l'excédent par jour
        stocks[r] = v
        bilan[r] = variation[r]
        if r == "eau":
            couverture_eau = clampf(1.0 - maxf(0.0, -brut) / besoin_eau, 0.0, 1.0) if besoin_eau > 0.0 else 1.0
        # Ce qui n'a pas pu entrer (réserve pleine) ou pas pu être consommé (stock vide).
        if stocks[r] - brut < 0.0:
            noter("trop_plein", r, stocks[r] - brut)
        elif stocks[r] - brut > 0.0:
            noter("manque", r, stocks[r] - brut)
    objets["cendres"] = float(objets.get("cendres", 0.0)) + bois_brule * CENDRES_PAR_KG_BOIS
    noter("production", "cendres", bois_brule * CENDRES_PAR_KG_BOIS)
    # Sel : le sel d'abord, puis le sel végétal (moins efficace).
    var sel_avant: float = stocks["sel"]
    var besoin_sel: float = n * SEL_PAR_PERSONNE
    var pris_sel := minf(stocks["sel"], besoin_sel)
    stocks["sel"] -= pris_sel
    noter("consommation", "sel", -pris_sel)
    besoin_sel -= pris_sel
    if besoin_sel > 0.0 and float(objets.get("sel_vegetal", 0.0)) > 0.0:
        var vegetal := minf(float(objets["sel_vegetal"]), besoin_sel / SEL_PAR_SEL_VEGETAL)
        objets["sel_vegetal"] = float(objets["sel_vegetal"]) - vegetal
        noter("consommation", "sel_vegetal", -vegetal)
        besoin_sel -= vegetal * SEL_PAR_SEL_VEGETAL
    bilan["sel"] = stocks["sel"] - sel_avant
    # D-2 : le compteur monte de la part non couverte, et redescend progressivement.
    var part_manque := clampf(besoin_sel / (n * SEL_PAR_PERSONNE), 0.0, 1.0) if n > 0 else 0.0
    if part_manque > 0.000001:
        jours_sans_sel = minf(SEL_COMPTEUR_MAX, jours_sans_sel + part_manque)
    else:
        jours_sans_sel = maxf(0.0, jours_sans_sel - SEL_RECUP)
    hist_sel_prod.append(_sel_prod_jour)
    hist_sel_sechage.append(_sel_sechage_jour)
    while hist_sel_prod.size() > 7:
        hist_sel_prod.pop_front()
    while hist_sel_sechage.size() > 7:
        hist_sel_sechage.pop_front()
    _sel_prod_jour = 0.0
    _sel_sechage_jour = 0.0
    _alertes_sel(population, jour, part_manque)
    var avait_faim := faim
    var avait_soif := soif
    faim = manque > 0.001 or stocks["nourriture"] <= 0.0
    couverture_nourriture = clampf((besoin_nourriture - manque) / besoin_brut, 0.0, 1.0) if besoin_brut > 0.0 else 1.0
    soif = stocks["eau"] <= 0.0
    if faim and not avait_faim:
        penurie.emit("nourriture")
    if soif and not avait_soif:
        penurie.emit("eau")

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
    return "   ".join(morceaux)    # le sel a sa propre ligne (texte_sel, D-2)

# ---------- Sel : entrées communes S, C, P et prévision (D-2) ----------
# Une seule source pour l'affichage, les alertes et le Premier ministre.

static func _moyenne(h: Array) -> float:
    if h.is_empty():
        return 0.0
    var t := 0.0
    for q in h:
        t += float(q)
    return t / h.size()

# S : stock de sel + équivalent du sel végétal (kg de sel).
func sel_stock() -> float:
    return float(stocks["sel"]) + float(objets.get("sel_vegetal", 0.0)) * SEL_PAR_SEL_VEGETAL

# C : consommation par jour (habitants + séchage moyen des 7 derniers jours).
func sel_conso(population) -> float:
    return population.habitants.size() * SEL_PAR_PERSONNE + _moyenne(hist_sel_sechage)

# P : production par jour (moyenne des 7 derniers jours ; achats exclus).
func sel_prod() -> float:
    return _moyenne(hist_sel_prod)

const SEL_SANS_LIMITE := 999999.0

# Autonomie du stock : S / C, sans production.
func autonomie_sel(population) -> float:
    var c := sel_conso(population)
    return sel_stock() / c if c > 0.0 else SEL_SANS_LIMITE

# Autonomie prévisionnelle : S / (C - P) si P < C. extra : production ajoutée (aperçu du PM).
func autonomie_sel_prevue(population, extra := 0.0) -> float:
    var c := sel_conso(population)
    var p := sel_prod() + extra
    if c <= 0.0 or p >= c:
        return SEL_SANS_LIMITE
    return sel_stock() / (c - p)

# Jours avant le premier effet sur la santé (compteur 36). 0 si la santé est déjà touchée,
# SEL_SANS_LIMITE si la production couvre la consommation. Pendant que le stock couvre
# les besoins, le compteur baisse de SEL_RECUP par jour ; ensuite il monte de la part manquante.
func delai_sel(population, extra := 0.0) -> float:
    if jours_sans_sel >= SEL_SEUIL_EFFET:
        return 0.0
    var c := sel_conso(population)
    var p := sel_prod() + extra
    if c <= 0.0 or p >= c:
        return SEL_SANS_LIMITE
    var t1 := sel_stock() / (c - p)
    var c1 := maxf(0.0, jours_sans_sel - SEL_RECUP * t1)
    return t1 + (SEL_SEUIL_EFFET - c1) / (1.0 - p / c)

func plafond_sel() -> int:
    return preload("res://scripts/core/population.gd").plafond_sante(jours_sans_sel)

func texte_attendu() -> String:
    return " (%.1f kg de sel attendus)" % sel_attendu if sel_attendu > 0.05 else ""

# Ligne du bandeau : stock, autonomie et, pendant un manque, la limite de santé ou le délai.
func texte_sel(population) -> String:
    var a := autonomie_sel(population)
    var t := "Sel %.1f kg · %s" % [float(stocks["sel"]), "sans limite" if a >= SEL_SANS_LIMITE else "%d j" % int(a)]
    if jours_sans_sel >= SEL_SEUIL_EFFET:
        t += " · santé limitée à %d (manque de sel)" % plafond_sel()
    elif jours_sans_sel > 0.0 or alerte_sel > 0:
        var d := delai_sel(population)
        if d < SEL_SANS_LIMITE:
            t += " · santé touchée dans ~%d j" % int(d)
    return t + texte_attendu()

# Messages des quatre niveaux, chacun une fois par franchissement de seuil.
func _alertes_sel(population, _jour: int, part_manque: float) -> void:
    if population.habitants.is_empty():
        return
    if jours_sans_sel >= SEL_SEUIL_EFFET:
        if alerte_sel < 3:
            alerte_sel = 3
            evenement.emit("Le manque de sel limite la santé de tout le clan à %d. Les soins ne peuvent pas aller au-delà. Pêcheurs, achat ou sel végétal : voir « Sel et santé » (écran du chef).%s" % [plafond_sel(), texte_attendu()])
        return
    if alerte_sel == 3:
        alerte_sel = 0
        evenement.emit("Le sel est revenu : la santé n'est plus limitée.")
        return
    if part_manque > 0.000001:
        if alerte_sel < 2:
            alerte_sel = 2
            var d := delai_sel(population)
            evenement.emit("Pénurie de sel : %d %% du besoin couvert aujourd'hui. La santé sera touchée dans environ %d jours.%s" % [int(round((1.0 - part_manque) * 100.0)), int(d), texte_attendu()])
        return
    if alerte_sel == 2 and jours_sans_sel <= 0.0:
        alerte_sel = 0
    var d2 := delai_sel(population)
    var manque_prevu := sel_prod() < sel_conso(population)
    if alerte_sel == 0 and manque_prevu and d2 < SEL_ALERTE_JOURS:
        alerte_sel = 1
        evenement.emit("Le sel baisse : au rythme actuel, la santé commencera à baisser dans environ %d jours.%s" % [int(d2), texte_attendu()])
    elif alerte_sel == 1 and (not manque_prevu or d2 > SEL_FIN_ALERTE_JOURS):
        alerte_sel = 0

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
    return {"stocks": stocks, "aliments": aliments, "objets": objets, "jours_sans_sel": jours_sans_sel, "hist_sel_prod": hist_sel_prod, "hist_sel_sechage": hist_sel_sechage, "alerte_sel": alerte_sel, "outils": outils, "faim": faim, "soif": soif, "ration": ration, "ration_jusqu": ration_jusqu}

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
    jours_sans_sel = float(d.get("jours_sans_sel", 0))
    hist_sel_prod = Array(d.get("hist_sel_prod", [])).map(func(x): return float(x))
    hist_sel_sechage = Array(d.get("hist_sel_sechage", [])).map(func(x): return float(x))
    alerte_sel = int(d.get("alerte_sel", 0))
    outils = float(d.get("outils", 1.0))
    faim = bool(d.get("faim", false))
    soif = bool(d.get("soif", false))
    ration = float(d.get("ration", 1.0))
    ration_jusqu = int(d.get("ration_jusqu", -1))
