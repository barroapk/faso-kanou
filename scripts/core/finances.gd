extends RefCounted

# Comptabilité du clan (v0.3.59). Un JOURNAL, pas une caisse :
#  - aucune monnaie, aucune deuxième réserve : la trésorerie est la valeur de la réserve commune
#    existante (budget.caisse), exprimée en kg de mil équivalent (kgEM) ;
#  - chaque flux est écrit UNE seule fois (jour, origine, valeur au moment de l'opération) ;
#    une variation de prix n'est donc jamais comptée comme une recette ;
#  - recettes : l'impôt perçu (l'or et les ventes entrent dans la base imposable) ;
#    dépenses : chantiers, entretien (quelle que soit la source des biens) et salaires des fonctions ;
#  - réserve : totale = valeur de la caisse ; mobilisable = ce que le gouvernement peut dépenser ;
#    affectée = biens de la caisse qui ne peuvent pas servir (normalement rien) ;
#  - santé financière en JOURS de réserve = réserve mobilisable / dépenses moyennes (30 jours) ;
#  - salaires impayés : ils s'accumulent (arriérés) et sont payés en premier dès que possible.
# Ce module n'a aucun effet sur le jeu sauf les salaires ; les conséquences d'une crise viendront ensuite.

signal evenement(texte)

const JOURS_MOYENNE := 30
const JOURS_GARDES := 60
const TARIF_SALAIRE := 2.0        # kgEM par jour pour un temps plein (à régler à la campagne finale)
const SEUIL_STABLE := 60.0
const SEUIL_ALERTE := 20.0
const ORIGINES_DEPENSE := ["construction", "entretien", "salaires"]

var eco = null                    # economie.gd (valeurs des biens)
var jour := 0
var debut := -1                   # premier jour comptabilisé
var jours := {}                   # jour -> {"rec": {origine: kgEM}, "dep": {origine: kgEM}}
var arrieres := 0.0
var dernier_salaire := -1
var statut_notifie := ""

func _valeur(id: String, q: float) -> float:
    if eco == null:
        return 0.0
    return float(eco.valeur(id, q))

# Une opération réelle, écrite une seule fois. sens : "rec" ou "dep".
func noter(sens: String, origine: String, id: String, q: float) -> void:
    if q <= 0.0:
        return
    var v := _valeur(id, q)
    if v <= 0.0:
        return
    _ecrire(sens, origine, v)

func _ecrire(sens: String, origine: String, kgem: float) -> void:
    var cle := str(jour)
    if not jours.has(cle):
        jours[cle] = {"rec": {}, "dep": {}}
    jours[cle][sens][origine] = float(jours[cle][sens].get(origine, 0.0)) + kgem

# Totaux par origine sur les n derniers jours (jour courant inclus).
func total(sens: String, n: int) -> Dictionary:
    var t := {}
    for k in jours:
        var j := int(k)
        if j > jour - n and j <= jour:
            for o in jours[k][sens]:
                t[o] = float(t.get(o, 0.0)) + float(jours[k][sens][o])
    return t

func somme(d: Dictionary) -> float:
    var s := 0.0
    for o in d:
        s += float(d[o])
    return s

func solde(n: int) -> float:
    return somme(total("rec", n)) - somme(total("dep", n))

# Dépenses moyennes par jour : sur 30 jours, ou sur les jours écoulés au démarrage.
func depenses_moyennes() -> float:
    var n := clampi(jour - debut + 1, 1, JOURS_MOYENNE) if debut >= 0 else 1
    return somme(total("dep", n)) / float(n)

# Engagements prévisibles par jour : salaires + entretien des bâtiments (30 jours par mois).
func engagements_jour(c) -> float:
    var e := salaires_jour(c)
    for b in c.construction.batiments:
        var cout: Dictionary = c.construction._niveau(b["type"], int(b["niveau"]))["entretien"]
        for id in cout:
            e += _valeur(str(id), float(cout[id])) / 30.0
    return e

func salaires_jour(c) -> float:
    var s := 0.0
    for h in c.population.habitants:
        if h.has("fonction") and typeof(h["fonction"]) == TYPE_DICTIONARY:
            s += float(h["fonction"].get("temps", 0.0)) * TARIF_SALAIRE
    return s

# Le budget public existe dès qu'un impôt est fixé ou que la réserve commune contient quelque chose.
# Avant cela, chantiers et entretien se prennent sur les stocks des habitants, et les responsables
# servent par coutume, sans salaire : aucune crise financière n'est possible sans budget public.
func budget_actif(c) -> bool:
    return float(c.budget.taux) > 0.0001 or not c.budget.caisse.is_empty() or arrieres > 0.0001

# Catégories comptables appliquées à la réserve commune existante.
func reserve(c) -> Dictionary:
    var totale := 0.0
    var affectee := 0.0
    for id in c.budget.caisse:
        var v := _valeur(str(id), float(c.budget.caisse[id]))
        totale += v
        if not c.budget._prelevable(c.ressources, str(id)):
            affectee += v
    return {"totale": totale, "affectee": affectee, "mobilisable": totale - affectee}

# Santé financière : stable / alerte / critique / incapacite / sans (aucun engagement).
func etat(c) -> Dictionary:
    var r := reserve(c)
    if not budget_actif(c):
        return {"code": "sans", "jours": -1.0, "reserve": r, "reference": 0.0}
    var ref := depenses_moyennes()
    if ref <= 0.0001:
        ref = engagements_jour(c)
    var code := "sans"
    var jr := -1.0
    if ref > 0.0001:
        jr = float(r["mobilisable"]) / ref
        if float(r["mobilisable"]) <= 0.0001:
            code = "incapacite"
        elif jr >= SEUIL_STABLE:
            code = "stable"
        elif jr >= SEUIL_ALERTE:
            code = "alerte"
        else:
            code = "critique"
    return {"code": code, "jours": jr, "reserve": r, "reference": ref}

# Chaque jour : paie les salaires (arriérés d'abord), puis surveille la santé financière.
func jour_passe(c, j: int) -> void:
    jour = j
    if debut < 0:
        debut = j
    if dernier_salaire != j:
        dernier_salaire = j
        _payer(c)
    var e := etat(c)
    if str(e["code"]) != statut_notifie:
        var avant := statut_notifie
        statut_notifie = str(e["code"])
        if avant != "" or statut_notifie != "stable":
            _annoncer(e)
    var vieux := j - JOURS_GARDES
    for k in jours.keys():
        if int(k) <= vieux:
            jours.erase(k)

func _annoncer(e: Dictionary) -> void:
    match str(e["code"]):
        "stable":
            evenement.emit("Finances : situation stable (%d jours de réserve)." % int(e["jours"]))
        "alerte":
            evenement.emit("Finances : alerte, %d jours de réserve seulement." % int(e["jours"]))
        "critique":
            evenement.emit("Finances : situation critique, %d jours de réserve." % int(maxf(0.0, e["jours"])))
        "incapacite":
            evenement.emit("Finances : la réserve commune est épuisée, le clan ne peut plus payer.")

# Salaire en nature : la valeur sort de la réserve commune et passe aux stocks des habitants
# (un transfert, rien n'est détruit). Ce qui ne peut pas être payé devient arriéré.
func _payer(c) -> void:
    if not budget_actif(c):
        return
    var du := salaires_jour(c) + arrieres
    if du <= 0.0001:
        arrieres = 0.0
        return
    var reste := du
    var ids: Array = c.budget.caisse.keys()
    ids.sort_custom(func(a, b): return _valeur(str(a), c.budget.quantite(str(a))) > _valeur(str(b), c.budget.quantite(str(b))))
    for id in ids:
        if reste <= 0.0001:
            break
        var sid := str(id)
        var vu := _valeur(sid, 1.0)
        if vu <= 0.0 or not c.budget._prelevable(c.ressources, sid):
            continue
        var q := minf(c.budget.quantite(sid), reste / vu)
        var pris: float = c.budget.depenser(sid, q, "salaires")
        if pris <= 0.0:
            continue
        c.ressources.ajouter(sid, pris, "salaire")
        reste -= pris * vu
        _ecrire("dep", "salaires", pris * vu)
    var avant := arrieres
    arrieres = maxf(0.0, reste)
    if arrieres > 0.0001 and avant <= 0.0001:
        evenement.emit("Finances : salaires impayés, la réserve commune ne suffit pas.")

func _nom(o: String) -> String:
    return {"impot": "impôt", "construction": "chantiers", "entretien": "entretien", "salaires": "salaires"}.get(o, o)

func _liste(d: Dictionary) -> String:
    var l: PackedStringArray = []
    for o in d:
        l.append("%s %d" % [_nom(str(o)), int(round(float(d[o])))])
    return ", ".join(l) if not l.is_empty() else "rien"

func texte(c) -> String:
    var e := etat(c)
    var r: Dictionary = e["reserve"]
    var rec := total("rec", JOURS_MOYENNE)
    var dep := total("dep", JOURS_MOYENNE)
    var n := clampi(jour - debut + 1, 1, JOURS_MOYENNE) if debut >= 0 else 1
    var noms := {"stable": "stable", "alerte": "ALERTE", "critique": "CRITIQUE", "incapacite": "INCAPACITÉ DE PAYER", "sans": "pas encore de budget public"}
    var s := "Comptabilité (en kg de mil équivalent). Sur les %d derniers jours : recettes %d (%s), dépenses %d (%s), solde %+d, soit %+.1f par jour.\n" % [n, int(round(somme(rec))), _liste(rec), int(round(somme(dep))), _liste(dep), int(round(somme(rec) - somme(dep))), (somme(rec) - somme(dep)) / float(n)]
    s += "Réserve : totale %d, mobilisable %d, affectée %d. " % [int(round(float(r["totale"]))), int(round(float(r["mobilisable"]))), int(round(float(r["affectee"])))]
    s += "Santé financière : %s" % noms.get(str(e["code"]), "?")
    if float(e["jours"]) >= 0.0:
        s += " (%d jours de réserve, dépenses de référence %.1f par jour)" % [int(e["jours"]), float(e["reference"])]
    s += "."
    if arrieres > 0.0001:
        s += " Salaires impayés : %d." % int(round(arrieres))
    return s

func vers_dict() -> Dictionary:
    return {"jour": jour, "debut": debut, "jours": jours, "arrieres": arrieres, "dernier_salaire": dernier_salaire, "statut": statut_notifie}

func depuis_dict(d: Dictionary) -> void:
    jour = int(d.get("jour", 0))
    debut = int(d.get("debut", -1))
    arrieres = float(d.get("arrieres", 0.0))
    dernier_salaire = int(d.get("dernier_salaire", -1))
    statut_notifie = str(d.get("statut", ""))
    jours = {}
    for k in d.get("jours", {}):
        var x: Dictionary = d["jours"][k]
        var e := {"rec": {}, "dep": {}}
        for s in ["rec", "dep"]:
            for o in x.get(s, {}):
                e[s][str(o)] = float(x[s][o])
        jours[str(int(k))] = e
