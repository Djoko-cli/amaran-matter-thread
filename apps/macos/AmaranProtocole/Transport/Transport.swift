// Repris de Halo Compagnon (commit e114cd5) : sans le transport UDP (plan 3b-2).
import Foundation

/// Ce qu'un transport remonte.
public enum EvenementTransport: Sendable, Equatable {
    /// Octets bruts, dans l'ordre de reception.
    case donnees(Data)
    /// Fermeture (EOF, erreur, re-enumeration USB, fermeture demandee). Le flux finit ensuite.
    case ferme(raison: String)
}

/// Transport d'octets : port serie USB, rejeu de demonstration (Thread viendra
/// au plan 3b-2). La couche protocole (tramage, session, correlation) ne connait
/// que ce protocole.
public protocol Transport: AnyObject, Sendable {
    var genre: GenreTransport { get }
    /// Nom lisible (chemin du port, "Démo"...).
    var nom: String { get }
    /// Ouvre le transport ; le flux se termine apres `.ferme`.
    func ouvrir() async throws -> AsyncStream<EvenementTransport>
    /// Envoi sans attente (ligne de 127 octets au plus).
    func envoyer(_ donnees: Data) throws
    /// Ferme sans toucher aux lignes de controle (DTR et RTS restent a 0).
    func fermer()
    /// Ferme apres avoir laisse partir les octets deja confies a `envoyer`
    /// (`json 0` avant de liberer le port), au plus quelques centaines de ms.
    /// `synchrone` : ne rend la main qu'une fois le transport ferme (fin de l'app).
    func fermerApresVidage(synchrone: Bool)
}

extension Transport {
    public func fermerApresVidage(synchrone: Bool) { fermer() }
}

/// Erreur de transport lisible.
public struct ErreurTransport: Error, Sendable, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}
