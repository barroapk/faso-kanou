extends SceneTree

# Catalogue des produits (v0.3.7) : fiches, équivalence nutritionnelle, interdits,
# sel, puis 10 simulations x 100 ans (logement construit au besoin).
const TEMPS = preload("res://scripts/core/temps.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")

const CHAMPS := ["nom", "categorie", "kcal_kg", "perte_jour", "sec", "valeur", "epoque", "disponibilite", "terrains"]
const JAMAIS_PRODUITS := ["sel", "ble", "raisin", "mangue", "orange", "mais", "arachide", "datte", "sucre", "coton"]

var ok := 0
var rate := 0

func _initialize() -> void:
    var res = RESSOURCES.new()
    # 1. Fiches
    var completes := true
    for id in res.produits:
        for c in CHAMPS:
            if not res.produits[id].has(c):
                completes = false
                print("   fiche incomplète : %s (%s)" % [id, c])
    _verifier("%d produits, toutes les fiches ont les 9 propriétés" % res.produits.size(), completes and res.produits.size() >= 30)
    _verifier("coton : fibre, jamais nourriture (0 kcal)", res.produits["coton"]["categorie"] == "fibre" and float(res.produits["coton"]["kcal_kg"]) == 0.0)
    _verifier("sel : condiment sans calories", float(res.produits["sel"]["kcal_kg"]) == 0.0)
    var tr_ok := true
    for id in res.produits:
        var t: String = res.produits[id].get("transforme_de", "")
        if t != "" and not res.produits.has(t):
            tr_ok = false
    _verifier("produits transformés : leur produit de départ existe (karité -> beurre, néré -> soumbala...)", tr_ok)
    # 2. Équivalence : 1 kgEM récolté = même énergie, quel que soit le produit.
    var r2 = RESSOURCES.new()
    r2.aliments = {}
    r2._recolter(10.0, {"gibier": 0.5, "fonio_sauvage": 0.5})
    _verifier("10 kgEM récoltés = 10 kgEM en stock (%.2f) ; gibier %.1f kg, fonio %.1f kg" % [r2.total_aliments(), r2.aliments["gibier"], r2.aliments["fonio_sauvage"]], absf(r2.total_aliments() - 10.0) < 0.001)
    # Sauvegarde : produits et sel relus à l'identique ; ancienne sauvegarde convertie.
    var r4 = RESSOURCES.new()
    r4.aliments = {"gibier": 12.5, "miel": 3.0, "fonio_sauvage": 80.0}
    r4.stocks["nourriture"] = r4.total_aliments()
    r4.stocks["sel"] = 7.5
    r4.jours_sans_sel = 3
    var r5 = RESSOURCES.new()
    r5.depuis_dict(JSON.parse_string(JSON.stringify(r4.vers_dict())))
    _verifier("sauvegarde : produits, sel et jours sans sel relus à l'identique", r5.aliments == r4.aliments and r5.stocks["sel"] == 7.5 and r5.jours_sans_sel == 3)
    var r6 = RESSOURCES.new()
    r6.depuis_dict({"stocks": {"nourriture": 250.0, "eau": 100.0, "bois": 50.0}})
    _verifier("ancienne sauvegarde : 250 kg de nourriture -> %.0f kgEM de fonio sauvage, sel de départ gardé" % r6.total_aliments(), absf(r6.total_aliments() - 250.0) < 0.01 and r6.aliments.has("fonio_sauvage"))
    # 3. Simulations
    var faim := 0
    var soif := 0
    var interdits := 0
    var sel_monte := 0
    var morts_sante0_sans_faim := 0
    var sante_min := 100.0
    var jours_sans_sel_max := 0
    var eteints := 0
    var compo := {}    # mois -> {produit: kgEM}
    var pop_fin := 0
    for g in [2026, 1, 2, 3, 4, 5, 6, 7, 8, 9]:
        var t = TEMPS.new()
        var pop = POPULATION.new()
        var res3 = RESSOURCES.new()
        var cons = CONSTRUCTION.new()
        res3.construction = cons
        var b = BESOINS.new()
        pop.creer_clan_initial(0, g)
        cons.etat_initial()
        pop.deces.connect(func(h): if int(h["sante"]) <= 0 and not res3.faim and not res3.soif: morts_sante0_sans_faim += 1)
        for an in 100:
            for j in 360:
                t.jour_total += 1
                var pluie: bool = t.saison_des_pluies()
                var chantier: bool = not cons.chantiers.is_empty()
                var sel_avant: float = res3.stocks["sel"]
                res3.jour_passe(pop, t.jour_total, pluie, chantier)
                if res3.stocks["sel"] > sel_avant + 0.0001:
                    sel_monte += 1
                for id in JAMAIS_PRODUITS:
                    if res3.aliments.has(id):
                        interdits += 1
                if res3.faim: faim += 1
                if res3.soif: soif += 1
                jours_sans_sel_max = maxi(jours_sans_sel_max, res3.jours_sans_sel)
                var w := 0.0
                for h in pop.habitants:
                    if h["metier"] == "bâtisseur":
                        w += 0.6 + float(h["competence"]) / 100.0 * 0.8
                cons.jour_passe(w)
                pop.jour_passe(res3.faim, res3.soif, res3.jours_sans_sel)
                if t.jour_total % 30 == 0:
                    var m: int = ((t.jour_total - 1) / 30) % 12
                    var c: Dictionary = compo.get(m, {})
                    for id in res3.aliments:
                        c[id] = float(c.get(id, 0.0)) + float(res3.aliments[id]) * res3.facteur(id)
                    compo[m] = c
                    for h in pop.habitants:
                        sante_min = minf(sante_min, float(h["sante"]))
                    cons.mois_passe(res3)
                    pop.mois_passe(t.jour_total, res3.stocks["nourriture"] > 100.0, int(cons.effet_total("logement")))
                    b.mois_passe(pop, res3, cons, t.jour_total, pluie, chantier)
                    if cons.chantiers.is_empty():
                        for p in b.problemes:
                            if p["type"] == "logement" and p["solutions"].size() > 0:
                                b.appliquer(p["solutions"][0])
                    pop.repartir(t.jour_total)
            if pop.habitants.is_empty():
                eteints += 1
                break
        pop_fin += pop.habitants.size()
    print("--- Composition moyenne du stock de nourriture (part de l'énergie) ---")
    var noms := ["janv", "févr", "mars", "avr", "mai", "juin", "juil", "août", "sept", "oct", "nov", "déc"]
    for m in 12:
        var c: Dictionary = compo.get(m, {})
        var total := 0.0
        for id in c:
            total += c[id]
        var ids := c.keys()
        ids.sort_custom(func(a, b2): return c[a] > c[b2])
        var l: PackedStringArray = []
        for id in ids.slice(0, 4):
            l.append("%s %d %%" % [res.nom_produit(id), int(100.0 * c[id] / total)])
        print("  %s : %s" % [noms[m], ", ".join(l)])
    print("Population finale moyenne : %.0f habitants, clans éteints : %d/10" % [pop_fin / 10.0, eteints])
    _verifier("0 jour de faim et 0 jour de soif (faim %d, soif %d)" % [faim, soif], faim == 0 and soif == 0)
    _verifier("aucun clan éteint", eteints == 0)
    _verifier("sel, blé, raisin, mangue, orange, maïs... jamais produits sur place", interdits == 0 and sel_monte == 0)
    _verifier("manque de sel : santé plafonnée au plus bas à %.0f (attendu 60 et plus), après %d jours sans sel" % [sante_min, jours_sans_sel_max], sante_min >= 59.0)
    _verifier("le manque de sel seul ne tue personne (%d)" % morts_sante0_sans_faim, morts_sante0_sans_faim == 0)
    print("RÉSULTAT : %d réussis, %d ratés" % [ok, rate])
    quit()

func _verifier(nom: String, condition: bool) -> void:
    if condition:
        ok += 1
    else:
        rate += 1
    print("%s %s" % ["OK  " if condition else "RATÉ", nom])
