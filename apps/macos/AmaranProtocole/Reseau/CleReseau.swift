// Repris de Halo Compagnon (commit e114cd5) : cle UDP de 32 octets creee par l'USB, code pur ;
// l'etat de l'acces reseau se lit dans le bloc `ip` (docs/PROTOCOLE-JSON.md 5.5, 10.2).
import Foundation

/// Cle partagee du transport reseau, creee par l'USB (spec 3b, section 7) : l'app fournit
/// un alea, le pont calcule `cle = HMAC-SHA256(alea_app, alea_pont)` et la
/// rend une seule fois dans la reponse.
public enum CleReseau {
    /// Alea de l'app : 32 octets d'un generateur cryptographique.
    public static func alea() -> Data { H1.aleatoire(32) }

    /// `json cle nouvelle <64 HEXA>` (USB seulement ; le pont la refuse a distance).
    public static func commande(alea: Data) -> String {
        "json cle nouvelle \(H1.hexa(alea))"
    }

    public struct Creee: Sendable, Equatable {
        public var cle: Data
        public var empreinte: String
    }

    public enum Erreur: Error, Sendable, Equatable, CustomStringConvertible {
        /// `ok` faux (tampon USB occupe...) : rien n'a change sur le pont.
        case refusee(String)
        case cleIllisible
        case empreinteIncoherente

        public var description: String {
            switch self {
            case .refusee(let msg): "Le pont refuse la nouvelle clé : \(msg)"
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

/// Acces reseau vu par l'USB : bloc `ip` du pont (5.5), et cles de ce Mac.
public enum EtatAccesReseau: Sendable, Equatable {
    /// Pas de bloc `ip` (pas encore recu), nom SRP inconnu, ou firmware sans canal
    /// UDP (pas de `udp`).
    case inconnu
    /// Le pont n'a pas de cle : port 5480 ferme.
    case sansCle(nom: String)
    /// La cle du pont est celle que ce Mac garde pour ce nom SRP.
    case cleConnue(nom: String, empreinte: String)
    /// Le pont a une cle que ce Mac n'a pas (autre Mac, cle recreee ailleurs).
    case cleInconnue(nom: String, empreinte: String)

    /// `empreinteDuMac` : empreinte de la cle que ce Mac garde pour un nom SRP, nil sans cle.
    /// Une cle existe si `udp.cle` le dit (a defaut, si le port ecoute) et qu'elle a une empreinte.
    public static func depuis(ip: ReseauIp?, empreinteDuMac: (String) -> String?) -> EtatAccesReseau {
        guard let nom = ip?.srp, !nom.isEmpty, let udp = ip?.udp else { return .inconnu }
        guard udp.cle ?? (udp.ouvert == true), let e = udp.empreinte, !e.isEmpty else { return .sansCle(nom: nom) }
        return empreinteDuMac(nom) == e ? .cleConnue(nom: nom, empreinte: e) : .cleInconnue(nom: nom, empreinte: e)
    }

    /// Nom SRP du pont, s'il est connu.
    public var nom: String? {
        switch self {
        case .inconnu: nil
        case .sansCle(let n), .cleConnue(let n, _), .cleInconnue(let n, _): n
        }
    }
}
