// Repris de Halo Compagnon (commit e114cd5, Reseau/AlerteReseau.swift ; Thread Route : deploiement
// du 06/10) : la route IPv6 vers le reseau Thread est celle que tient le demon Thread Route.
import AmaranProtocole
import Foundation

/// Alerte de la source reseau, montree en bandeau.
enum AlerteReseau: Equatable, Sendable {
    case transport(ErreurTransportReseau)
    case trousseau(ErreurTrousseauPonts)
    /// DEFI recu, puis aucun `hello` (places de session prises, 10.3).
    case sansHello

    /// Le texte du bandeau, avec l'etat reel de Thread Route (lu seulement pour "pas de route").
    var texte: String { texte(etatThreadRoute: { EtatThreadRoute.lire() }) }

    /// Le meme texte, l'etat de Thread Route venant de `etatThreadRoute` : les tests le fixent.
    func texte(etatThreadRoute: () -> EtatThreadRoute) -> String {
        switch self {
        case .transport(.pasDeRoute): Self.textePasDeRoute(etatThreadRoute())
        case .transport(let e): e.description
        case .trousseau(let e): e.description
        case .sansHello:
            tr("Aucune réponse au json 1 par le réseau : deux autres sessions déjà actives (autre Mac, script de banc) ? Nouvel essai toutes les 30 s.")
        }
    }

    /// Cause en quelques mots (liste des ponts connus).
    var raison: String {
        switch self {
        case .transport(.pasDeRoute): tr("pas de route IPv6")
        case .transport(.reseauLocalRefuse): tr("accès au réseau local refusé")
        case .transport(.portInjoignable): tr("le pont n'a plus de clé")
        case .transport(.nomIntrouvable): tr("pont introuvable")
        case .transport: tr("erreur réseau")
        case .trousseau(.absente): tr("clé absente de ce Mac")
        // La cle peut y etre : le trousseau en refuse la lecture (app recompilee ad hoc,
        // « Refuser » a l'invite) ; le bandeau donne le message du systeme.
        case .trousseau(.systeme): tr("trousseau inaccessible")
        case .sansHello: tr("aucune réponse, sessions prises ?")
        }
    }

    /// Sans route : la route revient d'elle-meme si Thread Route est actif ; sinon, ce qu'il reste a faire.
    static func textePasDeRoute(_ etat: EtatThreadRoute) -> String {
        ErreurTransportReseau.pasDeRoute.description + " "
            + (etat.consigne ?? tr("Thread Route est actif : la route revient d'elle-même."))
    }
}
