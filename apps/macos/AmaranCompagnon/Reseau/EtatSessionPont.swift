// Etat de la session reseau d'un pont connu (Reglages › Acces reseau Thread) : lecture
// seule du modele, rien n'est envoye.
import AmaranProtocole
import Foundation

enum EtatSessionPont: Equatable, Sendable {
    /// Ce pont n'est pas la source en cours.
    case aucune
    /// Ouverture, poignee de main ou reconnexion en cours.
    case enCours
    case ouverte
    /// Le pont, ou le chemin, refuse ou ne repond pas : la raison, courte.
    case refusee(String)

    var libelle: String {
        switch self {
        case .aucune: tr("pas de session")
        case .enCours: tr("session en cours d'ouverture")
        case .ouverte: tr("session ouverte")
        case .refusee(let raison): tr("session refusée : \(raison)")
        }
    }
}

extension Pont {
    /// Session de ce pont (nom SRP, sans `.local`) : ouverte, en cours, refusee ou aucune.
    func etatSession(pour nom: String) -> EtatSessionPont {
        guard source == .reseau(nom: nom) else { return .aucune }
        if let a = alerteReseau { return .refusee(a.raison) }
        switch etatTransport {
        case .ouvert:
            switch phase {
            case .connecte: return .ouverte
            case .sansReponse: return .refusee(tr("aucune réponse"))
            default: return .enCours
            }
        case .ouverture, .attente: return .enCours
        case .ferme, .libere: return .aucune
        case .erreur(let e): return .refusee(e)
        }
    }
}
