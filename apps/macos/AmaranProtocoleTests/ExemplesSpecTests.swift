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

@Suite("Exemples de la specification (section 9)")
struct ExemplesSpecTests {
    @Test func toutesLesLignesSontLues() throws {
        #expect(try ExemplesSpec.lignes().count == 47)
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
        #expect(h.session?.lampesMs == 10000)
        #expect(h.session?.bailS == 30)
        #expect(h.limites?.cmdMax == 127)

        guard case .helloIdentite(let i) = l[1].message else { Issue.record("identite"); return }
        #expect(i.id?.serie == "AMARAN-F0F5BD0A0B0C")
        #expect(i.caps?.contains("ordres") == true)

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
}
