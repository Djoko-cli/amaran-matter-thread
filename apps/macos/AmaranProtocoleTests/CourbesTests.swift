// Repris de Halo Compagnon (HaloProtocoleTests/CourbesTests.swift) : differences par
// fenetre et segments ; series du pont amaran (Mesh, relectures, ordres, tas).
import Foundation
import Testing
@testable import AmaranProtocole

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)  // multiple de 10

private func ech(_ s: Double, boot: String = "A", _ v: [Grandeur: Int]) -> Echantillon {
    Echantillon(date: t0.addingTimeInterval(s), boot: boot, valeurs: v)
}

private func message(_ json: String) -> MessageCarte {
    var r = RecepteurLignes()
    guard case .machine(let l) = r.alimenter(ligneMachine(json)).first else { return .inconnu }
    return l.message
}

@Suite("Courbes")
struct CourbesTests {
    @Test func segmentsSurDifferenceNegativeEtBoot() {
        let e = [
            ech(0, [.annonces: 10]),
            ech(1, [.annonces: 12]),
            ech(2, [.annonces: 3]),               // difference negative
            ech(3, [.annonces: 5]),
            ech(4, boot: "B", [.annonces: 6]),    // redemarrage
        ]
        #expect(Courbes.segmenter(e).map(\.count) == [2, 2, 1])
    }

    @Test func differencesParFenetre() {
        // Un echantillon par seconde pendant 30 s, 3 annonces par seconde.
        let e = (0...30).map { ech(Double($0), [.annonces: 3 * $0, .netmicFaux: $0 / 5]) }
        let d = Courbes.differences(e, fenetre: 10)
        #expect(d.count == 4)
        #expect(d[0].debut == t0 && d[0].fin == t0.addingTimeInterval(9))
        #expect(d[0][.annonces] == 27)
        #expect(d[1][.annonces] == 30)
        #expect(d[3][.annonces] == 3)
        #expect(d.allSatisfy { $0.segment == 0 })
        #expect(d.compactMap { $0[.annonces] }.reduce(0, +) == 90, "sans trou ni double compte")
    }

    @Test func pasDeValeurAberranteAuRedemarrage() {
        let e = [ech(0, [.netmicFaux: 100]), ech(5, [.netmicFaux: 110]), ech(12, boot: "B", [.netmicFaux: 2]),
                 ech(15, boot: "B", [.netmicFaux: 4])]
        let d = Courbes.differences(e, fenetre: 10)
        #expect(d.map { $0[.netmicFaux] } == [10, 2])
        #expect(d.map(\.segment) == [0, 1])
    }

    @Test func unTrouDEchantillonsOuvreUnSegment() {
        let e = [ech(0, [.annonces: 0]), ech(1, [.annonces: 10]), ech(591, [.annonces: 5910]), ech(592, [.annonces: 5920])]
        #expect(Courbes.segmenter(e).map(\.count) == [2, 2])
        #expect(Courbes.ecartMax(periodeMs: 1000) == 30)
        #expect(Courbes.ecartMax(periodeMs: 60000) == 180)
        #expect(Courbes.ecartMax(periodeMs: 0) == 30)
        let lent = [ech(0, [.annonces: 0]), ech(60, [.annonces: 6]), ech(120, [.annonces: 12])]
        #expect(Courbes.segmenter(lent, ecartMax: Courbes.ecartMax(periodeMs: 60000)).count == 1)
    }

    @Test func partsDuMesh() {
        let d = Difference(debut: t0, fin: t0.addingTimeInterval(60), segment: 0,
                           deltas: [.annonces: 200, .nidReconnu: 100, .netmicFaux: 25, .emis: 18, .echecsEmission: 2,
                                    .confirmes: 9, .abandons: 1])
        #expect(Courbes.partNetmicFaux(d) == 0.25, "rapportee aux annonces de notre reseau, pas a toutes")
        #expect(Courbes.partRefusEmission(d) == 0.1)
        #expect(Courbes.partAbandons(d) == 0.1)
        #expect(Courbes.parMinute(d, .annonces) == 200)
        let vide = Difference(debut: t0, fin: t0.addingTimeInterval(10), segment: 0,
                              deltas: [.annonces: 0, .nidReconnu: 0, .emis: 0, .echecsEmission: 0])
        #expect(Courbes.partNetmicFaux(vide) == nil, "pas de division par zero")
        #expect(Courbes.partRefusEmission(vide) == nil)
    }

    /// Les deux pannes que le graphique « NetMIC faux » doit montrer, aux proportions de
    /// l'exemple 9.1 (5 120 annonces, dont 1 630 de notre reseau et 3 402 d'un autre). Le
    /// pont ne verifie le NetMIC que d'un message qui porte notre NID (crochet.c).
    @Test func netmicFauxDistingueIVFauxEtClesPerimees() {
        // IV Index faux : chaque message de notre reseau a un NetMIC faux.
        let ivFaux = Difference(debut: t0, fin: t0.addingTimeInterval(60), segment: 0,
                                deltas: [.annonces: 5120, .nidReconnu: 1630, .nidInconnu: 3402, .netmicFaux: 1630])
        #expect(Courbes.partNetmicFaux(ivFaux) == 1, "IV Index faux : 100 %")
        // Cles perimees (reseau recree dans amaran Desktop) : plus aucun message ne porte
        // notre NID. Les annonces de notre reseau tombent a zero, sans NetMIC faux.
        let perimees = Difference(debut: t0, fin: t0.addingTimeInterval(60), segment: 0,
                                  deltas: [.annonces: 5120, .nidReconnu: 0, .nidInconnu: 5120, .netmicFaux: 0])
        #expect(perimees[.nidReconnu] == 0, "graphique des annonces : « de notre réseau » a zero")
        #expect(Courbes.partNetmicFaux(perimees) == nil, "pas de part sans annonce de notre reseau")
        // Sain : quelques NetMIC faux seulement.
        let sain = Difference(debut: t0, fin: t0.addingTimeInterval(60), segment: 0,
                              deltas: [.annonces: 5120, .nidReconnu: 1630, .nidInconnu: 3402, .netmicFaux: 0])
        #expect(Courbes.partNetmicFaux(sain) == 0)
        // Pendant un renouvellement des cles, un message peut compter deux NetMIC faux :
        // la part reste bornee a 100 %.
        let renouvellement = Difference(debut: t0, fin: t0.addingTimeInterval(10), segment: 0,
                                        deltas: [.nidReconnu: 10, .netmicFaux: 12])
        #expect(Courbes.partNetmicFaux(renouvellement) == 1)
    }

    @Test func cumul() {
        let e = [ech(0, [.emis: 1]), ech(1, [.emis: 3]), ech(2, boot: "B", [.emis: 0])]
        #expect(Courbes.cumul(e, .emis).map(\.valeur) == [1, 3, 0])
        #expect(Courbes.cumul(e, .emis).map(\.segment) == [0, 0, 1])
    }
}

@Suite("Series des graphiques")
struct SeriesCourbesTests {
    /// Les lignes des exemples de la specification nourrissent toutes les series.
    @Test func seriesDesExemples() throws {
        var s = SeriesCourbes()
        for (i, l) in try ExemplesSpec.decoder().enumerated() {
            s.ajouter(l.message, date: t0.addingTimeInterval(Double(i)))
        }
        #expect(s.mesh.count == 1)
        #expect(s.mesh.first?.valeurs[.annonces] == 5120)
        #expect(s.mesh.first?.valeurs[.echecsEmission] == 0)
        #expect(s.pont.first?.valeurs[.releves] == 41)
        #expect(s.pont.first?.valeurs[.confirmes] == 5)
        #expect(s.parts[1]?.map(\.valeur) == [97, 97, 97])
        #expect(s.parts[2]?.first?.valeur == 100)
        #expect(s.tas.map(\.valeur) == [112640, 112640])
        #expect(s.tasMin.first?.valeur == 103424)
        #expect(s.ordres[1]?.map(\.issue) == [.confirme])
        #expect(s.ordres[2]?.map(\.issue) == [.tenu, .abandon])
        #expect(s.delaisConfirmes(lampe: 1).map(\.valeur) == [410])
        #expect(s.delaisConfirmes(lampe: 2).isEmpty, "tenu et abandon n'ont pas de delai de confirmation")
        #expect(s.lampes == [1, 2])
        #expect(s.segment == 0, "un seul boot dans les exemples")
    }

    @Test func nouveauBootNouveauSegment() {
        var s = SeriesCourbes()
        s.ajouter(message(#"{"v":1,"t":"etat","n":1,"ms":1,"bloc":"sante","boot":"3FA2C901","up_s":1,"sys":{"heap":1000,"heap_min":900}}"#), date: t0)
        s.ajouter(message(#"{"v":1,"t":"etat","n":2,"ms":2,"bloc":"lampe","lampe":1,"part_10min":null}"#), date: t0.addingTimeInterval(1))
        s.ajouter(message(#"{"v":1,"t":"hello","n":0,"ms":5,"bloc":"base","boot":"0B0C0D0E","up_s":0}"#), date: t0.addingTimeInterval(2))
        s.ajouter(message(#"{"v":1,"t":"etat","n":3,"ms":6,"bloc":"sante","boot":"0B0C0D0E","up_s":1,"sys":{"heap":2000}}"#), date: t0.addingTimeInterval(3))
        s.ajouter(message(#"{"v":1,"t":"compteurs","n":4,"ms":7,"bloc":"mesh","annonces":3}"#), date: t0.addingTimeInterval(4))
        s.ajouter(message(#"{"v":1,"t":"ordre","n":5,"ms":8,"lampe":1,"issue":"confirme","delai_ms":350,"essai":1,"ids":[],"ids_perdus":0}"#), date: t0.addingTimeInterval(5))
        #expect(s.segment == 1)
        #expect(s.boot == "0B0C0D0E")
        #expect(s.tas.map(\.segment) == [0, 1])
        #expect(s.tas.map(\.valeur) == [1000, 2000])
        #expect(s.parts[1]?.first?.valeur == nil, "part inconnue : un point sans valeur")
        #expect(s.mesh.first?.boot == "0B0C0D0E")
        #expect(s.ordres[1]?.first?.segment == 1)
        s.vider()
        #expect(s == SeriesCourbes())
    }

    @Test func seriesBornees() {
        var s = SeriesCourbes(capacite: 3)
        for i in 0..<5 {
            s.ajouter(.etatSante(BlocSante(boot: "A", sys: BlocSante.Systeme(heap: i))), date: t0.addingTimeInterval(Double(i)))
        }
        #expect(s.tas.map(\.valeur) == [2, 3, 4])
    }
}
