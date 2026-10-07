// Carte « Bluetooth Mesh » et ecran Graphiques a distance : l'explication des compteurs
// absents ou figes, et l'origine de l'IV Index (logique pure, docs/PROTOCOLE-JSON.md 10.5).
import AmaranProtocole
import Foundation
import Testing
@testable import AmaranCompagnon

@Suite("Compteurs du Mesh a distance", .langue(.francais))
struct CompteursMeshTests {
    @Test func parLUSBRienNeChange() {
        #expect(CompteursMesh.etat(aDistance: false, enDirect: false, periodeMs: 1000) == .normal)
        #expect(CompteursMesh.etat(aDistance: false, enDirect: false, periodeMs: nil) == .normal)
        #expect(CompteursMesh.etat(aDistance: false, enDirect: true, periodeMs: 0) == .normal)
        #expect(CompteursMesh.texte(.normal, dernierReleve: Date()) == nil)
    }

    @Test func aDistanceSansCompteurs() {
        #expect(CompteursMesh.etat(aDistance: true, enDirect: false, periodeMs: 0) == .nonReleves)
        #expect(CompteursMesh.etat(aDistance: true, enDirect: false, periodeMs: nil) == .nonReleves)
        #expect(CompteursMesh.etat(aDistance: true, enDirect: false, periodeMs: 5000) == .demandes)
        #expect(CompteursMesh.etat(aDistance: true, enDirect: true, periodeMs: 5000) == .normal)
    }

    /// Un bloc recu dans une session precedente ne fait jamais passer la carte pour
    /// relevee : periode a 0, « non releves », quel que soit ce qui a ete recu avant.
    @Test func periodeNulleToujoursNonReleves() {
        #expect(CompteursMesh.etat(aDistance: true, enDirect: true, periodeMs: 0) == .nonReleves)
        let texte = CompteursMesh.texte(.nonReleves, dernierReleve: Date(timeIntervalSinceReferenceDate: 800_000_000))
        #expect(texte?.hasPrefix("Compteurs du Mesh non relevés à distance (dernier relevé à ") == true)
        #expect(CompteursMesh.texte(.nonReleves, dernierReleve: nil) == "Compteurs du Mesh non relevés à distance")
        #expect(CompteursMesh.texte(.demandes, dernierReleve: nil) == "Compteurs du Mesh demandés, en attente du premier relevé")
    }

    @Test func periodeProposeeEstPermiseADistance() {
        // 10.5 : `json compteurs` 0 ou 5 000 a 60 000 ms.
        #expect(PolitiqueCommandes.autoriseeADistance("json compteurs \(CompteursMesh.periodeProposeeMs)") == nil)
    }

    @Test func ivIndex() {
        #expect(CompteursMesh.ivIndex(compteurs: 3, ivNvs: 2)?.texte == "3")
        #expect(CompteursMesh.ivIndex(compteurs: 3, ivNvs: 2)?.deNvs == false)
        #expect(CompteursMesh.ivIndex(compteurs: nil, ivNvs: 2)?.texte == "2 (mémoire du pont)")
        #expect(CompteursMesh.ivIndex(compteurs: nil, ivNvs: 0)?.deNvs == true)
        #expect(CompteursMesh.ivIndex(compteurs: nil, ivNvs: nil) == nil)
    }
}
