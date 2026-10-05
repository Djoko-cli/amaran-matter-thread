// Filtres de l'ecran « Trames » (spec 3b, section 8) : sens, lampe, nature du message.
// Code pur, sans vue : les tests le jugent directement.
import AmaranProtocole
import Foundation

struct FiltreTrames: Equatable, Sendable {
    /// Lampe visee par une trame : une lampe, le groupe (demande d'etat), ou toutes.
    enum Cible: Hashable, Sendable {
        case toutes
        case groupe
        case lampe(Int)
    }

    /// nil : les deux sens.
    var sens: SensTrame?
    var cible: Cible = .toutes
    /// Natures montrees. Une nature que l'app ne connait pas (`inconnu`, absente) n'est
    /// jamais cachee : une trace qu'on ne comprend pas ne se filtre pas en silence.
    var quoi: Set<QuoiTrame> = [.ordre, .demande, .etat]

    func garde(_ t: Trame) -> Bool {
        if let sens, t.sens != sens { return false }
        switch cible {
        case .toutes: break
        case .groupe: if t.lampe != nil { return false }
        case .lampe(let n): if t.lampe != n { return false }
        }
        if let q = t.quoi, q != .inconnu, !quoi.contains(q) { return false }
        return true
    }

    /// Les trames gardees, de la plus recente a la plus ancienne.
    func appliquer(_ source: [TrameRecue]) -> [TrameRecue] {
        source.reversed().filter { garde($0.trame) }
    }

    /// « 1 · Lampe bureau », ou « Groupe » pour la demande d'etat.
    static func libelleCible(_ t: Trame, noms: [Int: String]) -> String {
        guard let n = t.lampe else { return "Groupe" }
        return noms[n].map { "\(n) · \($0)" } ?? "\(n)"
    }

    /// Aucun filtre : tout est montre.
    var estNeutre: Bool { self == FiltreTrames() }
}

extension SensTrame {
    var libelle: String {
        switch self {
        case .tx: "Émise"
        case .rx: "Reçue"
        case .inconnu: "?"
        }
    }

    var fleche: String {
        switch self {
        case .tx: "→"
        case .rx: "←"
        case .inconnu: "?"
        }
    }
}

extension QuoiTrame {
    var libelle: String {
        switch self {
        case .ordre: "Ordre"
        case .demande: "Demande d'état"
        case .etat: "État"
        case .inconnu: "Inconnu"
        }
    }
}
