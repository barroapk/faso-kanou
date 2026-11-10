extends SceneTree

# Démographie sur 100 ans, plusieurs graines, deux cas de logement :
#   fixe     : 4 huttes (20 places), personne ne construit
#   construit: un joueur construit une hutte quand besoins.gd signale le manque
# Les postes sont gérés par besoins.gd en mode auto (comme le jeu actuel).
# Lancer : godot --headless --path . --script tests/test_demographie.gd

const TEMPS = preload("res://scripts/core/temps.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")
const MIGRATION = preload("res://scripts/core/migration.gd")

const GRAINES := [2026, 1, 2, 3, 4, 5, 6, 7, 8, 9]
const ANS := 100
var VARIANTES := ["fixe", "construit", "fixe+migration", "construit+migration"]

var erreurs := {}
var t
var pop
var res
var cons
var b
var mig
var naissances := 0
var morts := 0
var nes := {}          # id -> jour de naissance
var morts_jour := {}   # id -> jour du décès
var sortis := {}
var filiation := {}    # id -> [pere, mere], vérification indépendante
var age_meres := {}
var conceptions := {}
var sur_capacite := 0
var naissances_hors_capacite := 0

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() > 0:
        VARIANTES = args[0].split(",")
    for variante in VARIANTES:
        print("=== Logement %s ===" % variante)
        print("graine | pop fin | max | naiss | décès | croiss/an | couples | stériles | <5 ans | enfants/couple fini")
        var cumul := {"naiss": 0, "couples": 0, "steriles": 0, "nes5": 0, "morts5": 0, "croiss": 0.0, "eteints": 0, "arr": 0, "dep": 0}
        for g in GRAINES:
            var r := _simuler(g, variante)
            for k in cumul:
                cumul[k] += r.get(k, 0)
        var n := GRAINES.size()
        print("MOYENNE %s : arrivées %d, départs %d, croissance %.2f %%/an, stérilité %.1f %% (réglage 10 %%), mortalité avant 5 ans %.1f %% (réglage 18 %%), clans éteints %d/%d" % [variante, cumul["arr"], cumul["dep"], cumul["croiss"] / n, 100.0 * cumul["steriles"] / maxi(1, cumul["couples"]), 100.0 * cumul["morts5"] / maxi(1, cumul["nes5"]), cumul["eteints"], n])
    print("--- Âge des mères à la naissance (toutes simulations) ---")
    for k in ["16-19", "20-29", "30-34", "35-39", "40-44", "autre"]:
        print("  %s ans : %d" % [k, age_meres.get(k, 0)])
    print("--- Contrôles ---")
    for k in ["couple interdit", "enfant sans parents enregistrés", "enfant sans couple parental valide", "naissance sans grossesse de 9 mois"]:
        print("  %s : %d" % [k, erreurs.get(k, 0)])
    print("  naissance au-delà de la capacité de logement : %d" % naissances_hors_capacite)
    print("  mois où la population dépasse la capacité (huttes en ruine) : %d" % sur_capacite)
    var total := 0
    for k in erreurs:
        total += erreurs[k]
    print("RÉSULTAT : %s" % ("OK" if total == 0 and naissances_hors_capacite == 0 else "RATÉ"))
    quit()

func _simuler(graine: int, variante: String) -> Dictionary:
    t = TEMPS.new()
    pop = POPULATION.new()
    res = RESSOURCES.new()
    cons = CONSTRUCTION.new()
    res.construction = cons
    b = BESOINS.new()
    mig = MIGRATION.new()
    mig.initialiser(graine)
    mig.actif = variante.ends_with("migration")
    pop.creer_clan_initial(0, graine)
    cons.etat_initial()
    naissances = 0
    morts = 0
    nes = {}
    morts_jour = {}
    sortis = {}
    filiation = {}
    for h in pop.habitants:
        filiation[int(h["id"])] = [int(h["pere"]), int(h["mere"])]
    pop.naissance.connect(_sur_naissance)
    pop.deces.connect(_sur_deces)
    pop.union.connect(_sur_union)
    pop.entree.connect(_sur_entree)
    pop.sortie.connect(_sur_sortie)
    var depart: int = pop.habitants.size()
    var maxi_pop := depart
    var fin_an := ANS
    for an in ANS:
        for j in 360:
            t.jour_total += 1
            var chantier: bool = not cons.chantiers.is_empty()
            res.jour_passe(pop, t.jour_total, t.saison_des_pluies(), chantier)
            cons.jour_passe(_travail())
            pop.jour_passe(res.faim, res.soif)
            if t.jour_total % 30 == 0:
                _mois(variante)
        maxi_pop = maxi(maxi_pop, pop.habitants.size())
        if pop.habitants.is_empty():
            fin_an = an + 1
            break
    var fin: int = pop.habitants.size()
    var croiss := 0.0
    if fin > 0:
        croiss = (pow(float(fin) / depart, 1.0 / ANS) - 1.0) * 100.0
    else:
        croiss = -100.0 / fin_an
    var steriles := 0
    var enfants_finis := 0
    var couples_finis := 0
    for c in pop.couples:
        if c["sterile"]:
            steriles += 1
        if int(c["fin"]) >= 0:
            couples_finis += 1
            enfants_finis += c["enfants"].size()
    var nes5 := 0
    var morts5 := 0
    for id in nes:
        if sortis.has(id):
            continue
        if t.jour_total - int(nes[id]) >= 5 * 360:
            nes5 += 1
            if morts_jour.has(id) and int(morts_jour[id]) - int(nes[id]) < 5 * 360:
                morts5 += 1
    print("%6d | %7d | %3d | %5d | %5d | %8.2f %% | %7d | %8d | %5.1f %% | %.1f" % [graine, fin, maxi_pop, naissances, morts, croiss, pop.couples.size(), steriles, 100.0 * morts5 / maxi(1, nes5), float(enfants_finis) / maxi(1, couples_finis)])
    pop.naissance.disconnect(_sur_naissance)
    pop.deces.disconnect(_sur_deces)
    pop.union.disconnect(_sur_union)
    pop.entree.disconnect(_sur_entree)
    pop.sortie.disconnect(_sur_sortie)
    return {"arr": mig.arrivees, "dep": mig.departs, "naiss": naissances, "couples": pop.couples.size(), "steriles": steriles, "nes5": nes5, "morts5": morts5, "croiss": croiss, "eteints": 1 if fin == 0 else 0}

func _mois(variante: String) -> void:
    cons.mois_passe(res)
    var logement := int(cons.effet_total("logement"))
    conceptions = {}
    for c in pop.couples:
        conceptions[int(c["id"])] = int(c["conception"])
    var avant: int = naissances
    pop.mois_passe(t.jour_total, res.stocks["nourriture"] > 100.0, logement)
    if pop.habitants.size() > logement:
        sur_capacite += 1
        if naissances > avant and pop.habitants.size() - (naissances - avant) >= logement:
            naissances_hors_capacite += 1
    b.mois_passe(pop, res, cons, t.jour_total, t.saison_des_pluies(), not cons.chantiers.is_empty())
    mig.mois_passe(pop, res, cons, t.jour_total)
    if variante.begins_with("construit") and cons.chantiers.is_empty():
        for p in b.problemes:
            if p["type"] == "logement" and p["solutions"].size() > 0:
                b.appliquer(p["solutions"][0])
    pop.repartir(t.jour_total)

func _travail() -> float:
    var w := 0.0
    for h in pop.habitants:
        if h["metier"] == "bâtisseur":
            w += 0.6 + float(h["competence"]) / 100.0 * 0.8
    return w

func _erreur(k: String) -> void:
    erreurs[k] = int(erreurs.get(k, 0)) + 1

func _sur_naissance(h: Dictionary) -> void:
    naissances += 1
    var id := int(h["id"])
    nes[id] = t.jour_total
    if h.has("origine"):
        return
    var pere := int(h["pere"])
    var mere := int(h["mere"])
    filiation[id] = [pere, mere]
    if pere < 0 or mere < 0:
        _erreur("enfant sans parents enregistrés")
    var trouve := false
    for c in pop.couples:
        if int(c["mari"]) == pere and int(c["femme"]) == mere and c["enfants"].has(id):
            trouve = true
            var conc := int(conceptions.get(int(c["id"]), -1))
            if conc < 0 or t.jour_total - conc < pop.GROSSESSE_JOURS:
                _erreur("naissance sans grossesse de 9 mois")
    if not trouve:
        _erreur("enfant sans couple parental valide")
    var m: Dictionary = pop.par_id(mere)
    var a: int = pop.age(m, t.jour_total) if not m.is_empty() else -1
    var k := "autre"
    for band in [[16, 19, "16-19"], [20, 29, "20-29"], [30, 34, "30-34"], [35, 39, "35-39"], [40, 44, "40-44"]]:
        if a >= band[0] and a <= band[1]:
            k = band[2]
    age_meres[k] = int(age_meres.get(k, 0)) + 1

func _sur_deces(h: Dictionary) -> void:
    morts += 1
    morts_jour[int(h["id"])] = t.jour_total

# Vérification indépendante de la parenté (sans utiliser population.apparentes).
func _par(id: int) -> Array:
    return filiation.get(id, [-1, -1]).filter(func(x): return x >= 0)

func _gp(id: int) -> Array:
    var l := []
    for p in _par(id):
        l.append_array(_par(p))
    return l

func _sur_union(mari: Dictionary, femme: Dictionary) -> void:
    var m := int(mari["id"])
    var f := int(femme["id"])
    for x in [mari, femme]:
        if not filiation.has(int(x["id"])):
            filiation[int(x["id"])] = [int(x.get("pere", -1)), int(x.get("mere", -1))]
    var pm := _par(m)
    var pf := _par(f)
    var gm := _gp(m)
    var gf := _gp(f)
    var interdit: bool = int(mari["famille"]) == int(femme["famille"])
    interdit = interdit or pm.has(f) or pf.has(m) or gm.has(f) or gf.has(m)
    for x in pm:
        if pf.has(x) or gf.has(x):
            interdit = true
    for x in pf:
        if gm.has(x):
            interdit = true
    if interdit:
        _erreur("couple interdit")

func _sur_entree(h: Dictionary) -> void:
    filiation[int(h["id"])] = [int(h.get("pere", -1)), int(h.get("mere", -1))]

func _sur_sortie(h: Dictionary) -> void:
    sortis[int(h["id"])] = true
