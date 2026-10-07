// Sauvegarde chiffree du reseau (spec 3b, section 5) : la copie du trousseau, dans
// un fichier que Djoko range ou il veut (iCloud Drive conseille). AES-GCM 256, cle
// tiree de la phrase de passe par PBKDF2-HMAC-SHA256 (600 000 tours, sel aleatoire
// de 16 octets). L'en-tete (magie, version, tours, sel) est authentifie avec le
// contenu : rien n'y change sans que l'ouverture echoue.
import CommonCrypto
import CryptoKit
import Foundation

public enum ErreurSauvegarde: Error, Sendable, Equatable, CustomStringConvertible {
    case phraseTropCourte(Int)
    case phrasesDifferentes
    /// Phrase de passe fausse ou fichier altere : jamais de detail.
    case ouvertureImpossible
    case pasUneSauvegarde
    case versionInconnue(UInt8)

    public var description: String {
        switch self {
        case .phraseTropCourte(let n): tr("Phrase de passe trop courte : \(Sauvegarde.phraseMin) caractères au moins (\(n)).")
        case .phrasesDifferentes: tr("Les deux phrases de passe diffèrent.")
        case .ouvertureImpossible: tr("Phrase de passe fausse, ou fichier altéré.")
        case .pasUneSauvegarde: tr("Ce fichier n'est pas une sauvegarde d'Amaran Compagnon.")
        case .versionInconnue(let v):
            tr("Sauvegarde de version \(String(v)) : cette app lit la version \(String(Sauvegarde.version)).")
        }
    }
}

public enum Sauvegarde {
    public static let magie = Data("AMARANSV".utf8)
    public static let version: UInt8 = 1
    public static let toursParDefaut: UInt32 = 600_000
    public static let phraseMin = 12
    static let tailleSel = 16
    static let toursMax: UInt32 = 10_000_000

    /// Phrase de passe : 12 caracteres au moins, tapee deux fois.
    public static func verifierPhrase(_ phrase: String, confirmation: String) throws(ErreurSauvegarde) {
        guard phrase.count >= phraseMin else { throw .phraseTropCourte(phrase.count) }
        guard phrase == confirmation else { throw .phrasesDifferentes }
    }

    /// Chiffre le reseau. `tours` : 600 000 hors des tests.
    public static func chiffrer(_ reseau: ReseauMesh, phrase: String,
                                tours: UInt32 = toursParDefaut) throws -> Data {
        var sel = Data(count: tailleSel)
        let r = sel.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, tailleSel, $0.baseAddress!) }
        guard r == errSecSuccess else { throw ErreurSauvegarde.ouvertureImpossible }
        var tete = magie
        tete.append(version)
        withUnsafeBytes(of: tours.bigEndian) { tete.append(contentsOf: $0) }
        tete.append(sel)
        var clair = try JSONEncoder().encode(reseau)
        defer { clair.resetBytes(in: 0..<clair.count) }
        let cle = try deriver(phrase: phrase, sel: sel, tours: tours)
        let boite = try AES.GCM.seal(clair, using: cle, authenticating: tete)
        guard let scelle = boite.combined else { throw ErreurSauvegarde.ouvertureImpossible }
        return tete + scelle
    }

    /// Dechiffre et verifie l'integrite (en-tete compris).
    public static func dechiffrer(_ fichier: Data, phrase: String) throws(ErreurSauvegarde) -> ReseauMesh {
        let tailleTete = magie.count + 1 + 4 + tailleSel
        let f = Data(fichier)  // indices a partir de 0
        guard f.count > tailleTete, f.prefix(magie.count) == magie else { throw .pasUneSauvegarde }
        let v = f[magie.count]
        guard v == version else { throw .versionInconnue(v) }
        let tours = f[(magie.count + 1)..<(magie.count + 5)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard (1...toursMax).contains(tours) else { throw .ouvertureImpossible }
        let sel = f[(magie.count + 5)..<tailleTete]
        let tete = f.prefix(tailleTete)
        do {
            let cle = try deriver(phrase: phrase, sel: Data(sel), tours: tours)
            let boite = try AES.GCM.SealedBox(combined: f.suffix(from: tailleTete))
            var clair = try AES.GCM.open(boite, using: cle, authenticating: tete)
            defer { clair.resetBytes(in: 0..<clair.count) }
            return try JSONDecoder().decode(ReseauMesh.self, from: clair)
        } catch {
            throw .ouvertureImpossible
        }
    }

    /// PBKDF2-HMAC-SHA256, 32 octets.
    static func deriver(phrase: String, sel: Data, tours: UInt32) throws -> SymmetricKey {
        var cle = [UInt8](repeating: 0, count: 32)
        defer { cle.withUnsafeMutableBytes { _ = memset($0.baseAddress!, 0, $0.count) } }
        // NFC : un « e » accentue compose ou decompose donne la meme cle.
        var mot = Array(phrase.precomposedStringWithCanonicalMapping.utf8)
        defer { mot.withUnsafeMutableBytes { _ = memset($0.baseAddress!, 0, $0.count) } }
        guard !mot.isEmpty, !sel.isEmpty else { throw ErreurSauvegarde.ouvertureImpossible }
        let r = sel.withUnsafeBytes { s in
            mot.withUnsafeBufferPointer { m in
                m.baseAddress!.withMemoryRebound(to: Int8.self, capacity: m.count) { p in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p, m.count,
                                         s.bindMemory(to: UInt8.self).baseAddress, s.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), tours, &cle, cle.count)
                }
            }
        }
        guard r == kCCSuccess else { throw ErreurSauvegarde.ouvertureImpossible }
        return SymmetricKey(data: cle)
    }
}
