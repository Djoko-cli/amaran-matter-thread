// Repris de Halo Compagnon (commit e114cd5, Reseau/AlerteReseau.swift) : la route IPv6
// vers le reseau Thread est celle que tient l'assistant systeme halo-routes de Halo.
import AmaranProtocole
import Foundation

/// Alerte de la source reseau, montree en bandeau.
enum AlerteReseau: Equatable, Sendable {
    case transport(ErreurTransportReseau)
    case trousseau(ErreurTrousseauPonts)
    /// DEFI recu, puis aucun `hello` (places de session prises, 10.3).
    case sansHello

    var texte: String {
        switch self {
        case .transport(.pasDeRoute): Self.textePasDeRoute(assistant: Self.assistantInstalle)
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

    static func textePasDeRoute(assistant: Bool) -> String {
        ErreurTransportReseau.pasDeRoute.description + " " + (assistant
            ? tr("L'assistant système halo-routes est installé : la route revient d'elle-même.")
            : tr("Installer l'assistant système halo-routes : tools/macos/halo-routes/installer.sh du dépôt github.com/Djoko-cli/benq-screenbar-halo-matter."))
    }

    /// Le plist de l'assistant halo-routes, s'il est installe (et que la sandbox laisse le voir).
    static var assistantInstalle: Bool {
        FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/fr.djoko.halo.routes.plist")
    }
}
