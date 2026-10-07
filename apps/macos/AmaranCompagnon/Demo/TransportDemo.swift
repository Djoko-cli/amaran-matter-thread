// Repris de Halo Compagnon (commit e114cd5) : transport du mode demo, avec le pont
// simule (SimulateurDemo) et sa memoire, qui survit a ses redemarrages.
import AmaranProtocole
import Foundation
import Synchronization

/// Chaque ouverture est un nouveau demarrage du pont simule (nouveau `boot`) ; quand
/// il redemarre, le flux se ferme comme a une re-enumeration USB : l'app se
/// reconnecte seule.
final class TransportDemo: Transport {
    let genre: GenreTransport = .demo
    /// Nom montre a l'utilisateur, dans la langue en vigueur.
    static var nomLisible: String { tr("Démo (pont simulé à trois lampes)") }
    var nom: String { Self.nomLisible }

    private struct Etat {
        var tache: Task<Void, Never>?
        var entrees: AsyncStream<Data>.Continuation?
        var sortie: AsyncStream<EvenementTransport>.Continuation?
        var memoire = MemoireDemo.initiale
    }

    private let vitesse: Double
    private let etat: Mutex<Etat>

    /// `vitesse` : facteur du temps du pont simule (les tests vont plus vite).
    /// `annonceLogiciel` faux : un pont d'avant la fiche des lampes (tests).
    init(vitesse: Double = 1, annonceLogiciel: Bool = true) {
        self.vitesse = vitesse
        var memoire = MemoireDemo.initiale
        if !annonceLogiciel {
            memoire.annonceLogiciel = false
            for i in memoire.lampes.indices {
                memoire.lampes[i].logiciel = nil
                memoire.lampes[i].ble = nil
            }
        }
        etat = Mutex(Etat(memoire: memoire))
    }

    func ouvrir() async throws -> AsyncStream<EvenementTransport> {
        let (flux, sortie) = AsyncStream.makeStream(of: EvenementTransport.self, bufferingPolicy: .unbounded)
        let (entrees, suiteEntrees) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        let memoire = etat.withLock { $0.memoire }
        let boot = String(format: "%08X", UInt32.random(in: .min ... .max))
        let simulateur = SimulateurDemo(sortie: sortie, boot: boot, vitesse: vitesse, memoire: memoire) { [weak self] m in
            self?.etat.withLock { $0.memoire = m }
        }
        let tache = Task.detached(priority: .userInitiated) {
            await simulateur.executer(entrees: entrees)
            sortie.finish()
        }
        etat.withLock { e in
            e.tache = tache
            e.entrees = suiteEntrees
            e.sortie = sortie
        }
        return flux
    }

    func envoyer(_ donnees: Data) throws {
        guard let entrees = etat.withLock({ $0.entrees }) else { throw ErreurTransport(tr("démo arrêtée")) }
        entrees.yield(donnees)
    }

    func fermer() {
        let (tache, entrees, sortie) = etat.withLock { e in
            let r = (e.tache, e.entrees, e.sortie)
            e.tache = nil
            e.entrees = nil
            e.sortie = nil
            return r
        }
        entrees?.finish()
        tache?.cancel()
        sortie?.yield(.ferme(raison: tr("démo arrêtée")))
        sortie?.finish()
    }
}
