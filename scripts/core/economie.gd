extends RefCounted

# Richesse collective et comptabilité (v0.3.13).
# La richesse appartient au clan, jamais à une personne. Quatre notions :
#   trésorerie  : la monnaie réellement détenue (cauris, or) ; vide au début ;
#   stocks      : la valeur des ressources et produits (nourriture, eau, bois...) ;
#   patrimoine  : bâtiments et outils (valeur selon leur état) ;
#   comptabilité: chaque mois, tous les mouvements par motif (production,
#                 consommation, pertes, fabrication, construction, échanges...).
# Valeurs en "kg de mil" (valeur 1 du catalogue). Pas de monnaie au départ :
# on échange par troc. Rien n'est compté deux fois : la monnaie n'est pas
# dans les stocks, les outils ne sont que dans le patrimoine.
# Contrôle : pour chaque ressource, stock de fin = stock de début + somme des
# mouvements notés. Tout écart (création ou disparition sans origine) est signalé.

signal evenement(texte)

const MONNAIES := ["cauris", "or_alluvionnaire", "or_fondu"]
const JOURNAL_MAX := 24
const ECART_TOLERE := 0.01

var valeurs := {}
var journal: Array = []        # un résumé par mois
var historique: Array = []     # indicateurs, un par an
var transactions: Array = []   # échanges avec d'autres clans
var _depart := {}              # quantités au début du mois
var anomalies := 0

func _init() -> void:
    var c = JSON.parse_string(FileAccess.get_file_as_string("res://data/produits.json"))
    if typeof(c) == TYPE_DICTIONARY:
        for id in c.get("produits", {}):
            valeurs[id] = float(c["produits"][id].get("valeur", 0.0))

func valeur(id: String, q: float) -> float:
    return q * float(valeurs.get(id, 0.0))

# ---------- Indicateurs ----------

func tresorerie(res) -> float:
    var t := 0.0
    for m in MONNAIES:
        t += valeur(m, res.quantite(m))
    return t

func valeur_stocks(res) -> float:
    var t := 0.0
    for id in res.aliments:
        t += valeur(id, float(res.aliments[id]))
    for r in ["eau", "bois", "sel"]:
        t += valeur(r, float(res.stocks[r]))
    for id in res.objets:
        if not MONNAIES.has(id):
            t += valeur(id, float(res.objets[id]))
    return t

func patrimoine(cons, eq) -> float:
    var t := 0.0
    for b in cons.batiments:
        var niv: Dictionary = cons._niveau(b["type"], int(b["niveau"]))
        var cout := 0.0
        for r in niv["cout"]:
            cout += valeur(r, float(niv["cout"][r]))
        t += cout * float(b["etat"]) / 100.0
    if eq != null:
        for o in eq.instances:
            var vie := float(eq.definitions[o["id"]]["durabilite"])
            t += valeur(o["id"], 1.0) * float(o["durabilite"]) / vie
    return t

# Production possible par jour, en valeur, avec les travailleurs actuels.
func capacite_productive(pop, res) -> float:
    var t := 0.0
    for h in pop.habitants:
        var p: Dictionary = res.PRODUCTION.get(h["metier"], {})
        var eff := (0.6 + float(h["competence"]) / 100.0 * 0.8) * float(h.get("bonus_outil", 1.0))
        for r in p:
            var q: float = (float(p[r][0]) + float(p[r][1])) / 2.0 * eff
            t += q * (1.0 if r == "nourriture" else float(valeurs.get(r, 0.0)))
    return t

func indicateurs(pop, res, cons, eq, jour: int) -> Dictionary:
    var tr := tresorerie(res)
    var st := valeur_stocks(res)
    var pa := patrimoine(cons, eq)
    var ca: float = res.budget.valeur(self) if res.budget != null else 0.0
    var au: Dictionary = res.autonomie(pop, jour)
    return {
        "jour": jour,
        "tresorerie": tr,
        "stocks": st,
        "patrimoine": pa,
        "caisse": ca,
        "richesse": tr + st + pa + ca,
        "autonomie_nourriture": minf(9999.0, float(au["nourriture"])),
        "autonomie_eau": minf(9999.0, float(au["eau"])),
        "capacite_productive": capacite_productive(pop, res),
    }

# ---------- Comptabilité ----------

func _photo(res) -> Dictionary:
    var p := {"nourriture": res.total_aliments(), "eau": float(res.stocks["eau"]), "bois": float(res.stocks["bois"]), "sel": float(res.stocks["sel"])}
    for id in res.objets:
        p[id] = float(res.objets[id])
    return p

func commencer(res) -> void:
    _depart = _photo(res)
    res.flux = {}

# Fin du mois : contrôle des écarts, résumé dans le journal, nouveau départ.
func mois_passe(pop, res, cons, eq, jour: int) -> void:
    var fin := _photo(res)
    var mouvements := {}
    for motif in res.flux:
        for r in res.flux[motif]:
            mouvements[r] = float(mouvements.get(r, 0.0)) + float(res.flux[motif][r])
    var ecarts := {}
    var cles := {}
    for r in fin:
        cles[r] = true
    for r in _depart:
        cles[r] = true
    for r in mouvements:
        cles[r] = true
    for r in cles:
        var e: float = float(fin.get(r, 0.0)) - float(_depart.get(r, 0.0)) - float(mouvements.get(r, 0.0))
        if absf(e) > ECART_TOLERE:
            ecarts[r] = e
    if not ecarts.is_empty():
        anomalies += 1
    journal.append({"jour": jour, "flux": res.flux.duplicate(true), "ecarts": ecarts, "indicateurs": indicateurs(pop, res, cons, eq, jour)})
    while journal.size() > JOURNAL_MAX:
        journal.pop_front()
    if jour % 360 == 0:
        historique.append(indicateurs(pop, res, cons, eq, jour))
    commencer(res)

# ---------- Troc entre deux clans ----------
# Un échange a toujours deux côtés : ce que A donne, B le reçoit, et l'inverse.
# Rien n'est créé. Renvoie "" si c'est fait, sinon la raison du refus.
static func echanger(eco_a, res_a, eco_b, res_b, a_donne: Dictionary, b_donne: Dictionary, jour: int, id_transaction: String) -> String:
    for r in a_donne:
        if res_a.quantite(r) + 0.000001 < float(a_donne[r]):
            return "Le premier clan n'a pas assez de %s." % r
    for r in b_donne:
        if res_b.quantite(r) + 0.000001 < float(b_donne[r]):
            return "Le second clan n'a pas assez de %s." % r
    for r in a_donne:
        res_a.retirer(r, float(a_donne[r]), "echange")
        res_b.ajouter(r, float(a_donne[r]), "echange")
    for r in b_donne:
        res_b.retirer(r, float(b_donne[r]), "echange")
        res_a.ajouter(r, float(b_donne[r]), "echange")
    var t := {"id": id_transaction, "jour": jour, "a_donne": a_donne.duplicate(), "b_donne": b_donne.duplicate()}
    eco_a.transactions.append(t)
    eco_b.transactions.append(t.duplicate(true))
    return ""

# ---------- Sauvegarde ----------

func vers_dict() -> Dictionary:
    return {"journal": journal, "historique": historique, "transactions": transactions, "depart": _depart, "anomalies": anomalies}

func depuis_dict(d: Dictionary, res) -> void:
    journal = d.get("journal", [])
    historique = d.get("historique", [])
    transactions = d.get("transactions", [])
    anomalies = int(d.get("anomalies", 0))
    if d.has("depart"):
        _depart = {}
        for r in d["depart"]:
            _depart[str(r)] = float(d["depart"][r])
    else:
        commencer(res)
