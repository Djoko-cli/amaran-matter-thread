// Repris de Halo Compagnon (commit e114cd5) : enveloppe et decodeur ; les messages
// sont ceux du pont amaran (docs/PROTOCOLE-JSON.md, sections 5 et 7).
import Foundation

/// Champs communs a toutes les lignes machine (section 4).
public struct Enveloppe: Codable, Sendable, Equatable {
    /// Version majeure du protocole.
    public var v: Int
    /// Type de message.
    public var t: String
    /// Numero de ligne produite depuis le demarrage.
    public var n: UInt32
    /// Millisecondes depuis le demarrage, a la production de la ligne.
    public var ms: UInt32?
    /// Partie d'un message en blocs.
    public var bloc: String?
}

/// Un message du pont, decode selon (`t`, `bloc`).
public enum MessageCarte: Sendable, Equatable {
    case helloBase(HelloBase)
    case helloIdentite(HelloIdentite)
    case configCatalogue(ConfigCatalogue)
    case configMesh(ConfigMesh)
    case configLampe(ConfigLampe)
    case etatPont(BlocPont)
    case etatLampe(BlocLampe)
    case etatSante(BlocSante)
    case compteursMesh(CompteursMesh)
    case reseauMatter(ReseauMatter)
    case reseauThread(ReseauThread)
    case reseauIp(ReseauIp)
    case battement(Battement)
    case fin(FinSession)
    case reponse(Reponse)
    case ordre(EvenementOrdre)
    case alerte(Alerte)
    case lampe(EvenementLampe)
    case led(ChangementLed)
    case log(MessageLog)
    case trame(Trame)
    case texte(TexteCommande)
    /// Type ou bloc inconnu : ignore (section 8).
    case inconnu

    /// Vrai pour les messages periodiques (instantanes), faux pour les evenements.
    public var estPeriodique: Bool {
        switch self {
        case .helloBase, .helloIdentite, .configCatalogue, .configMesh, .configLampe, .etatPont, .etatLampe,
             .etatSante, .compteursMesh, .reseauMatter, .reseauThread, .reseauIp, .battement:
            true
        default:
            false
        }
    }

    /// La meme valeur, sans la cle si c'est une `reponse` a `json cle nouvelle` (6.3, 10.2) :
    /// pour tout historique qui garde le message entier (journal des trames).
    public var sansCle: MessageCarte {
        if case .reponse(let r) = self { return .reponse(r.sansCle) }
        return self
    }
}

/// Ligne machine valide et decodee.
public struct LigneMachine: Sendable, Equatable {
    public var enveloppe: Enveloppe
    public var message: MessageCarte
    /// Le JSON tel que recu, pour le journal et l'inspection.
    public var json: String

    public init(enveloppe: Enveloppe, message: MessageCarte, json: String) {
        self.enveloppe = enveloppe
        self.message = message
        self.json = json
    }

    /// La meme ligne, sans la cle UDP : ni dans le message (`sansCle`), ni dans le JSON
    /// garde (`"cle":"<hexa>"` masque). A appliquer avant tout journal.
    public var sansCle: LigneMachine {
        // Une reponse a `json cle nouvelle` porte la cle dans un champ "cle" (6.3) ; une
        // ligne alteree mais encore valide la porterait sous un autre nom : le JSON passe
        // toujours par le masque (32 hexa d'un bloc compris).
        LigneMachine(enveloppe: enveloppe, message: message.sansCle, json: PolitiqueCommandes.masquerCle(json))
    }
}

/// Decodage d'un objet JSON du pont : enveloppe d'abord, puis un `Codable`
/// par (`t`, `bloc`) (section 8).
public enum DecodeurMessages {
    /// Versions majeures gerees par l'app.
    public static let versionsGerees: Set<Int> = [1]

    public enum Resultat: Sendable, Equatable {
        case valide(LigneMachine)
        /// Enveloppe absente ou mal typee : ligne abimee.
        case abimee(String)
        case versionInconnue(v: Int, t: String)
        /// Champ obligatoire absent ou mal type dans le corps.
        case invalide(t: String, raison: String)
    }

    private static func decodeur() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    public static func decoder(json: Data) -> Resultat {
        let d = decodeur()
        let enveloppe: Enveloppe
        do {
            enveloppe = try d.decode(Enveloppe.self, from: json)
        } catch {
            return .abimee("enveloppe : \(Self.raison(error))")
        }
        guard versionsGerees.contains(enveloppe.v) else {
            return .versionInconnue(v: enveloppe.v, t: enveloppe.t)
        }
        let texte = String(decoding: json, as: UTF8.self)
        do {
            let message = try corps(enveloppe: enveloppe, json: json, decodeur: d)
            return .valide(LigneMachine(enveloppe: enveloppe, message: message, json: texte))
        } catch {
            return .invalide(t: enveloppe.t, raison: Self.raison(error))
        }
    }

    private static func corps(enveloppe e: Enveloppe, json: Data, decodeur d: JSONDecoder) throws -> MessageCarte {
        switch (e.t, e.bloc) {
        case ("hello", "base"): return .helloBase(try d.decode(HelloBase.self, from: json))
        case ("hello", "identite"): return .helloIdentite(try d.decode(HelloIdentite.self, from: json))
        case ("config", "catalogue"): return .configCatalogue(try d.decode(ConfigCatalogue.self, from: json))
        case ("config", "mesh"): return .configMesh(try d.decode(ConfigMesh.self, from: json))
        case ("config", "lampe"): return .configLampe(try d.decode(ConfigLampe.self, from: json))
        case ("etat", "pont"): return .etatPont(try d.decode(BlocPont.self, from: json))
        case ("etat", "lampe"): return .etatLampe(try d.decode(BlocLampe.self, from: json))
        case ("etat", "sante"): return .etatSante(try d.decode(BlocSante.self, from: json))
        case ("compteurs", "mesh"): return .compteursMesh(try d.decode(CompteursMesh.self, from: json))
        case ("reseau", "matter"): return .reseauMatter(try d.decode(ReseauMatter.self, from: json))
        case ("reseau", "thread"): return .reseauThread(try d.decode(ReseauThread.self, from: json))
        case ("reseau", "ip"): return .reseauIp(try d.decode(ReseauIp.self, from: json))
        case ("hb", _): return .battement(try d.decode(Battement.self, from: json))
        case ("fin", _): return .fin(try d.decode(FinSession.self, from: json))
        case ("reponse", _): return .reponse(try d.decode(Reponse.self, from: json))
        case ("ordre", _): return .ordre(try d.decode(EvenementOrdre.self, from: json))
        case ("alerte", _): return .alerte(try d.decode(Alerte.self, from: json))
        case ("lampe", _): return .lampe(try d.decode(EvenementLampe.self, from: json))
        case ("led", _): return .led(try d.decode(ChangementLed.self, from: json))
        case ("log", _): return .log(try d.decode(MessageLog.self, from: json))
        case ("trame", _): return .trame(try d.decode(Trame.self, from: json))
        case ("texte", _): return .texte(try d.decode(TexteCommande.self, from: json))
        default: return .inconnu
        }
    }

    static func raison(_ erreur: any Error) -> String {
        guard let e = erreur as? DecodingError else { return String(describing: erreur) }
        func chemin(_ c: [any CodingKey]) -> String {
            c.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch e {
        case .keyNotFound(let cle, let ctx):
            let base = chemin(ctx.codingPath)
            let champ = (base.isEmpty ? "" : base + ".") + cle.stringValue
            return "champ absent : \(champ)"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return "champ mal typé : \(chemin(ctx.codingPath))"
        case .dataCorrupted(let ctx):
            return "JSON invalide \(chemin(ctx.codingPath))"
        @unknown default:
            return "décodage impossible"
        }
    }
}
