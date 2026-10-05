// Repris de Halo Compagnon (commit e114cd5, TrousseauTests.swift) : trousseau des cles
// UDP des ponts (docs/PROTOCOLE-JSON.md 10.2). Nom SRP et cle inventes.
import AmaranProtocole
import Foundation
import Testing
@testable import AmaranCompagnon

@Suite("Trousseau des ponts (cles UDP)")
struct TrousseauPontsTests {
    static let nom = "1A2B3C4D5E6F7081"
    static let cle = Data((0..<32).map { 0x40 &+ UInt8($0) })

    static func exercer(_ t: any TrousseauPonts) throws {
        try? t.oublier(nom: nom)
        #expect(t.lister().isEmpty)
        #expect(throws: ErreurTrousseauPonts.absente(nom)) { try t.lire(nom: nom) }
        try t.ranger(nom: nom, cle: cle, empreinte: H1.kid(cle: cle))
        #expect(t.lister() == [PontConnu(nom: nom, empreinte: H1.kid(cle: cle))])
        #expect(try t.lire(nom: nom) == cle)
        // Nouvelle cle pour le meme pont : remplacee, pas doublee.
        let autre = Data(repeating: 0x5A, count: 32)
        try t.ranger(nom: nom, cle: autre, empreinte: H1.kid(cle: autre))
        #expect(t.lister().count == 1)
        #expect(t.lister().first?.empreinte == H1.kid(cle: autre))
        #expect(try t.lire(nom: nom) == autre)
        try t.oublier(nom: nom)
        #expect(t.lister().isEmpty)
        try t.oublier(nom: nom)  // deja oublie : sans erreur
    }

    @Test func enMemoire() throws {
        try Self.exercer(TrousseauPontsMemoire())
    }

    /// Le trousseau des ponts et celui des cles Mesh sont deux elements distincts.
    @Test func distinctDuTrousseauMesh() {
        #expect(TrousseauPontsSysteme().service == "fr.djoko.amaran.pont")
        #expect(TrousseauSysteme().service == "fr.djoko.amaran.reseau")
    }

    /// Vrai trousseau (service de test, nettoye) : seulement sur demande,
    /// `TEST_RUNNER_AMARAN_TEST_TROUSSEAU=1 xcodebuild ... test`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AMARAN_TEST_TROUSSEAU"] == "1"))
    func trousseauDuMac() throws {
        try Self.exercer(TrousseauPontsSysteme(service: "fr.djoko.amaran.pont.tests"))
    }

    @Test func pontConnu() {
        #expect(PontConnu(nom: Self.nom, empreinte: "CA2A4FE7").hote == "1A2B3C4D5E6F7081.local")
    }

    /// Le texte d'une cle absente ne cite que le nom SRP.
    @Test func texteDeLaCleAbsente() {
        let t = ErreurTrousseauPonts.absente(Self.nom).description
        #expect(t.contains("1A2B3C4D5E6F7081.local"))
        #expect(t.contains("Activer l'accès réseau"))
    }
}
