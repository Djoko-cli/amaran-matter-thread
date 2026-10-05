// Repris de Halo Compagnon (commit e114cd5) : creation et verification de la cle UDP.
import Foundation
import Testing
@testable import AmaranProtocole

@Suite("Cle du transport reseau ")
struct CleReseauTests {
    static func reponseCle(ok: Bool = true, code: CodeReponse = .ok, cle: String?, empreinte: String?) -> Reponse {
        Reponse(id: 7, etape: .fin, cmd: "json cle nouvelle", ok: ok, code: code, msg: ok ? nil : "tampon USB occupe",
                dureeMs: 1, cle: cle, empreinte: empreinte)
    }

    @Test func commande() {
        let c = CleReseau.commande(alea: Data(repeating: 0xAB, count: 32))
        #expect(c == "json cle nouvelle " + String(repeating: "AB", count: 32))
        if case .failure(let e) = LigneCommande.valider(c, id: LigneCommande.idMax) { Issue.record("\(e)") }
        #expect(CleReseau.alea().count == 32)
    }

    @Test func verifierUneBonneCle() throws {
        let r = Self.reponseCle(cle: H1.hexa(VecteursH1.psk), empreinte: "630DCD29")
        let c = try CleReseau.verifier(r).get()
        #expect(c.cle == VecteursH1.psk)
        #expect(c.empreinte == "630DCD29")
    }

    @Test func refus() {
        #expect(CleReseau.verifier(Self.reponseCle(ok: false, code: .erreur, cle: nil, empreinte: nil))
                == .failure(.refusee("tampon USB occupe")))
        #expect(CleReseau.verifier(Self.reponseCle(cle: nil, empreinte: "630DCD29")) == .failure(.cleIllisible))
        #expect(CleReseau.verifier(Self.reponseCle(cle: H1.hexa(VecteursH1.psk).lowercased(), empreinte: "630DCD29"))
                == .failure(.cleIllisible))
        #expect(CleReseau.verifier(Self.reponseCle(cle: H1.hexa(VecteursH1.psk), empreinte: "00000000"))
                == .failure(.empreinteIncoherente))
    }

    @Test func laCleNestJamaisRangeeDansLeSuivi() {
        var c = Correlateur()
        let a = c.soumettre(CleReseau.commande(alea: Data(repeating: 1, count: 32)), origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(Self.reponseCle(cle: H1.hexa(VecteursH1.psk), empreinte: "630DCD29").avecId(1), maintenant: 0.1)
        // La cle ne va que dans le trousseau : jamais dans un suivi de commande, meme un instant (5.2).
        #expect(c.suivi(a)?.fin?.cle == nil)
        #expect(c.suivi(a)?.fin?.empreinte == "630DCD29", "l'empreinte reste")
    }
}

@Suite("Etat de l'acces reseau")
struct EtatAccesReseauTests {
    static let nom = "1A2B3C4D5E6F7081"

    static func ip(srp: String? = nom, cle: Bool? = true, empreinte: String? = "CA2A4FE7", ouvert: Bool? = true,
                  sansUdp: Bool = false) -> ReseauIp {
        var u = ReseauIp.Udp()
        u.port = 5480
        u.cle = cle
        u.empreinte = empreinte
        u.ouvert = ouvert
        var r = ReseauIp()
        r.srp = srp
        r.udp = sansUdp ? nil : u
        return r
    }

    @Test func etats() {
        let connue: (String) -> String? = { $0 == Self.nom ? "CA2A4FE7" : nil }
        let autre: (String) -> String? = { _ in "11111111" }
        let aucune: (String) -> String? = { _ in nil }
        #expect(EtatAccesReseau.depuis(ip: nil, empreinteDuMac: connue) == .inconnu)
        #expect(EtatAccesReseau.depuis(ip: Self.ip(srp: nil), empreinteDuMac: connue) == .inconnu)
        #expect(EtatAccesReseau.depuis(ip: Self.ip(srp: ""), empreinteDuMac: connue) == .inconnu)
        #expect(EtatAccesReseau.depuis(ip: Self.ip(sansUdp: true), empreinteDuMac: connue) == .inconnu)
        #expect(EtatAccesReseau.depuis(ip: Self.ip(cle: false, empreinte: nil, ouvert: false), empreinteDuMac: connue)
                == .sansCle(nom: Self.nom))
        #expect(EtatAccesReseau.depuis(ip: Self.ip(), empreinteDuMac: connue) == .cleConnue(nom: Self.nom, empreinte: "CA2A4FE7"))
        #expect(EtatAccesReseau.depuis(ip: Self.ip(), empreinteDuMac: autre) == .cleInconnue(nom: Self.nom, empreinte: "CA2A4FE7"))
        #expect(EtatAccesReseau.depuis(ip: Self.ip(), empreinteDuMac: aucune) == .cleInconnue(nom: Self.nom, empreinte: "CA2A4FE7"))
        // Sans le champ `cle` (firmware plus ancien) : le port ouvert dit la cle.
        #expect(EtatAccesReseau.depuis(ip: Self.ip(cle: nil), empreinteDuMac: connue) == .cleConnue(nom: Self.nom, empreinte: "CA2A4FE7"))
        #expect(EtatAccesReseau.depuis(ip: Self.ip(cle: nil, ouvert: false), empreinteDuMac: connue) == .sansCle(nom: Self.nom))
        #expect(EtatAccesReseau.cleConnue(nom: Self.nom, empreinte: "CA2A4FE7").nom == Self.nom)
        #expect(EtatAccesReseau.inconnu.nom == nil)
    }
}

extension Reponse {
    func avecId(_ n: Int) -> Reponse {
        var r = self
        r.id = n
        return r
    }
}
