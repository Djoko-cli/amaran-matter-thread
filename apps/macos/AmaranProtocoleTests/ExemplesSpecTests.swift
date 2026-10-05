// Repris de Halo Compagnon (commit e114cd5) : les exemples sont ceux de
// docs/PROTOCOLE-JSON.md du pont amaran, que tests/hote/test_json.cpp forme tels quels.
import Foundation
import Testing
@testable import AmaranProtocole

/// Les lignes `<RS>{...}` de docs/PROTOCOLE-JSON.md, lues dans le document lui-meme :
/// le protocole du firmware, sa specification et l'app ne divergent pas.
enum ExemplesSpec {
    static let chemin = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AmaranProtocoleTests
        .deletingLastPathComponent()  // macos
        .deletingLastPathComponent()  // apps
        .deletingLastPathComponent()  // racine du depot
        .appendingPathComponent("docs/PROTOCOLE-JSON.md")

    static func lignes() throws -> [String] {
        let texte = try String(contentsOf: chemin, encoding: .utf8)
        return texte.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.hasPrefix("<RS>") }
            .map { String($0.dropFirst(4)) }
    }

    /// Decode toutes les lignes dans un meme recepteur, comme sur le fil.
    static func decoder() throws -> [LigneMachine] {
        var r = RecepteurLignes()
        var octets: [UInt8] = []
        for l in try lignes() { octets += [Octets.rs] + Array(l.utf8) + [Octets.lf] }
        return r.alimenter(octets).compactMap {
            if case .machine(let l) = $0 { return l }
            return nil
        }
    }
}

@Suite("Exemples de la specification (sections 9 et 10)")
struct ExemplesSpecTests {
    @Test func toutesLesLignesSontLues() throws {
        #expect(try ExemplesSpec.lignes().count == 60)
    }

    @Test(arguments: (try? ExemplesSpec.lignes()) ?? [])
    func chaqueLigneSeDecode(_ json: String) throws {
        var r = RecepteurLignes()
        let e = r.alimenter([Octets.rs] + Array(json.utf8) + [Octets.lf])
        try #require(e.count == 1, "un element attendu : \(e)")
        guard case .machine(let l) = e[0] else {
            Issue.record("ligne rejetee : \(e[0])")
            return
        }
        #expect(l.message != .inconnu, "type non gere : \(l.enveloppe.t) \(l.enveloppe.bloc ?? "")")
        #expect(l.enveloppe.v == 1)
        #expect(json.utf8.count + 2 <= 896, "au-dela du budget de 896 octets")
        #expect(r.compteurs.lignesAbimees == 0)
    }

    @Test func connexion() throws {
        let l = try ExemplesSpec.decoder()
        guard case .helloBase(let h) = l[0].message else { Issue.record("hello base"); return }
        #expect(h.fw == "0.1.0-d569f01")
        #expect(h.boot == "3FA2C901")
        #expect(h.reset == "logiciel")
        #expect(h.rev == 1)
        #expect(h.session?.transport == .usb)
        #expect(h.session?.lampesMs == 10000)
        #expect(h.session?.bailS == 30)
        #expect(h.session?.trames == false)
        #expect(h.limites?.cmdMax == 127)

        guard case .helloIdentite(let i) = l[1].message else { Issue.record("identite"); return }
        #expect(i.id?.serie == "AMARAN-F0F5BD0A0B0C")
        #expect(i.caps?.contains("ordres") == true)
        var e = EtatPont()
        e.appliquer(l[1], recueA: Date())
        #expect(CapPont.allCases.allSatisfy { e.a($0) }, "rev 1 : trames, udp, cle, texte en plus")

        guard case .configCatalogue(let c) = l[2].message else { Issue.record("catalogue"); return }
        #expect(c.modeles?.first?.code == 40065)
        #expect(c.modeles?.first?.capacites == [.intensite])
        #expect(c.repli?.type == .variable)

        guard case .configMesh(let m) = l[3].message else { Issue.record("mesh"); return }
        #expect(m.empreintes?.reseau == "1A2B3C4D")
        #expect(m.adresse == "7F38")
        #expect(m.lampes == 2)
        #expect(m.releveMs == 2000)

        guard case .configLampe(let l2) = l[5].message else { Issue.record("config lampe 2"); return }
        #expect(l2.lampe == 2)
        #expect(l2.nom == "Lumière fenêtre")
        #expect(l2.mac == "020000000002")

        guard case .etatPont(let p) = l[6].message else { Issue.record("etat pont"); return }
        #expect(p.mesh?.diag == .ok)
        #expect(p.ordres?.delaiMoyenMs == 430)

        guard case .etatLampe(let e1) = l[7].message else { Issue.record("etat lampe 1"); return }
        #expect(e1.maison?.endpoint == 2)
        #expect(e1.lue == EtatLu(marche: true, intensite: 430))
        #expect(e1.part10Min == 97)
        #expect(e1.consigne == nil)

        guard case .etatSante(let s) = l[9].message else { Issue.record("sante"); return }
        #expect(s.commande == nil)
        #expect(s.led?.motif == .operationnel)
        #expect(s.sys?.piles?["ot_task"] == 1536)

        guard case .reseauMatter(let r) = l[11].message else { Issue.record("matter"); return }
        #expect(r.abonnements?.actifs == 1)
        #expect(r.codeManuel == "34970112332")
    }

    @Test func ordreEtEvenements() throws {
        let tout = try ExemplesSpec.decoder()
        let ordres = tout.compactMap { if case .ordre(let o) = $0.message { return o } else { return nil } }
        #expect(ordres.map(\.issue) == [.confirme, .tenu, .abandon])
        #expect(ordres.first?.ids == [2])
        let lampes = tout.compactMap { if case .lampe(let e) = $0.message { return e } else { return nil } }
        #expect(lampes.map(\.quoi) == [.masquee, .remise, .entree])
        #expect(lampes.first?.endpoint == nil)
        let alertes = tout.compactMap { if case .alerte(let a) = $0.message { return a } else { return nil } }
        #expect(alertes.map(\.quoi) == [.releves, .mesh, .mesh])
        #expect(alertes[1].diag == .clesPerimees)
        let sante = tout.compactMap { if case .etatSante(let s) = $0.message { return s } else { return nil } }
        #expect(sante.map(\.commande) == [nil, 7], "le bloc sante porte la commande en cours")
    }

    /// Un ordre refuse faute de Bluetooth Mesh (essai 0) n'accuse pas la lampe.
    @Test func abandonSansEssaiDitMeshPasPret() {
        let refuse = EvenementOrdre(lampe: 1, issue: .abandon, delaiMs: 0, essai: 0, ids: [4], idsPerdus: 0)
        #expect(Interpretation.ordre(refuse).contains("Bluetooth Mesh pas prêt"))
        #expect(!Interpretation.ordre(refuse).contains("ne répond pas"))
        let abandon = EvenementOrdre(lampe: 1, issue: .abandon, delaiMs: 3700, essai: 3, ids: [4], idsPerdus: 0)
        #expect(Interpretation.ordre(abandon) == "abandonné après 3 essai(s), 3700 ms : la lampe ne répond pas")
    }

    /// Section 10.6 : chaque champ des exemples a distance.
    @Test func aDistance() throws {
        let tout = try ExemplesSpec.decoder()
        let hellos = tout.compactMap { if case .helloBase(let h) = $0.message { return h } else { return nil } }
        let h = try #require(hellos.last)
        #expect(h.session == HelloBase.ReglagesSession(transport: .udp, periodeMs: 2000, lampesMs: 30000, compteursMs: 0,
                                                       reseauMs: 30000, bailS: 60, log: false, trames: false))
        #expect(h.upS == 900)

        let ips = tout.compactMap { if case .reseauIp(let r) = $0.message { return r } else { return nil } }
        #expect(ips.count == 2)
        let ip = ips[0]
        #expect(ip.srp == "1A2B3C4D5E6F7081")
        #expect(ip.hote == "1A2B3C4D5E6F7081.local")
        #expect(ip.adresses?.map(\.type) == [.omr, .mlEid])
        #expect(ip.adresseOmr == "fd00:aaaa:bbbb:0:1111:2222:3333:4444")
        #expect(ip.adresses?.last?.adresse == "fd00:cccc:dddd:1:5555:6666:7777:8888")
        #expect(ip.udp?.port == 5480)
        #expect(ip.udp?.cle == true)
        #expect(ip.udp?.empreinte == "CA2A4FE7")
        #expect(ip.udp?.ouvert == true)
        #expect(ip.udp?.sessions == 1)
        #expect(ip.udp?.recus == 412 && ip.udp?.emis == 980 && ip.udp?.rejets == 3 && ip.udp?.perdus == 0)
        let sans = ips[1]
        #expect(sans.adresses == [] && sans.adresseOmr == nil)
        #expect(sans.udp?.cle == false && sans.udp?.empreinte == nil && sans.udp?.ouvert == false)

        let reponses = tout.compactMap { if case .reponse(let r) = $0.message { return r } else { return nil } }
        let cle = try #require(reponses.first { $0.cle != nil })
        #expect(cle.cmd == "json cle nouvelle", "le pont ne cite jamais l'alea")
        #expect(cle.empreinte == "CA2A4FE7")
        #expect(CleReseau.verifier(cle).map(\.empreinte) == .success("CA2A4FE7"), "empreinte = SHA-256 de la cle")
        #expect(cle.sansCle.cle == nil && cle.sansCle.empreinte == "CA2A4FE7")
        let interdite = try #require(reponses.first { $0.code == .interdite })
        #expect(interdite.cmd == "redemarre" && !interdite.ok)
        #expect(interdite.msg == PolitiqueCommandes.autoriseeADistance("redemarre"), "meme raison que le miroir de l'app")
        let deja = try #require(reponses.first { $0.code == .dejaTraite })
        #expect(deja.id == 29 && deja.etape == .fin && deja.msg == "id deja traite : reponse oubliee")

        let textes = tout.compactMap { if case .texte(let t) = $0.message { return t } else { return nil } }
        #expect(textes == [TexteCommande(id: 32, txt: "lampe 1 : Lampe bureau"), TexteCommande(id: 32, txt: "  Maison    : EP2")])

        let trames = tout.compactMap { if case .trame(let t) = $0.message { return t } else { return nil } }
        #expect(trames == [
            Trame(sens: .tx, quoi: .ordre, lampe: 1, marche: true, intensite: 500, essai: 1, sautes: 0),
            Trame(sens: .tx, quoi: .demande, lampe: nil, marche: nil, intensite: nil, essai: nil, sautes: 0),
            Trame(sens: .rx, quoi: .etat, lampe: 1, marche: true, intensite: 500, essai: nil, sautes: 2),
        ])
        #expect(trames.map(Interpretation.trame) == [
            "→ lampe 1 : ordre allumée, 50 % (essai 1)",
            "→ groupe : demande d'état",
            "← lampe 1 : état allumée, 50 % — 2 trame(s) non émise(s) avant",
        ])
    }

    /// La lecture a distance (`id=32 lampe 1`) se deroule dans le correlateur comme par
    /// l'USB : `debut`, le texte rattache a la commande, puis `fin`.
    @Test func lectureADistanceCorrelee() throws {
        let tout = try ExemplesSpec.decoder()
        let premiere = try #require(tout.firstIndex {
            if case .reponse(let r) = $0.message { r.id == 32 && r.cmd == "lampe 1" } else { false }
        })
        var c = Correlateur()
        c.politique = .reseau
        // Le correlateur numerote lui-meme : amener le prochain numero a 32.
        for _ in 1..<32 { _ = c.reserverNumero() }
        let a = c.soumettre("lampe 1", origine: .console, maintenant: 0)
        let p = c.prochainEnvoi(maintenant: 0)
        #expect(p.map { texte($0.octets) } == "id=32 lampe 1\n")
        for l in tout[premiere...] {
            switch l.message {
            case .reponse(let r) where r.id == 32: _ = c.recevoir(r, maintenant: 1)
            case .texte(let t): c.texte(t.txt ?? "", id: t.id, maintenant: 1)
            default: break
            }
        }
        #expect(c.suivi(a)?.etat == .terminee)
        #expect(c.suivi(a)?.texte == ["lampe 1 : Lampe bureau", "  Maison    : EP2"])
        #expect(c.suivi(a)?.fin?.dureeMs == 6)
    }
}
