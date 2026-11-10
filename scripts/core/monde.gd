extends RefCounted

# Monde de départ (v0.3.16 D1).
# Le joueur arrive dans un archipel déjà habité : chaque île libre (sauf la
# sienne) a un clan installé avant lui. Rien n'est inventé sans origine :
# chaque clan a une île, une date d'arrivée (5 à 60 ans avant le joueur) et
# une histoire. Son état (habitants, huttes, stocks, outils, savoirs, champs)
# est déduit de son ancienneté et de la richesse de son île, avec les mêmes
# règles que la simulation (consommation par jour, 5 habitants par hutte,
# 2 ha par cultivateur...). On ne simule pas ces années une par une.

const NOMS := ["OUÉDRAOGO", "SAWADOGO", "KABORÉ", "ZONGO", "COMPAORÉ", "ILBOUDO", "NIKIÉMA", "TAPSOBA", "OUATTARA", "KAMBOU", "SOMÉ", "DABIRÉ", "HIEN", "SIDIBÉ", "YAMÉOGO", "ZOUNGRANA", "BAMOGO", "KIEMDE", "GUIRO", "DAH"]
const PRENOMS_H := ["Adama", "Boukary", "Issa", "Salif", "Hamidou", "Souleymane", "Ousmane", "Inoussa", "Lassané", "Tiga", "Noufou", "Rasmané", "Saïdou", "Moumouni", "Karim", "Yacouba", "Drissa", "Seydou", "Mahamadi", "Arouna"]
const PRENOMS_F := ["Aminata", "Fatimata", "Mariam", "Awa", "Safiatou", "Rasmata", "Habibou", "Bibata", "Alizèta", "Kadidia", "Salamata", "Zénabo", "Haoua", "Ramata", "Fanta", "Assétou", "Maïmouna", "Nafissatou", "Djénéba", "Odile"]
const ORIGINES := ["venu du continent par la mer", "parti d'une île lointaine après une famine", "descendant de pêcheurs installés sur la côte", "venu de l'est après une guerre entre familles", "arrivé sur les pirogues d'un ancien marchand"]
const CROISSANCE_AN := 0.02     # croissance moyenne d'un petit clan (naissances - décès)
const POP_MAX := 30

# Une fiche de clan au même format que data/clans.json.
static func generer(ile_id: String, ile: Dictionary, rng: RandomNumberGenerator, noms_pris: Array) -> Dictionary:
    var anciennete := rng.randi_range(5, 60)
    var fondateurs := rng.randi_range(6, 12)
    var n := clampi(int(round(fondateurs * pow(1.0 + CROISSANCE_AN, anciennete))), 6, POP_MAX)
    var r: Dictionary = ile.get("richesse", {})
    var noms_libres: Array = NOMS.filter(func(x): return not noms_pris.has(x))
    for i in range(noms_libres.size() - 1, 0, -1):   # mélange tiré de la graine du monde
        var j := rng.randi_range(0, i)
        var x = noms_libres[i]
        noms_libres[i] = noms_libres[j]
        noms_libres[j] = x
    # ---------- Familles ----------
    var liste: Array = []
    var couples: Array = []
    var famille := 0
    while liste.size() < n:
        famille += 1
        var nom: String = noms_libres[(famille - 1) % noms_libres.size()]
        if famille == 1:
            noms_pris.append(nom)
        var age_h := rng.randi_range(22, 55)
        var age_f := maxi(18, age_h - rng.randi_range(2, 9))
        var p := liste.size()
        liste.append({"prenom": PRENOMS_H[rng.randi() % PRENOMS_H.size()], "nom": nom, "sexe": "H", "age": age_h, "famille": famille, "metier": "sans métier"})
        liste.append({"prenom": PRENOMS_F[rng.randi() % PRENOMS_F.size()], "nom": nom, "sexe": "F", "age": age_f, "famille": famille, "metier": "sans métier"})
        couples.append([p, p + 1, mini(age_f - 17, rng.randi_range(2, 25))])
        var age_enfant := mini(age_f - 17, rng.randi_range(1, 16))
        var nb_enfants := 0
        while age_enfant >= 0 and liste.size() < n and nb_enfants < rng.randi_range(1, 4):
            nb_enfants += 1
            var sexe := "H" if rng.randf() < 0.5 else "F"
            var prenoms: Array = PRENOMS_H if sexe == "H" else PRENOMS_F
            var adulte := age_enfant >= 14
            liste.append({"prenom": prenoms[rng.randi() % prenoms.size()], "nom": nom, "sexe": sexe, "age": age_enfant, "famille": famille,
                "metier": "sans métier" if adulte else "enfant", "initie": "" if adulte else "cueilleur", "pere": p, "mere": p + 1})
            age_enfant -= rng.randi_range(2, 4)
        # Un frère ou une sœur adulte du mari vit souvent avec la famille.
        if liste.size() < n and rng.randf() < 0.5:
            var sx := "H" if rng.randf() < 0.5 else "F"
            liste.append({"prenom": (PRENOMS_H if sx == "H" else PRENOMS_F)[rng.randi() % 20], "nom": nom, "sexe": sx, "age": rng.randi_range(15, 30), "famille": famille, "metier": "sans métier"})
        if liste.size() < n and rng.randf() < 0.2:
            liste.append({"prenom": PRENOMS_H[rng.randi() % PRENOMS_H.size()], "nom": nom, "sexe": "H", "age": rng.randi_range(58, 70), "famille": famille, "metier": "ancien"})
    liste.resize(n)
    for f in liste:
        if f.has("pere") and int(f["pere"]) >= n:
            f.erase("pere")
            f.erase("mere")
    var c0: Array = couples.filter(func(c): return int(c[1]) < n)
    liste[0]["metier"] = "chef"
    # ---------- Métiers ----------
    var adultes := 0
    for f in liste:
        if f["metier"] == "sans métier":
            adultes += 1
    var connaissances: Array = []
    if anciennete >= 15 and rng.randf() < 0.3 + anciennete / 100.0:
        connaissances.append("agriculture")
    if anciennete >= 35 and float(r.get("bois", 1.0)) >= 0.8 and rng.randf() < 0.5:
        connaissances.append("charbonnage")
    if connaissances.has("agriculture") and anciennete >= 45 and rng.randf() < 0.3:
        connaissances.append("irrigation")
    # Mêmes rendements que la simulation : un porteur fournit l'eau d'environ
    # 8 personnes ; un bâtisseur le bois de 9 personnes (moins si l'île a peu
    # de forêt) ; le reste des adultes nourrit le clan.
    var amorti := func(k): return 0.5 + 0.5 * float(r.get(k, 1.0))
    var postes := {"porteur d'eau": mini(maxi(1, int(ceil(n / 8.0))), maxi(1, adultes - 1))}
    postes["bâtisseur"] = mini(int(ceil(n / (9.0 * amorti.call("bois")))), maxi(0, adultes - postes["porteur d'eau"] - 1))
    var reste: int = adultes - postes["porteur d'eau"] - postes["bâtisseur"]
    var cultivateurs := int(ceil(n / 4.0)) if connaissances.has("agriculture") else 0
    cultivateurs = mini(cultivateurs, maxi(0, reste - 1))
    if cultivateurs > 0:
        postes["cultivateur"] = cultivateurs
    reste -= cultivateurs
    # Chasse, pêche ou cueillette selon ce que l'île donne (rendement × richesse).
    var r_chasse: float = 3.0 * amorti.call("chasse")
    var r_peche: float = 3.0 * amorti.call("poisson")
    var r_cueil: float = 2.0 * amorti.call("cueillette")
    var total := r_chasse + r_peche + r_cueil
    postes["chasseur"] = int(floor(maxi(reste, 0) * r_chasse / total))
    postes["pêcheur"] = int(floor(maxi(reste, 0) * r_peche / total))
    postes["cueilleur"] = maxi(0, reste - postes["chasseur"] - postes["pêcheur"])
    # Au moins un pêcheur : il fait aussi le sel marin.
    if int(postes["pêcheur"]) == 0 and reste > 0:
        postes["pêcheur"] = 1
        if int(postes["cueilleur"]) > 0:
            postes["cueilleur"] = int(postes["cueilleur"]) - 1
        else:
            postes["chasseur"] = maxi(0, int(postes["chasseur"]) - 1)
    # ---------- Chacun son métier (et le savoir qui va avec) ----------
    var a_donner: Array = []
    for m in ["pêcheur", "chasseur", "cultivateur", "cueilleur", "porteur d'eau", "bâtisseur"]:
        for k in int(postes.get(m, 0)):
            a_donner.append(m)
    for f in liste:
        if f["metier"] == "sans métier" and not a_donner.is_empty():
            f["metier"] = a_donner.pop_front()
    # ---------- Un clan qui a duré sait se nourrir ----------
    # S'il y a trop de bouches pour les bras, les plus jeunes enfants ne sont
    # pas là (le clan est resté plus petit) : on retire les plus jeunes.
    var rendement := {"chasseur": 3.0 * amorti.call("chasse"), "pêcheur": 3.0 * amorti.call("poisson"),
        "cueilleur": 2.0 * amorti.call("cueillette"), "cultivateur": 1.5 * amorti.call("cueillette")}
    while true:
        var prod := 0.0
        var conso := 0.0
        for f in liste:
            var age := int(f["age"])
            conso += 0.8 if age >= 14 else 0.5
            prod += float(rendement.get(f["metier"], 0.0)) * (0.6 + minf(70.0, age * 2.0) / 100.0 * 0.8)
            if f["metier"] == "enfant" and age >= 8:
                prod += 0.5
        if prod >= conso * 1.05:
            break
        var plus_jeune := -1
        for i in liste.size():
            if liste[i]["metier"] == "enfant" and (plus_jeune < 0 or int(liste[i]["age"]) < int(liste[plus_jeune]["age"])):
                plus_jeune = i
        if plus_jeune < 0:
            break
        liste.remove_at(plus_jeune)
        for f in liste:
            for cle in ["pere", "mere"]:
                if f.has(cle) and int(f[cle]) > plus_jeune:
                    f[cle] = int(f[cle]) - 1
        for c in c0:
            for k in 2:
                if int(c[k]) > plus_jeune:
                    c[k] = int(c[k]) - 1
    n = liste.size()
    # ---------- Biens accumulés ----------
    var age_village := minf(1.0, anciennete / 40.0)
    var stocks := {
        "nourriture": n * 0.7 * (30.0 + 60.0 * age_village) * float(r.get("cueillette", 1.0)),
        "eau": n * 4.5 * 10.0,
        "bois": n * 1.0 * (20.0 + 40.0 * age_village) * float(r.get("bois", 1.0)),
        "sel": n * 0.005 * (60.0 + 120.0 * float(r.get("sel", 1.0))),
    }
    var outils := {"hache_pierre": maxi(1, int(ceil(adultes / 4.0))), "arc": maxi(1, int(postes["chasseur"])), "lance": maxi(1, int(ceil(int(postes["chasseur"]) / 2.0)))}
    if anciennete >= 20:
        outils["meule"] = 1
    var fiche := {
        "nom": "Clan %s" % liste[0]["nom"],
        "chef_fixe": {},
        "origine": "%s, installé à %s il y a %d ans" % [ORIGINES[rng.randi() % ORIGINES.size()], str(ile.get("nom", ile_id)).replace("Île de ", "").replace("Îles de ", ""), anciennete],
        "anciennete": anciennete,
        "graine": rng.randi_range(10000, 99999),
        "fondateurs": liste,
        "couples": c0,
        "postes": postes,
        "huttes": int(ceil(n / 5.0)) + (1 if anciennete >= 25 else 0),
        "stocks": stocks,
        "outils": outils,
        "connaissances": connaissances,
        "ile": ile_id,
    }
    if connaissances.has("agriculture"):
        fiche["semences"] = {"mil": 5.0 * 2.0 * cultivateurs * 1.2, "sorgho": 8.0 * 2.0 * cultivateurs * 1.2}
        fiche["champs_ha"] = 2.0 * cultivateurs
        # Un clan qui cultive depuis longtemps a des greniers pour sa récolte.
        fiche["greniers"] = int(ceil(2.0 * cultivateurs * 600.0 / 1000.0))
    # Élevage (v0.3.38) : 4 clans anciens sur 10 élèvent depuis longtemps
    # (tiré de la graine du clan, sans changer le reste du monde).
    if anciennete >= 30 and int(fiche["graine"]) % 10 < 4:
        connaissances.append("elevage")
        fiche["troupeau"] = {"pintade": [2, 5], "chevre": [1, 3] if anciennete >= 40 else [0, 0]}
    return fiche
