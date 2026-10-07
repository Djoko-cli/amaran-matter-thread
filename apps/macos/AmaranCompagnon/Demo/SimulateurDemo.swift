// Pont simule du mode demo (spec 3b, section 8), sur le modele de SimulateurDemo de
// Halo Compagnon (commit e114cd5) : trois lampes (une dans Maison allumee, une
// eteinte et retiree de Maison, une jamais vue qui y entre a sa premiere reponse). Il
// repond comme le firmware (docs/PROTOCOLE-JSON.md) ; il sert aussi aux tests de bout
// en bout.
import AmaranProtocole
import CryptoKit
import Foundation

/// Memoire du pont simule (sa NVS) : elle survit a ses redemarrages.
struct MemoireDemo: Sendable {
    struct Lampe: Sendable, Equatable {
        var adresse: UInt16
        var mac: String
        var nom: String
        var code: UInt32
        var endpoint: Int?
        var vue: Bool
        var masquee = false
        /// Versions (jeton de `mesh lampe`) ; nil : inconnues.
        var logiciel: String?
        var ble: String?
    }

    var empreintes: (reseau: String, application: String)?
    /// Empreinte de la cle UDP (10.2) ; nil : pas de cle, port 5480 ferme. La cle
    /// elle-meme n'est jamais gardee par le simulateur : seule l'app la range.
    var empreinteUdp: String?
    var lampes: [Lampe]
    var releveMs = 2000
    var prochainEndpoint = 5
    /// Chargement en cours (`mesh cles`, `mesh lampes`, `mesh lampe`) : effet au redemarrage.
    var clesChargees: (reseau: String, application: String)?
    var brouillon: [Int: Lampe] = [:]
    var attendues = 0
    var listeChargee: [Lampe]?
    /// Faux : un pont d'avant la fiche des lampes (pas de capacite `logiciel`, pas de versions).
    var annonceLogiciel = true

    static var initiale: MemoireDemo {
        let r = ReseauDemo.reseau
        func l(_ i: Int, ep: Int?, vue: Bool, masquee: Bool = false) -> Lampe {
            let x = r.lampes[i]
            return Lampe(adresse: x.adresse, mac: x.mac, nom: x.nom, code: x.code, endpoint: ep, vue: vue, masquee: masquee,
                         logiciel: x.logiciel, ble: x.ble)
        }
        return MemoireDemo(empreintes: (r.empreinteReseau, r.empreinteApplication),
                           lampes: [l(0, ep: 2, vue: true), l(1, ep: 3, vue: true, masquee: true), l(2, ep: nil, vue: false)])
    }

    /// Redemarrage : les cles et la liste chargees s'appliquent ; une MAC connue garde
    /// son numero et ses drapeaux (liste_fusionner).
    mutating func appliquerChargement() {
        if let c = clesChargees { empreintes = c }
        if let nouvelle = listeChargee {
            lampes = nouvelle.map { n in
                guard let a = lampes.first(where: { $0.mac == n.mac }) else { return n }
                var x = n
                x.endpoint = a.endpoint
                x.vue = a.vue
                x.masquee = a.masquee
                return x
            }
        }
        clesChargees = nil
        listeChargee = nil
        brouillon = [:]
        attendues = 0
    }
}

/// Valeur JSON ordonnee, en UTF-8 (2.2) : comme l'ecrivain du firmware.
indirect enum J: Sendable {
    case i(Int)
    case b(Bool)
    case s(String?)
    case a([J])
    case o([(String, J)])

    var texte: String {
        switch self {
        case .i(let v): String(v)
        case .b(let v): v ? "true" : "false"
        case .s(let v): v.map(Self.chaine) ?? "null"
        case .a(let v): "[" + v.map(\.texte).joined(separator: ",") + "]"
        case .o(let v): "{" + v.map { Self.chaine($0.0) + ":" + $0.1.texte }.joined(separator: ",") + "}"
        }
    }

    static func chaine(_ s: String) -> String {
        var r = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            default: r += u.value < 0x20 || u.value == 0x7F ? "?" : String(u)
            }
        }
        return r + "\""
    }
}

actor SimulateurDemo {
    private struct LampeSim {
        var entendue: Bool
        var marche: Bool
        var intensite: Int
        var reponseMs: UInt32?
        var repondues = 0
        var consigne: (marche: Bool?, intensite: Int?)?
        var ids: [Int] = []
    }

    private let sortie: AsyncStream<EvenementTransport>.Continuation
    private let boot: String
    private let vitesse: Double
    private let sauver: @Sendable (MemoireDemo) -> Void
    private var memoire: MemoireDemo
    private let depart = ContinuousClock.now
    private var n: UInt32 = 0
    private var machine = false
    private var bailS = 30
    private var dernierRx: TimeInterval = 0
    private var log = false
    private var trames = false
    /// Prochaine demande d'etat au groupe des lampes (trames `json trames 1`), en secondes simulees.
    private var prochaineDemande = 0.0
    private var periodes = (etat: 1000, lampes: 10000, compteurs: 1000, reseau: 5000)
    private var prochains = (etat: 0.0, lampes: 0.0, compteurs: 0.0, reseau: 0.0, regard: 0.0)
    private var lampes: [LampeSim]
    private var montrees: [String] = []
    private var tampon: [UInt8] = []
    private var ordres = (total: 0, confirmes: 0, abandons: 0, tenus: 0, delai: 0)
    private var ferme = false

    init(sortie: AsyncStream<EvenementTransport>.Continuation, boot: String, vitesse: Double, memoire: MemoireDemo,
         sauver: @escaping @Sendable (MemoireDemo) -> Void) {
        self.sortie = sortie
        self.boot = boot
        self.vitesse = vitesse
        self.memoire = memoire
        self.sauver = sauver
        lampes = memoire.lampes.enumerated().map { i, l in
            LampeSim(entendue: l.vue, marche: i == 0, intensite: i == 0 ? 500 : 600)
        }
    }

    /// Secondes simulees depuis le demarrage du pont simule.
    private var t: TimeInterval { reel * vitesse }
    /// Secondes reelles : le bail se compte en temps reel, comme le ping de l'app.
    private var reel: TimeInterval { (ContinuousClock.now - depart) / .seconds(1) }
    /// Horloge du pont : il a demarre 21 s avant l'ouverture du port.
    private var ms: UInt32 { UInt32(21_000 + t * 1000) }

    func executer(entrees: AsyncStream<Data>) async {
        texte("Console du pont amaran : 'help' pour les commandes.")
        brut("amaran> ")
        await withTaskGroup(of: Void.self) { g in
            g.addTask { [weak self] in
                for await d in entrees { await self?.recevoir(d) }
            }
            g.addTask { [weak self] in
                while !Task.isCancelled {
                    guard let self, await self.tic() else { return }
                    try? await Task.sleep(for: .milliseconds(Int(50 / self.vitesse)))
                }
            }
            await g.next()
            g.cancelAll()
        }
    }

    // MARK: - Sorties

    private func brut(_ s: String) {
        guard !ferme else { return }
        sortie.yield(.donnees(Data(s.utf8)))
    }

    private func texte(_ s: String) { brut(s + "\r\n") }

    private func ligne(_ type: String, bloc: String? = nil, _ champs: [(String, J)]) {
        var tete: [(String, J)] = [("v", .i(1)), ("t", .s(type)), ("n", .i(Int(n))), ("ms", .i(Int(ms)))]
        if let bloc { tete.append(("bloc", .s(bloc))) }
        n &+= 1
        brut("\u{1E}" + J.o(tete + champs).texte + "\n")
    }

    private func reponse(_ id: Int?, _ cmd: String, debut: Bool = false, ok: Bool = true, code: String = "ok",
                         msg: String? = nil, extra: [(String, J)] = []) {
        guard let id else { return }
        // Comme le pont : `cmd` ne cite jamais une cle (mesh cles) ni l'alea (json cle nouvelle).
        let m = LigneCommande.mots(cmd)
        let vue = m.starts(with: ["json", "cle", "nouvelle"]) ? "json cle nouvelle"
            : PolitiqueCommandes.masquerCle(cmd) == cmd ? String(cmd.prefix(40)) : "mesh cles"
        var c: [(String, J)] = [("id", .i(id)), ("etape", .s(debut ? "debut" : "fin")),
                                ("cmd", .s(vue)),
                                ("ok", .b(ok)), ("code", .s(debut ? "en_cours" : code))]
        if let msg { c.append(("msg", .s(msg))) }
        if !debut { c.append(("duree_ms", .i(1))) }
        ligne("reponse", c + extra)
    }

    // MARK: - Instantanes (5)

    private func hello() {
        ligne("hello", bloc: "base", [
            ("rev", .i(1)), ("fw", .s("0.1.0-demo")), ("date", .s("Oct  5 2026")), ("heure", .s("14:02:11")),
            ("idf", .s("v5.5.4")), ("puce", .s("esp32c6")), ("boot", .s(boot)), ("reset", .s("logiciel")),
            ("reset_n", .i(3)), ("up_s", .i(Int(ms / 1000))),
            ("session", .o([("transport", .s("usb")), ("periode_ms", .i(periodes.etat)), ("lampes_ms", .i(periodes.lampes)),
                            ("compteurs_ms", .i(periodes.compteurs)), ("reseau_ms", .i(periodes.reseau)),
                            ("bail_s", .i(bailS)), ("log", .b(log)), ("trames", .b(trames))])),
            ("limites", .o([("ligne_max", .i(1024)), ("cmd_max", .i(127))])),
        ])
        ligne("hello", bloc: "identite", [
            ("boot", .s(boot)), ("mac", .s("02000000DE00")),
            ("id", .o([("fabricant", .s("TEST_VENDOR")), ("produit", .s("TEST_PRODUCT")),
                       ("serie", .s("AMARAN-02000000DE00")), ("nom", .s("Pont amaran"))])),
            ("caps", .a((["matter", "thread", "mesh", "catalogue", "ordres", "led", "log", "trames", "udp", "cle", "texte"]
                + (memoire.annonceLogiciel ? ["logiciel"] : [])).map { .s($0) })),
        ])
        ligne("config", bloc: "catalogue", [
            ("modeles", .a([.o([("code", .i(40065)), ("nom", .s("amaran COB 60d")), ("capacites", .a([.s("intensite")])),
                                ("type", .s("variable")), ("cct_k", .s(nil))])])),
            ("repli", .o([("nom", .s("modele non catalogue")), ("capacites", .a([.s("intensite")])),
                          ("type", .s("variable")), ("cct_k", .s(nil))])),
        ])
        configMesh()
        for i in memoire.lampes.indices { configLampe(i) }
    }

    private func configMesh() {
        let e = memoire.empreintes
        ligne("config", bloc: "mesh", [
            ("cles", .b(e != nil)),
            ("empreintes", e.map { .o([("reseau", .s($0.reseau)), ("application", .s($0.application))]) } ?? .s(nil)),
            ("adresse", .s("7F38")), ("iv_nvs", .i(0)),
            ("balayage", .o([("fenetre_ms", .i(20)), ("intervalle_ms", .i(40))])),
            ("lampes", .i(memoire.lampes.count)), ("capacite", .i(16)), ("releve_ms", .i(memoire.releveMs)),
            ("groupe", .s("C000")),
        ])
    }

    private func configLampe(_ i: Int) {
        let l = memoire.lampes[i]
        ligne("config", bloc: "lampe", [
            ("lampe", .i(i + 1)), ("adresse", .s(String(format: "%04X", l.adresse))),
            ("mac", .s(l.mac.replacingOccurrences(of: ":", with: ""))), ("nom", .s(l.nom)), ("code", .i(Int(l.code))),
            ("modele", .s(l.code == 40065 ? "amaran COB 60d" : "modele non catalogue")), ("catalogue", .b(l.code == 40065)),
            ("capacites", .a([.s("intensite")])), ("type", .s("variable")),
        ] + (memoire.annonceLogiciel ? [("logiciel", .s(l.logiciel)), ("ble", .s(l.ble))] : []))
    }

    private func etatPont() {
        ligne("etat", bloc: "pont", [
            ("boot", .s(boot)), ("up_s", .i(Int(ms / 1000))),
            ("mesh", .o([("pret", .b(memoire.empreintes != nil)), ("diag", .s(memoire.empreintes == nil ? "cles_absentes" : "ok"))])),
            ("ordres", .o([("total", .i(ordres.total)), ("confirmes", .i(ordres.confirmes)), ("abandons", .i(ordres.abandons)),
                           ("tenus", .i(ordres.tenus)), ("delai_total_ms", .i(ordres.delai)), ("delai_max_ms", .i(ordres.confirmes > 0 ? 430 : 0)),
                           ("lents", .i(0))])),
            ("releves", .i(Int(t / Double(memoire.releveMs) * 1000))), ("trames", .i(lampes.map(\.repondues).reduce(0, +))),
        ])
    }

    private func resume(_ i: Int) -> String {
        let l = lampes[i], m = memoire.lampes[i]
        return "\(l.entendue) \(l.marche) \(l.intensite) \(String(describing: l.consigne)) \(String(describing: m.endpoint)) \(m.vue) \(m.masquee)"
    }

    private func etatLampe(_ i: Int) {
        let l = lampes[i], m = memoire.lampes[i]
        let ep = m.masquee || !m.vue ? nil : m.endpoint
        var consigne: J = .s(nil)
        if let c = l.consigne {
            consigne = .o([("marche", c.marche.map(J.b) ?? .s(nil)), ("intensite", c.intensite.map(J.i) ?? .s(nil)),
                           ("phase", .s("attente")), ("essai", .i(1))])
        }
        ligne("etat", bloc: "lampe", [
            ("lampe", .i(i + 1)), ("maison", .o([("endpoint", ep.map(J.i) ?? .s(nil)), ("vue", .b(m.vue)), ("masquee", .b(m.masquee))])),
            ("entendue", .b(l.entendue)),
            ("lue", l.entendue ? .o([("marche", .b(l.marche)), ("intensite", .i(l.intensite))]) : .s(nil)),
            ("joignable", .b(l.entendue)), ("reponse_ms", l.reponseMs.map { .i(Int($0)) } ?? .s(nil)),
            ("consigne", consigne), ("repondues", .i(l.repondues)), ("part_10min", l.entendue ? .i(100) : .s(nil)),
            ("alerte", .b(false)),
        ])
        if i < montrees.count { montrees[i] = resume(i) }
    }

    private func sante() {
        ligne("etat", bloc: "sante", [
            ("boot", .s(boot)), ("up_s", .i(Int(ms / 1000))), ("commande", .s(nil)),
            ("led", .o([("motif", .s("operationnel")), ("test", .b(false)), ("depuis_ms", .i(Int(ms) % 10_000))])),
            ("matter", .o([("en_service", .b(true)), ("thread", .b(true)), ("identifie", .b(false)), ("ble", .b(false))])),
            ("sys", .o([("heap", .i(112_640)), ("heap_min", .i(103_424)), ("heap_bloc", .i(45_056)),
                        ("piles", .o([("lampes", .i(2104)), ("json", .i(1460)), ("console", .i(2876))])),
                        ("json_perdus", .i(0)), ("json_trop_longs", .i(0)), ("rejets", .i(0))])),
        ])
    }

    private func compteurs() {
        let k = Int(t * 40)
        ligne("compteurs", bloc: "mesh", [
            ("annonces", .i(k * 3)), ("nid_reconnu", .i(k)), ("nid_inconnu", .i(k * 2)), ("netmic_faux", .i(0)),
            ("acces_dechiffres", .i(k)), ("etats_lampes", .i(lampes.map(\.repondues).reduce(0, +))), ("doublons", .i(k / 2)),
            ("balises", .o([("notres", .i(Int(t / 5))), ("autres", .i(0)), ("fausses", .i(0)), ("derniere", .s(nil))])),
            ("emis", .i(Int(t))), ("echecs_emission", .i(0)), ("file_pleine", .i(0)), ("iv", .i(0)), ("seq", .i(1000 + Int(t))),
            ("plancher", .i(1024)),
        ])
    }

    private func reseau() {
        ligne("reseau", bloc: "matter", [
            ("demarre", .b(true)), ("fabriques", .i(1)), ("ble", .b(false)), ("identifie", .b(false)),
            ("abonnements", .o([("demandes", .i(2)), ("plafonnes", .i(2)), ("etablis", .i(2)), ("termines", .i(1)), ("plafond_s", .i(20))])),
            ("code_manuel", .s("34970112332")), ("qr", .s("MT:Y.K9042C00KA0648G00")),
        ])
        ligne("reseau", bloc: "thread", [("role", .s("child")), ("attache", .b(true))])
        let e = memoire.empreinteUdp
        ligne("reseau", bloc: "ip", [
            ("srp", .s(Self.srpDemo)),
            ("adresses", .a([.o([("type", .s("omr")), ("adresse", .s("fd12:34:5678:0:aaaa:bbbb:ccc:dddd"))]),
                             .o([("type", .s("ml_eid")), ("adresse", .s("fd12:34:5678:1:1111:2222:3333:4444"))])])),
            ("udp", .o([("port", .i(5480)), ("cle", .b(e != nil)), ("empreinte", .s(e)), ("ouvert", .b(e != nil)),
                        ("sessions", .i(0)), ("recus", .i(0)), ("emis", .i(0)), ("rejets", .i(0)), ("perdus", .i(0))])),
        ])
    }

    /// Nom SRP du pont simule : jamais 16 hexa, pour ne jamais se confondre avec un vrai
    /// pont (le trousseau de la demo est isole, mais un nom distinct le dit aussi).
    static let srpDemo = "DEMO-AMARAN"

    // MARK: - Trames (7.6)

    /// Une ligne `trame`, seulement avec `json trames 1` (le pont simule suit l'USB : pas de
    /// coupure a 60 s). `lampe` nil : le groupe des lampes.
    private func trame(_ sens: String, _ quoi: String, lampe: Int?, marche: Bool? = nil, intensite: Int? = nil,
                       essai: Int? = nil) {
        guard machine, trames, !ferme else { return }
        var c: [(String, J)] = [("sens", .s(sens)), ("quoi", .s(quoi)), ("lampe", lampe.map(J.i) ?? .s(nil)),
                                ("marche", marche.map(J.b) ?? .s(nil)), ("intensite", intensite.map(J.i) ?? .s(nil))]
        if let essai { c.append(("essai", .i(essai))) }
        c.append(("sautes", .i(0)))
        ligne("trame", c)
    }

    /// Demande d'etat au groupe, puis l'etat que chaque lampe entendue renvoie (`seulement`
    /// : une seule lampe, pour `lampe <n> releve`).
    private func demandeEtDonnees(seulement k: Int? = nil) {
        trame("tx", "demande", lampe: nil)
        for i in lampes.indices where lampes[i].entendue && (k == nil || k == i + 1) {
            trame("rx", "etat", lampe: i + 1, marche: lampes[i].marche, intensite: lampes[i].intensite)
        }
    }

    /// Reemission d'un ordre (essais 2 et 3) tant que la lampe ne repond pas.
    private func renvoyerOrdre(_ k: Int, marche: Bool?, intensite: Int?, essai: Int) {
        guard lampes[k - 1].consigne != nil else { return }
        trame("tx", "ordre", lampe: k, marche: marche, intensite: intensite, essai: essai)
    }


    private func instantane() {
        etatPont()
        for i in lampes.indices { etatLampe(i) }
        sante()
        compteurs()
        reseau()
    }

    // MARK: - Temps

    /// Faux : le pont simule redemarre (le flux se ferme).
    private func tic() -> Bool {
        guard !ferme else { return false }
        let now = t
        // La lampe jamais vue repond pour la premiere fois au bout de 15 s.
        if now > 15, let i = memoire.lampes.indices.last, !lampes[i].entendue {
            lampes[i].entendue = true
            lampes[i].reponseMs = ms
            if !memoire.lampes[i].vue && !memoire.lampes[i].masquee {
                memoire.lampes[i].vue = true
                memoire.lampes[i].endpoint = memoire.prochainEndpoint
                memoire.prochainEndpoint += 1
                sauver(memoire)
                if machine {
                    ligne("lampe", [("lampe", .i(i + 1)), ("quoi", .s("entree")), ("endpoint", .i(memoire.lampes[i].endpoint ?? 0))])
                }
            }
        }
        for i in lampes.indices where lampes[i].entendue && Int(now * 1000) % memoire.releveMs < 60 {
            lampes[i].reponseMs = ms
            lampes[i].repondues += 1
        }
        guard machine else { return true }
        if bailS > 0, reel - dernierRx > Double(bailS) {
            ligne("fin", [("cause", .s("bail"))])
            texte("json : mode machine coupe (hote muet depuis \(bailS) s)")
            brut("amaran> ")
            machine = false
            return true
        }
        if periodes.etat > 0, now >= prochains.etat {
            etatPont()
            sante()
            prochains.etat = now + Double(periodes.etat) / 1000
        }
        if periodes.lampes > 0, now >= prochains.lampes {
            for i in lampes.indices { etatLampe(i) }
            prochains.lampes = now + Double(periodes.lampes) / 1000
        }
        if now >= prochains.regard {
            for i in lampes.indices where montrees.count > i && montrees[i] != resume(i) { etatLampe(i) }
            prochains.regard = now + 0.1
        }
        if trames, now >= prochaineDemande {
            demandeEtDonnees()
            prochaineDemande = now + Double(memoire.releveMs) / 1000
        }
        if periodes.compteurs > 0, now >= prochains.compteurs {
            compteurs()
            prochains.compteurs = now + Double(periodes.compteurs) / 1000
        }
        if periodes.reseau > 0, now >= prochains.reseau {
            reseau()
            prochains.reseau = now + Double(periodes.reseau) / 1000
        }
        return true
    }

    // MARK: - Commandes (6)

    private func recevoir(_ d: Data) {
        dernierRx = reel
        for o in d {
            if o == 0x0A {
                let l = String(decoding: tampon, as: UTF8.self)
                tampon.removeAll()
                executer(l)
            } else if o == 0x15 {
                tampon.removeAll()
            } else if o >= 0x20 || o == 0x09 {
                tampon.append(o)
            }
        }
    }

    private func executer(_ brute: String) {
        var l = brute.trimmingCharacters(in: .whitespaces)
        var id: Int?
        if l.hasPrefix("id="), let e = l.firstIndex(of: " ") {
            id = Int(l[l.index(l.startIndex, offsetBy: 3)..<e])
            l = String(l[e...]).trimmingCharacters(in: .whitespaces)
        }
        guard !l.isEmpty else { return }
        if !machine { texte(PolitiqueCommandes.masquerCle(l)) }
        let m = l.split(separator: " ").map(String.init)
        switch (m.first, m.count) {
        case ("json", _):
            commandeJson(id, l, m)
        case ("lampe", 3), ("lampe", 4):
            commandeLampe(id, l, m)
        case ("mesh", _):
            commandeMesh(id, l, m)
        case ("redemarre", 1):
            reponse(id, l, debut: true)
            texte("redemarrage")
            memoire.appliquerChargement()
            sauver(memoire)
            ferme = true
            sortie.yield(.ferme(raison: tr("le pont simulé redémarre")))
            sortie.finish()
        case ("led", 2):
            reponse(id, l, debut: true)
            texte(m[1] == "test" ? "Test de la LED, 6 s ('led stop' pour l'arreter) :" : "Test de la LED arrete.")
            reponse(id, l)
        default:
            reponse(id, l, debut: true)
            texte("Commande inconnue : \"\(m.first ?? "")\" (help)")
            reponse(id, l, ok: false, code: "inconnue")
        }
        if !machine { brut("amaran> ") }
    }

    private func commandeJson(_ id: Int?, _ l: String, _ m: [String]) {
        switch m.count > 1 ? m[1] : "" {
        case "1":
            machine = true
            bailS = m.count == 4 ? Int(m[3]) ?? 30 : 30
            periodes = (1000, 10000, 1000, 5000)
            log = false
            trames = false
            let now = t
            prochains = (now + 1, now + 10, now + 1, now + 5, now)
            hello()
            instantane()
            montrees = lampes.indices.map(resume)
            reponse(id, l, extra: [("bail_s", .i(bailS)), ("up_s", .i(Int(ms / 1000)))])
        case "0":
            reponse(id, l)
            if machine {
                ligne("fin", [("cause", .s("commande"))])
                texte("json : mode machine coupe")
                machine = false
            }
        case "etat":
            instantane()
            reponse(id, l)
        case "hello":
            hello()
            reponse(id, l)
        case "ping":
            reponse(id, l, extra: [("bail_s", .i(bailS)), ("up_s", .i(Int(ms / 1000)))])
        case "periode", "lampes", "compteurs", "reseau":
            if let v = m.count == 3 ? Int(m[2]) : nil {
                switch m[1] {
                case "periode": periodes.etat = v
                case "lampes": periodes.lampes = v
                case "compteurs": periodes.compteurs = v
                default: periodes.reseau = v
                }
                reponse(id, l)
            } else {
                reponse(id, l, ok: false, code: "usage", msg: "json \(m[1]) <ms>")
            }
        case "log":
            log = m.count == 3 && m[2] == "1"
            reponse(id, l)
        case "trames" where m.count == 3 && (m[2] == "0" || m[2] == "1"):
            trames = m[2] == "1"
            prochaineDemande = t + 1
            reponse(id, l)
        case "cle":
            commandeCle(id, l, m)
        default:
            reponse(id, l, ok: false, code: "usage", msg: "json [1|0|etat|hello|ping|...]")
        }
    }

    /// `json cle nouvelle <64 hexa>` et `json cle efface` (10.2), comme le firmware : la
    /// cle vaut HMAC-SHA256(alea de l'app, alea du pont), rendue une seule fois.
    private func commandeCle(_ id: Int?, _ l: String, _ m: [String]) {
        if m.count == 4, m[2] == "nouvelle", id != nil, !machine {
            // Comme le firmware (c5128fa) : avec un id, en mode machine seulement. Rien ne change.
            reponse(id, l, ok: false, code: "usage", msg: "json cle nouvelle avec id : en mode machine seulement (json 1)")
        } else if m.count == 4, m[2] == "nouvelle", let alea = H1.octets(hexa: m[3].uppercased()), alea.count == 32 {
            let cle = Data(HMAC<SHA256>.authenticationCode(for: H1.aleatoire(32), using: SymmetricKey(data: alea)))
            let empreinte = H1.kid(cle: cle)
            memoire.empreinteUdp = empreinte
            sauver(memoire)
            if id == nil { texte("ok cle UDP \(empreinte), port 5480 ouvert") }
            reponse(id, l, extra: [("cle", .s(H1.hexa(cle))), ("empreinte", .s(empreinte))])
        } else if m.count == 3, m[2] == "efface" {
            memoire.empreinteUdp = nil
            sauver(memoire)
            if id == nil { texte("ok cle UDP effacee, port 5480 ferme") }
            reponse(id, l)
        } else {
            reponse(id, l, ok: false, code: "usage", msg: "json cle nouvelle <64 hexa> | json cle efface")
        }
    }

    private func commandeLampe(_ id: Int?, _ l: String, _ m: [String]) {
        guard let k = Int(m[1]), (1...lampes.count).contains(k) else {
            return reponse(id, l, ok: false, code: "usage", msg: "lampe <1-\(lampes.count)> on|off|niveau <0-1000>")
        }
        let i = k - 1
        if m[2] == "releve" {
            reponse(id, l, debut: true)
            texte("ok demande d'etat a la lampe \(k)")
            demandeEtDonnees(seulement: k)
            return reponse(id, l)
        }
        var marche: Bool?
        var intensite: Int?
        switch m[2] {
        case "on" where m.count == 3: marche = true
        case "off" where m.count == 3: marche = false
        case "niveau" where m.count == 4: intensite = Int(m[3]).map { min(1000, max(0, $0)) / 10 * 10 }
        default: break
        }
        guard marche != nil || intensite != nil else {
            return reponse(id, l, ok: false, code: "usage", msg: "lampe <1-\(lampes.count)> on|off|niveau <0-1000>")
        }
        reponse(id, l, code: "accepte", extra: [("suite", .s("ordre")), ("lampe", .i(k))])
        ordres.total += 1
        if let id { lampes[i].ids.append(id) }
        let tenu = lampes[i].entendue && (marche.map { $0 == lampes[i].marche } ?? true)
            && (intensite.map { $0 == lampes[i].intensite } ?? true)
        if tenu {
            ordres.tenus += 1
            return finirOrdre(i, issue: "tenu", delai: 0, essai: 0)
        }
        lampes[i].consigne = (marche, intensite)
        let attente = Int((lampes[i].entendue ? 430 : 3700) / vitesse)
        trame("tx", "ordre", lampe: k, marche: marche, intensite: intensite, essai: 1)
        // Copies : les taches ci-dessous ne capturent pas les `var` de la fonction.
        let (voulueMarche, voulueIntensite) = (marche, intensite)
        if !lampes[i].entendue {
            // Sans reponse : le pont renvoie l'ordre aux essais 2 et 3 avant d'abandonner.
            Task { [weak self] in
                for essai in 2...3 {
                    try? await Task.sleep(for: .milliseconds(attente / 3))
                    await self?.renvoyerOrdre(k, marche: voulueMarche, intensite: voulueIntensite, essai: essai)
                }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(attente))
            await self?.finirConsigne(i, marche: voulueMarche, intensite: voulueIntensite)
        }
    }

    /// La lampe a obei (relue egale a la consigne), ou ne repond pas : abandon.
    private func finirConsigne(_ i: Int, marche: Bool?, intensite: Int?) {
        guard !ferme else { return }
        if lampes[i].entendue {
            if let marche { lampes[i].marche = marche }
            if let intensite { lampes[i].intensite = intensite }
            lampes[i].consigne = nil
            trame("tx", "demande", lampe: nil)
            trame("rx", "etat", lampe: i + 1, marche: lampes[i].marche, intensite: lampes[i].intensite)
            ordres.confirmes += 1
            ordres.delai += 430
            finirOrdre(i, issue: "confirme", delai: 430, essai: 1)
            if machine { ligne("led", [("motif", .s("livree")), ("avant", .s("operationnel")), ("test", .b(false)), ("depuis_ms", .i(0))]) }
        } else {
            lampes[i].consigne = nil
            ordres.abandons += 1
            finirOrdre(i, issue: "abandon", delai: 3700, essai: 3)
            if machine { ligne("led", [("motif", .s("injoignable")), ("avant", .s("operationnel")), ("test", .b(false)), ("depuis_ms", .i(0))]) }
        }
    }

    private func finirOrdre(_ i: Int, issue: String, delai: Int, essai: Int) {
        let ids = lampes[i].ids
        lampes[i].ids = []
        guard machine else { return }
        ligne("ordre", [("lampe", .i(i + 1)), ("issue", .s(issue)), ("delai_ms", .i(delai)), ("essai", .i(essai)),
                        ("ids", .a(ids.map(J.i))), ("ids_perdus", .i(0))])
    }

    private func commandeMesh(_ id: Int?, _ l: String, _ m: [String]) {
        reponse(id, l, debut: true)
        var ok = true
        switch (m.count > 1 ? m[1] : "", m.count) {
        case ("", 1):
            texte("mesh pret : \(memoire.empreintes == nil ? "non" : "oui")")
            if let e = memoire.empreintes { texte("cles : reseau \(e.reseau), application \(e.application)") }
        case ("releve", 3):
            if let s = Int(m[2]), (1...60).contains(s) {
                memoire.releveMs = s * 1000
                sauver(memoire)
                texte("ok relecture toutes les \(s) s")
                if machine { configMesh() }
            } else {
                texte("erreur : mesh releve <1-60 s>")
                ok = false
            }
        case ("lampe", 4) where m[3] == "masquer" || m[3] == "afficher":
            if let k = Int(m[2]), (1...memoire.lampes.count).contains(k) {
                let i = k - 1
                let afficher = m[3] == "afficher"
                memoire.lampes[i].masquee = !afficher
                if afficher {
                    memoire.lampes[i].vue = true
                    if memoire.lampes[i].endpoint == nil {
                        memoire.lampes[i].endpoint = memoire.prochainEndpoint
                        memoire.prochainEndpoint += 1
                    }
                }
                sauver(memoire)
                let ep = memoire.lampes[i].endpoint ?? 0
                texte(afficher ? "ok lampe \(k) dans Maison (EP\(ep))"
                               : "ok lampe \(k) retiree de Maison (mesh lampe \(k) afficher pour la remettre)")
                if machine {
                    ligne("lampe", [("lampe", .i(k)), ("quoi", .s(afficher ? "remise" : "masquee")),
                                    ("endpoint", afficher ? .i(ep) : .s(nil))])
                }
            } else {
                texte("erreur : mesh lampe <1-\(memoire.lampes.count)> masquer|afficher")
                ok = false
            }
        case ("cles", 4):
            let r = Data(hex: m[2]), a = Data(hex: m[3])
            if let r, let a, r.count == 16, a.count == 16 {
                let e = (Empreinte.de(r), Empreinte.de(a))
                memoire.clesChargees = e
                texte("ok cles \(e.0) \(e.1) (redemarrer pour les appliquer)")
            } else {
                texte("erreur : mesh cles <reseau 32 hexa> <application 32 hexa>")
                ok = false
            }
        case ("lampes", 3):
            memoire.attendues = Int(m[2]) ?? 0
            memoire.brouillon = [:]
            texte("ok liste de \(memoire.attendues) lampe(s) : envoyer mesh lampe 1 a \(memoire.attendues)"
                  + (memoire.annonceLogiciel ? " [v<x.y>[/<x.y>]]" : ""))
        case ("lampe", let c) where c >= 7:
            ok = chargerLampe(l)
        default:
            texte("erreur : sous-commande inconnue (help)")
            ok = false
        }
        reponse(id, l, ok: ok, code: ok ? "ok" : "erreur")
    }

    /// `mesh lampe <n> <adresse> <mac> <code> [v<x.y>[/<x.y>]] <nom>`, decoupee comme la console du
    /// pont (`LigneCommande.argv`). Le mot `argv[6]` est un jeton de version seulement si le pont prend
    /// les versions, s'il reste au moins un mot apres lui, et s'il a exactement la forme
    /// `v<x.y>[/<x.y>]` (donc sans espace : un nom entre guillemets reste un nom) ; sinon tout a partir
    /// de `argv[6]` est le nom, sans erreur. Sans la capacite `logiciel`, aucun jeton n'est reconnu.
    private func chargerLampe(_ l: String) -> Bool {
        let a = LigneCommande.argv(l, maxArguments: 32)
        let jeton = "[v<x.y>[/<x.y>]] "
        guard memoire.attendues > 0, a.count >= 7, let k = Int(a[2]), (1...memoire.attendues).contains(k),
              let adresse = UInt16(a[3].replacingOccurrences(of: "0x", with: ""), radix: 16), let code = UInt32(a[5])
        else {
            texte("erreur : mesh lampe <1-\(memoire.attendues)> <adresse> <mac> <code> "
                  + (memoire.annonceLogiciel ? jeton : "") + "<nom>")
            return false
        }
        var logiciel: String?, ble: String?
        var premier = 6
        if memoire.annonceLogiciel, a.count >= 8,
           let v = a[6].wholeMatch(of: /v([0-9]{1,3}\.[0-9]{1,3})(?:\/([0-9]{1,3}\.[0-9]{1,3}))?/) {
            logiciel = String(v.output.1)
            ble = v.output.2.map(String.init)
            premier = 7
        }
        let nom = a[premier...].joined(separator: " ")
        memoire.brouillon[k] = MemoireDemo.Lampe(adresse: adresse, mac: a[4], nom: nom, code: code, endpoint: nil, vue: false,
                                                   logiciel: logiciel, ble: ble)
        var fin = ""
        if memoire.brouillon.count == memoire.attendues {
            memoire.listeChargee = (1...memoire.attendues).compactMap { memoire.brouillon[$0] }
            fin = " ; liste de \(memoire.attendues) lampe(s) enregistree (redemarrer pour l'appliquer)"
        }
        // Un pont d'avant (sans la capacite `logiciel`) ne parle pas des versions.
        let versions = memoire.annonceLogiciel
            ? "logiciel \(ReseauMesh.versionsTexte(logiciel: logiciel, ble: ble) ?? "inconnu") " : ""
        texte("ok lampe \(k) 0x\(String(format: "%04x", adresse)) modele \(code) amaran COB 60d [intensite] "
              + "\(versions): \(nom)\(fin)")
        return true
    }
}
