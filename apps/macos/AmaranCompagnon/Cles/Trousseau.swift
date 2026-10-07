// Copie des cles dans le trousseau local du Mac (spec 3b, decision 4 et section 5),
// sur le modele de Trousseau.swift de Halo Compagnon (commit e114cd5) : element
// generique, sans groupe d'acces ni synchronisation, lie a la signature de l'app.
import AmaranProtocole
import Foundation
import Security
import Synchronization

/// La copie du reseau : un seul element. Les cles ne quittent le trousseau qu'au
/// dernier moment (chargement du pont, sauvegarde) ; l'apercu (empreintes, lampes,
/// date) se lit sans elles.
protocol TrousseauReseau: Sendable {
    func apercu() throws -> ApercuReseau?
    func lire() throws -> ReseauMesh
    func ranger(_ r: ReseauMesh) throws
    func oublier() throws
}

enum ErreurTrousseau: Error, Equatable, Sendable, CustomStringConvertible {
    case absente
    case systeme(Int32)
    case illisible

    var description: String {
        switch self {
        case .absente: tr("Aucune copie des clés sur ce Mac : « Copier depuis amaran Desktop ».")
        case .systeme(let s): tr("Trousseau : \(SecCopyErrorMessageString(s, nil) as String? ?? String(s))")
        case .illisible: tr("Copie des clés illisible dans le trousseau.")
        }
    }
}

/// Trousseau de session du Mac : mot de passe generique, service
/// `fr.djoko.amaran.reseau`, compte `reseau` ; valeur = les deux cles (32 octets) ;
/// attribut generique = l'apercu en JSON (sans cles) ; commentaire = les empreintes.
struct TrousseauSysteme: TrousseauReseau {
    let service: String
    static let compte = "reseau"

    init(service: String = "fr.djoko.amaran.reseau") {
        self.service = service
    }

    private var requete: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: Self.compte]
    }

    func apercu() throws -> ApercuReseau? {
        var q = requete
        q[kSecReturnAttributes as String] = true
        var r: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &r)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess else { throw ErreurTrousseau.systeme(s) }
        guard let a = r as? [String: Any], let g = a[kSecAttrGeneric as String] as? Data,
              let apercu = try? JSONDecoder().decode(ApercuReseau.self, from: g) else { throw ErreurTrousseau.illisible }
        return apercu
    }

    func lire() throws -> ReseauMesh {
        var q = requete
        q[kSecReturnData as String] = true
        q[kSecReturnAttributes as String] = true
        var r: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &r)
        if s == errSecItemNotFound { throw ErreurTrousseau.absente }
        guard s == errSecSuccess else { throw ErreurTrousseau.systeme(s) }
        guard let a = r as? [String: Any], var cles = a[kSecValueData as String] as? Data, cles.count == 32,
              let g = a[kSecAttrGeneric as String] as? Data,
              let apercu = try? JSONDecoder().decode(ApercuReseau.self, from: g) else { throw ErreurTrousseau.illisible }
        defer { cles.resetBytes(in: 0..<cles.count) }
        return ReseauMesh(cleReseau: Data(cles.prefix(16)), cleApplication: Data(cles.suffix(16)),
                          lampes: apercu.lampes, source: apercu.source ?? .amaranDesktop, date: apercu.date ?? Date())
    }

    func ranger(_ reseau: ReseauMesh) throws {
        var cles = reseau.cleReseau + reseau.cleApplication
        defer { cles.resetBytes(in: 0..<cles.count) }
        let apercu = try JSONEncoder().encode(reseau.apercu)
        let valeurs: [String: Any] = [
            kSecValueData as String: cles,
            kSecAttrGeneric as String: apercu,
            kSecAttrComment as String: "réseau \(reseau.empreinteReseau), application \(reseau.empreinteApplication)",
            kSecAttrLabel as String: "Amaran Compagnon - réseau des lampes",
        ]
        var s = SecItemUpdate(requete as CFDictionary, valeurs as CFDictionary)
        if s == errSecItemNotFound {
            s = SecItemAdd(requete.merging(valeurs) { $1 } as CFDictionary, nil)
        }
        guard s == errSecSuccess else { throw ErreurTrousseau.systeme(s) }
    }

    func oublier() throws {
        let s = SecItemDelete(requete as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw ErreurTrousseau.systeme(s) }
    }
}

/// Trousseau des tests et du mode demo : en memoire, isole du vrai.
final class TrousseauMemoire: TrousseauReseau {
    private let reseau = Mutex<ReseauMesh?>(nil)

    init(_ initial: ReseauMesh? = nil) {
        reseau.withLock { $0 = initial }
    }

    func apercu() throws -> ApercuReseau? { reseau.withLock { $0?.apercu } }

    func lire() throws -> ReseauMesh {
        guard let r = reseau.withLock({ $0 }) else { throw ErreurTrousseau.absente }
        return r
    }

    func ranger(_ r: ReseauMesh) throws { reseau.withLock { $0 = r } }

    func oublier() throws { reseau.withLock { $0 = nil } }
}
