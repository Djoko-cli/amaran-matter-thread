// Repris de Halo Compagnon (commit e114cd5) : cle UDP de 32 octets creee par l'USB, code pur (sans le bloc `ip`, hors plan 3b-2).
import Foundation

/// Cle partagee du transport reseau, creee par l'USB (spec 3b, section 7) : l'app fournit
/// un alea, la carte calcule `cle = HMAC-SHA256(alea_app, alea_carte)` et la
/// rend une seule fois dans la reponse.
public enum CleReseau {
    /// Alea de l'app : 32 octets d'un generateur cryptographique.
    public static func alea() -> Data { H1.aleatoire(32) }

    /// `json cle nouvelle <64 HEXA>` (USB seulement ; la carte la refuse a distance).
    public static func commande(alea: Data) -> String {
        "json cle nouvelle \(H1.hexa(alea))"
    }

    public struct Creee: Sendable, Equatable {
        public var cle: Data
        public var empreinte: String
    }

    public enum Erreur: Error, Sendable, Equatable, CustomStringConvertible {
        /// `ok` faux (tampon USB occupe...) : rien n'a change sur la carte.
        case refusee(String)
        case cleIllisible
        case empreinteIncoherente

        public var description: String {
            switch self {
            case .refusee(let msg): "La carte refuse la nouvelle clé : \(msg)"
            case .cleIllisible: "Réponse sans clé lisible (64 hexa majuscules attendus) : clé non rangée."
            case .empreinteIncoherente: "Empreinte incohérente avec la clé reçue : clé non rangée."
            }
        }
    }

    /// Reponse `fin` a `json cle nouvelle` : la cle et son empreinte, verifiees.
    public static func verifier(_ r: Reponse) -> Result<Creee, Erreur> {
        guard r.ok else { return .failure(.refusee(r.msg ?? r.code.rawValue)) }
        guard let texte = r.cle, let cle = H1.octets(hexa: texte), cle.count == 32 else { return .failure(.cleIllisible) }
        guard let e = r.empreinte, e == H1.kid(cle: cle) else { return .failure(.empreinteIncoherente) }
        return .success(Creee(cle: cle, empreinte: e))
    }
}
