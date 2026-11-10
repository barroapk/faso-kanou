extends SceneTree

# Sauvegarde et chargement avec filiation, couples, archives et migration.
# 1. Partie de 25 ans, sauvegarde, relecture : tout est identique.
# 2. On continue 10 ans les deux parties (originale et relue) : mêmes naissances,
#    mêmes décès, mêmes couples (le hasard reprend exactement au même point).
# 3. Une ancienne sauvegarde (version 3, sans couples) se charge sans erreur.
const CIV = preload("res://scripts/core/civilisation.gd")

var ok := 0
var rate := 0

func _empreinte(c) -> String:
    var ids := []
    for h in c.population.habitants:
        ids.append("%d:%d:%d" % [h["id"], h["pere"], h["mere"]])
    var cs := []
    for k in c.population.couples:
        cs.append("%d-%d-%d-%d-%d" % [k["mari"], k["femme"], k["debut"], k["fin"], k["enfants"].size()])
    return "%s|%s|%d" % [",".join(ids), ",".join(cs), c.population._archives.size()]

func _initialize() -> void:
    var a = CIV.new()
    a._nouvelle()
    a._brancher()
    a.construction.batiments.append({"type": "hutte", "niveau": 1, "etat": 100})
    a.construction.batiments.append({"type": "hutte", "niveau": 1, "etat": 100})
    for i in 25 * 360:
        a.temps._passer_un_jour()
    a.sauvegarder()
    var b = CIV.new()
    _verifier("relecture de la sauvegarde", b._charger(a.FICHIER))
    print("   habitants %d, couples %d, archives %d" % [a.population.habitants.size(), a.population.couples.size(), a.population._archives.size()])
    _verifier("habitants, parents, couples et archives identiques", _empreinte(a) == _empreinte(b))
    var avec_parents := 0
    var nes := 0
    for h in b.population.habitants:
        if int(h["id"]) > 10:
            nes += 1
            if int(h["pere"]) >= 0 and int(h["mere"]) >= 0:
                avec_parents += 1
    _verifier("après relecture : %d/%d enfants nés en jeu ont père et mère" % [avec_parents, nes], avec_parents == nes)
    _verifier("migration relue (désactivée)", b.migration.actif == false and a.migration.actif == false)
    b._brancher()
    b.temps.vitesse = a.temps.vitesse
    for i in 10 * 360:
        a.temps._passer_un_jour()
        b.temps._passer_un_jour()
    _verifier("10 ans de plus : même histoire dans les deux parties", _empreinte(a) == _empreinte(b))
    # Ancienne sauvegarde (v3) : pas de couples, pas de pere/mere.
    var vieux := {"version": 3, "temps": {"jour_total": 400}, "population": {"habitants": [], "prochain_id": 1}}
    var p := []
    for h in a.population.habitants.slice(0, 6):
        var x: Dictionary = h.duplicate()
        x.erase("pere")
        x.erase("mere")
        p.append(x)
    vieux["population"]["habitants"] = p
    vieux["population"]["prochain_id"] = a.population.prochain_id
    var f := FileAccess.open("user://vieux.json", FileAccess.WRITE)
    f.store_string(JSON.stringify(vieux))
    f.close()
    var c = CIV.new()
    _verifier("ancienne sauvegarde (v3) chargée", c._charger("vieux.json"))
    _verifier("ancienne sauvegarde : parents inconnus = -1, aucun couple", c.population.habitants.all(func(h): return int(h["pere"]) == -1) and c.population.couples.is_empty())
    c._brancher()
    for i in 2 * 360:
        c.temps._passer_un_jour()
    _verifier("ancienne sauvegarde : 2 ans de jeu sans erreur", true)
    a.free()
    b.free()
    c.free()
    print("RÉSULTAT : %d réussis, %d ratés" % [ok, rate])
    quit()

func _verifier(nom: String, condition: bool) -> void:
    if condition:
        ok += 1
    else:
        rate += 1
    print("%s %s" % ["OK  " if condition else "RATÉ", nom])
