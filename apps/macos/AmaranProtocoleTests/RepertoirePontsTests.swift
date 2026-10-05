// Repris de Halo Compagnon (HaloProtocoleTests/RepertoirePontsTests.swift) : numero de
// serie AMARAN-<MAC> ; MAC et noms SRP inventes.
import Foundation
import Testing
@testable import AmaranProtocole

@Suite("Repertoire des ponts (noms du menu Source)")
struct RepertoirePontsTests {
    static let mac = "F0F5BD0A0B0C"
    static let autre = "020000AABBCC"
    static let srp = "1A2B3C4D5E6F7081"

    @Test func mac() {
        #expect(RepertoirePonts.mac("F0:F5:BD:0A:0B:0C") == Self.mac, "numero de serie USB")
        #expect(RepertoirePonts.mac("f0f5bd0a0b0c") == Self.mac, "hello identite")
        #expect(RepertoirePonts.mac("F0-F5-BD-0A-0B-0C") == Self.mac)
        #expect(RepertoirePonts.mac("F0:F5:BD:0A:0B") == nil)
        #expect(RepertoirePonts.mac("ABCDEFGHIJKL") == nil, "pas de l'hexa")
        #expect(RepertoirePonts.mac(nil) == nil)
        #expect(RepertoirePonts.macLisible(Self.mac) == "F0:F5:BD:0A:0B:0C")
    }

    @Test func modele() {
        #expect(RepertoirePonts.modele(serie: "AMARAN-F0F5BD0A0B0C", mac: Self.mac) == "AMARAN")
        #expect(RepertoirePonts.modele(serie: "AMARAN-2-F0F5BD0A0B0C", mac: Self.mac) == "AMARAN-2")
        #expect(RepertoirePonts.modele(serie: "AMARAN-020000AABBCC", mac: Self.mac) == nil, "autre MAC")
        #expect(RepertoirePonts.modele(serie: "-F0F5BD0A0B0C", mac: Self.mac) == nil)
        #expect(RepertoirePonts.modele(serie: "AMARAN", mac: Self.mac) == nil)
        #expect(RepertoirePonts.modele(serie: nil, mac: Self.mac) == nil)
    }

    @Test func noterEtNommer() {
        var r = RepertoirePonts()
        #expect(r.titre(mac: Self.mac) == "ESP32 · F0:F5:BD:0A:0B:0C", "jamais connecte")
        let change1 = r.noter(mac: Self.mac, serie: "AMARAN-F0F5BD0A0B0C", srp: nil)
        #expect(change1)
        #expect(r.titre(mac: Self.mac) == "AMARAN · F0:F5:BD:0A:0B:0C")
        let change2 = r.noter(mac: Self.mac, serie: "AMARAN-F0F5BD0A0B0C", srp: Self.srp)
        #expect(change2)
        let change3 = r.noter(mac: Self.mac, serie: "AMARAN-F0F5BD0A0B0C", srp: Self.srp)
        #expect(!change3, "rien de neuf")
        #expect(r.mac(pourSrp: Self.srp) == Self.mac)
        #expect(r.pontsReseau.map(\.srp) == [Self.srp])
        let change4 = r.noter(mac: nil, serie: "AMARAN-F0F5BD0A0B0C", srp: "X")
        #expect(!change4, "sans MAC : rien")
        let change5 = r.noter(mac: Self.mac, serie: nil, srp: nil)
        #expect(!change5, "le modele appris reste")
        #expect(r.titre(mac: Self.mac) == "AMARAN · F0:F5:BD:0A:0B:0C")
        r.oublier(mac: "F0:F5:BD:0A:0B:0C")
        #expect(r.parMac.isEmpty)
    }

    /// Un nom SRP n'appartient qu'a un pont : le pont qui le reprend l'emporte.
    @Test func nomSrpRepris() {
        var r = RepertoirePonts()
        r.noter(mac: Self.mac, serie: "AMARAN-F0F5BD0A0B0C", srp: Self.srp)
        let change = r.noter(mac: Self.autre, serie: "AMARAN-020000AABBCC", srp: Self.srp)
        #expect(change)
        #expect(r.mac(pourSrp: Self.srp) == Self.autre)
        #expect(r.parMac[Self.mac]?.srp == nil && r.parMac[Self.mac]?.modele == "AMARAN")
    }

    /// Ce que dit l'etat du pont : `hello` `identite` et bloc `ip` des exemples.
    @Test func depuisLEtatDuPont() throws {
        var e = EtatPont()
        for l in try ExemplesSpec.decoder() { e.appliquer(l, recueA: Date()) }
        #expect(e.srp == Self.srp)
        #expect(e.ip?.valeur.udp?.cle == false, "le dernier bloc ip des exemples : sans cle")
        #expect(e.transport == .udp, "le dernier hello des exemples : session distante")
        var r = RepertoirePonts()
        let change = r.noter(e)
        #expect(change)
        #expect(r.parMac[Self.mac] == RepertoirePonts.Entree(modele: "AMARAN", srp: Self.srp))
    }

    @Test func codablePourLesReglages() throws {
        var r = RepertoirePonts()
        r.noter(mac: Self.mac, serie: "AMARAN-F0F5BD0A0B0C", srp: Self.srp)
        let relu = try JSONDecoder().decode(RepertoirePonts.self, from: try JSONEncoder().encode(r))
        #expect(relu == r)
        let d = try #require(r.donnees)
        #expect(RepertoirePonts(donnees: d) == r)
        #expect(RepertoirePonts(donnees: Data("pas du json".utf8)) == nil)
        #expect(RepertoirePonts.cleReglages == "repertoirePonts")
    }
}
