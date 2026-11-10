extends SceneTree

# v0.3.9 : recettes et transformations.
const RECETTES = preload("res://scripts/core/recettes.gd")
const CATALOGUE = preload("res://scripts/core/catalogue.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")

var ok := 0
var rate := 0
var pop
var res
var cons
var rec

func _monde() -> void:
    pop = POPULATION.new()
    res = RESSOURCES.new()
    cons = CONSTRUCTION.new()
    res.construction = cons
    pop.creer_clan_initial(0)
    cons.etat_initial()
    rec = RECETTES.new()

func _jours(n: int, jour0: int) -> void:
    for i in n:
        rec.jour_passe(pop, res, jour0 + i)
        res.jour_passe(pop, jour0 + i, false, false)

func _initialize() -> void:
    var cat = CATALOGUE.new()
    rec = RECETTES.new()
    print("   %d recettes : %s" % [rec.definitions.size(), ", ".join(rec.definitions.keys())])
    # 1. Bilans de masse
    var faux := []
    for id in rec.definitions:
        var b: Dictionary = rec.bilan_masse(id)
        print("   %-13s entrée %6.2f kg = produits %6.2f kg + pertes %6.2f kg" % [id, b["entree"], b["sortie"], b["pertes"]])
        if absf(b["ecart"]) > 0.000001:
            faux.append(id)
    _verifier("bilan de masse exact pour toutes les recettes (entrée = produits + sous-produits + pertes)", faux.is_empty())
    var inconnus := []
    var mauvais_combustible := []
    for id in rec.definitions:
        var r: Dictionary = rec.definitions[id]
        for g in ["entrees", "combustible", "sorties", "sous_produits"]:
            for m in r[g]:
                if not cat.existe(m):
                    inconnus.append(m)
        for m in r["combustible"]:
            if m != "bois" and m != "charbon_bois":
                mauvais_combustible.append(m)
        if r["outil"] != "" and not cat.existe(r["outil"]):
            inconnus.append(r["outil"])
    _verifier("toutes les matières, sorties et outils existent dans le catalogue", inconnus.is_empty())
    _verifier("combustible séparé : seulement bois ou charbon de bois", mauvais_combustible.is_empty())
    _verifier("chaque recette demande du temps de travail", rec.definitions.values().all(func(r): return float(r["jours_travail"]) > 0.0))
    var age_pierre := ["cendres", "sel_vegetal", "canari", "brique_banco", "hache_pierre", "arc", "lance", "ramasser_pierre", "creuser_argile"]
    var plus_tard := ["fer_brut", "charbon_bois", "fil_coton", "tissu_coton", "farine_mil", "hache_fer", "houe_bois"]
    _verifier("connues au départ : seulement des savoir-faire de l'âge de la pierre (%d recettes)" % rec.connues.size(), age_pierre.all(func(x): return rec.connues.has(x)) and plus_tard.all(func(x): return not rec.connues.has(x)))
    # 2. Les 5 conditions séparées : fer brut
    _monde()
    var e: Dictionary = rec.etat("fer_brut", pop, res, cons, 0)
    print("   fer brut : %s" % " / ".join(e["raisons"]))
    _verifier("fer brut refusé : pas connu, pas de minerai ni de charbon, pas de fourneau", not e["possible"] and not e["connue"] and not e["matieres"] and not e["batiment"])
    rec.apprendre("fer_brut")
    e = rec.etat("fer_brut", pop, res, cons, 0)
    _verifier("connaître la recette ne suffit pas : toujours refusé (matières, fourneau)", not e["possible"] and e["connue"])
    # 3. Saison : brique de banco refusée en saison des pluies (juillet)
    e = rec.etat("brique_banco", pop, res, cons, 6 * 30 + 5)
    _verifier("brique de banco refusée en saison des pluies", not e["saison"])
    # 4. Chaîne réelle : canari -> cendres -> sel végétal
    _monde()
    pop.postes = {"chasseur": 1, "cueilleur": 2, "porteur d'eau": 1, "bâtisseur": 0}
    pop.repartir(0)
    res.ajouter("argile", 10.0)
    res.ajouter("paille", 200.0)
    res.stocks["eau"] = 300.0
    res.stocks["bois"] = 100.0
    var argile0: float = res.quantite("argile")
    var bois0: float = res.stocks["bois"]
    _verifier("sel végétal refusé sans canari (outil)", rec.commander("sel_vegetal", pop, res, cons, 0) != "")
    _verifier("canari lancé", rec.commander("canari", pop, res, cons, 0) == "")
    _verifier("matières retirées au lancement : argile -8, bois -6", absf(res.quantite("argile") - (argile0 - 8.0)) < 0.0001 and absf(res.stocks["bois"] - (bois0 - 6.0)) < 0.0001)
    _verifier("pas de canari tout de suite", res.quantite("canari") == 0.0)
    var libres: int = pop.habitants.filter(func(h): return h["metier"] == "sans métier" and pop.age(h, 0) >= 14).size()
    _jours(3, 1)
    print("   adultes libres : %d, canaris : %d" % [libres, res.quantite("canari")])
    _verifier("canari livré après le travail (2 jours-personne)", res.quantite("canari") == 1.0)
    var cendres_av: float = res.quantite("cendres")
    _verifier("cendres lancées (20 kg de paille)", rec.commander("cendres", pop, res, cons, 4, 10) == "")
    _jours(4, 4)
    _verifier("cendres obtenues : +10 kg (10 x 1 kg)", res.quantite("cendres") >= cendres_av + 10.0 - 0.001)
    var sv: float = res.quantite("sel_vegetal")
    _verifier("sel végétal lancé (canari + 10 kg de cendres + 20 L d'eau + 4 kg de bois)", rec.commander("sel_vegetal", pop, res, cons, 8) == "")
    _jours(2, 8)
    _verifier("le canari n'est pas consommé (outil)", res.quantite("canari") == 1.0)
    # 5. Sel végétal remplace le sel (à moitié)
    _monde()
    res.stocks["sel"] = 0.0
    res.ajouter("sel_vegetal", 1.0)
    var n: int = pop.habitants.size()
    res.jour_passe(pop, 0, false, false)
    _verifier("sans sel, le sel végétal est utilisé (x2) : pas de jour sans sel", res.jours_sans_sel == 0 and absf(res.quantite("sel_vegetal") - (1.0 - n * 0.005 / 0.5)) < 0.0001)
    # 6. Les cendres viennent du bois brûlé chaque jour
    _monde()
    var c0: float = res.quantite("cendres")
    for i in 30:
        res.jour_passe(pop, i, false, false)
    print("   cendres de 30 jours de foyers : %.2f kg" % (res.quantite("cendres") - c0))
    _verifier("le bois brûlé laisse des cendres (1,5 %)", res.quantite("cendres") > c0)
    # 7. Personne de libre : refus
    _monde()
    for h in pop.habitants:
        if h["metier"] == "sans métier":
            h["metier"] = "cueilleur"
    res.ajouter("argile", 10.0)
    _verifier("aucun adulte libre : canari refusé", rec.commander("canari", pop, res, cons, 0) == "Aucun adulte libre pour ce travail.")
    # 8. Sauvegarde
    _monde()
    res.ajouter("argile", 10.0)
    pop.postes["bâtisseur"] = 0
    pop.repartir(0)
    rec.commander("canari", pop, res, cons, 0)
    var rec2 = RECETTES.new()
    rec2.depuis_dict(JSON.parse_string(JSON.stringify(rec.vers_dict())))
    var res2 = RESSOURCES.new()
    res2.depuis_dict(JSON.parse_string(JSON.stringify(res.vers_dict())))
    _verifier("sauvegarde : recettes connues, commandes en cours et objets relus", rec2.connues == rec.connues and rec2.commandes == rec.commandes and res2.objets == res.objets)
    var vieux = RESSOURCES.new()
    vieux.depuis_dict({"stocks": {"nourriture": 100.0, "eau": 50.0, "bois": 20.0}})
    _verifier("ancienne sauvegarde sans objets : chargée, inventaire vide", vieux.objets.is_empty())
    print("RÉSULTAT : %d réussis, %d ratés" % [ok, rate])
    quit()

func _verifier(nom: String, condition: bool) -> void:
    if condition:
        ok += 1
    else:
        rate += 1
    print("%s %s" % ["OK  " if condition else "RATÉ", nom])
