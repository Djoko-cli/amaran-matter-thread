// Carte « Bluetooth Mesh » du tableau de bord et ecran Graphiques, source reseau : le
// profil d'une session distante coupe les compteurs (`json compteurs 0`, docs/PROTOCOLE-JSON.md
// 10.5), donc IV Index, annonces, NetMIC faux et emis / refus n'arrivent pas, et un bloc
// recu avant (session precedente) garde des valeurs figees. Logique pure : ce que les deux
// ecrans disent, et d'ou vient l'IV Index.
import AmaranProtocole
import Foundation

enum CompteursMesh {
    /// Etat des compteurs du Mesh pour la carte et les graphiques.
    enum Etat: Equatable {
        /// Rien a dire : par l'USB, ou les compteurs du releve en cours arrivent.
        case normal
        /// A distance, periode a 0 (profil d'une session distante, `json compteurs 0`) :
        /// le pont ne les envoie pas. Un bloc d'avant (session precedente) n'est plus releve :
        /// ses valeurs ne sont jamais montrees comme actuelles. Les ecrans proposent de les
        /// activer.
        case nonReleves
        /// A distance, periode demandee, premier bloc du releve pas encore arrive.
        case demandes
    }

    /// Periode proposee par « Activer » (`json compteurs 5000` : le plus court permis a distance).
    static let periodeProposeeMs = 5000

    /// `enDirect` : un bloc est arrive depuis que la periode est non nulle (`Pont.compteursEnDirect`).
    static func etat(aDistance: Bool, enDirect: Bool, periodeMs: Int?) -> Etat {
        guard aDistance else { return .normal }
        guard let p = periodeMs, p > 0 else { return .nonReleves }
        return enDirect ? .normal : .demandes
    }

    /// La phrase commune a la carte « Bluetooth Mesh » et a l'ecran Graphiques ; nil :
    /// rien a dire. `dernierReleve` : date du dernier bloc recu (une session precedente).
    static func texte(_ e: Etat, dernierReleve: Date?) -> String? {
        switch e {
        case .normal:
            return nil
        case .nonReleves:
            let style = Date.FormatStyle(date: .omitted, time: .standard, locale: Localisation.partagee.locale)
            let heure = dernierReleve.map { tr(" (dernier relevé à \($0.formatted(style)))") } ?? ""
            return tr("Compteurs du Mesh non relevés à distance\(heure)")
        case .demandes:
            return tr("Compteurs du Mesh demandés, en attente du premier relevé")
        }
    }

    /// IV Index montre par la carte : celui des compteurs du releve en cours ; sans eux,
    /// celui que le pont garde en NVS (`config` `mesh` `iv_nvs`), et la carte le dit.
    static func ivIndex(compteurs: Int?, ivNvs: Int?) -> (texte: String, deNvs: Bool)? {
        if let compteurs { return (String(compteurs), false) }
        if let ivNvs { return (tr("\(String(ivNvs)) (mémoire du pont)"), true) }
        return nil
    }
}

extension Pont {
    var etatCompteursMesh: CompteursMesh.Etat {
        CompteursMesh.etat(aDistance: aDistance, enDirect: compteursEnDirect, periodeMs: reglages?.compteursMs)
    }

    /// Bloc `compteurs` que les ecrans peuvent montrer comme actuel : par l'USB, le dernier ;
    /// a distance, seulement celui du releve en cours (nil sinon : lignes « – »).
    var compteursMeshActuels: AmaranProtocole.CompteursMesh? {
        etatCompteursMesh == .normal ? etat.compteurs?.valeur : nil
    }

    /// Phrase de la carte et des graphiques (nil : rien a dire).
    var texteCompteursMesh: String? {
        CompteursMesh.texte(etatCompteursMesh, dernierReleve: etat.compteurs?.date)
    }

    var ivIndexMesh: (texte: String, deNvs: Bool)? {
        CompteursMesh.ivIndex(compteurs: compteursMeshActuels?.iv, ivNvs: etat.mesh?.valeur.ivNvs)
    }

    /// « Activer » : `json compteurs 5000`, permis a distance (10.5).
    func activerCompteursMesh() {
        reglerCadence(.compteurs, ms: CompteursMesh.periodeProposeeMs)
    }
}
