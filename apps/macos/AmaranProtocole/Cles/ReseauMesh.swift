// Le reseau Bluetooth Mesh des lampes : ses deux cles et la liste des lampes, tels
// qu'amaran Desktop les connait (spec 3b, section 5). Les cles ne sont jamais
// affichees, journalisees ni copiees : seulement leurs empreintes.
import CryptoKit
import Foundation

/// Empreinte d'une cle : les 8 premiers chiffres hexa, en majuscules, de son
/// SHA-256 (comme le pont, `config_empreinte`, et outils/cles_amaran.py).
public enum Empreinte {
    public static func de(_ cle: Data) -> String {
        SHA256.hash(data: cle).prefix(4).map { String(format: "%02X", $0) }.joined()
    }
}

/// Une lampe du reseau.
public struct LampeReseau: Codable, Sendable, Equatable, Hashable {
    /// Adresse unicast Bluetooth Mesh.
    public var adresse: UInt16
    /// `AA:BB:CC:DD:EE:FF`, en majuscules.
    public var mac: String
    public var nom: String
    /// Code produit Sidus ; 0 : inconnu.
    public var code: UInt32
    /// Capacites au-dela de l'intensite que sa composition declare (`cct`,
    /// `couleur`) : un modele a cataloguer si le pont ne les lui connait pas.
    public var declarees: [String]

    public init(adresse: UInt16, mac: String, nom: String, code: UInt32, declarees: [String] = []) {
        self.adresse = adresse
        self.mac = mac
        self.nom = nom
        self.code = code
        self.declarees = declarees
    }
}

/// Faute trouvee par les pre-controles : rien n'est envoye au pont.
public enum ErreurReseau: Error, Sendable, Equatable, CustomStringConvertible {
    case cle(String)
    case nombreLampes(Int)
    case adresse(lampe: Int, UInt16)
    case adresseDuPont(lampe: Int, UInt16)
    case adresseEnDouble(UInt16)
    case mac(lampe: Int)
    case macEnDouble(String)
    case nom(lampe: Int, String)

    public var description: String {
        switch self {
        case .cle(let quoi): "Clé \(quoi) : 16 octets attendus."
        case .nombreLampes(let n): "\(n) lampe(s) : le pont en gère de 1 à \(ReseauMesh.capacite)."
        case .adresse(let l, let a): "Lampe \(l) : adresse 0x\(String(format: "%04X", a)) hors de 0x0001–0x7FFF."
        case .adresseDuPont(let l, let a):
            "Lampe \(l) : adresse 0x\(String(format: "%04X", a)) dans la plage du pont (0x7F00–0x7F7F)."
        case .adresseEnDouble(let a): "Adresse 0x\(String(format: "%04X", a)) en double."
        case .mac(let l): "Lampe \(l) : MAC illisible."
        case .macEnDouble(let m): "MAC \(m) en double."
        case .nom(let l, let raison): "Lampe \(l) : \(raison)."
        }
    }
}

/// Les cles du reseau et ses lampes : copie d'amaran Desktop, gardee dans le
/// trousseau et dans les sauvegardes.
public struct ReseauMesh: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case amaranDesktop
        case sauvegarde
    }

    /// LISTE_CAPACITE du pont.
    public static let capacite = 16
    /// Nom d'une lampe : 31 octets au plus (NodeLabel de Matter, NUL compris dans 32).
    public static let nomMax = 31
    /// Plage des adresses du pont (spec du pont 5.4) : jamais celle d'une lampe.
    public static let plageDuPont: ClosedRange<UInt16> = 0x7F00...0x7F7F

    public var cleReseau: Data
    public var cleApplication: Data
    public var lampes: [LampeReseau]
    public var source: Source
    /// Date de la copie depuis amaran Desktop.
    public var date: Date

    public init(cleReseau: Data, cleApplication: Data, lampes: [LampeReseau], source: Source, date: Date) {
        self.cleReseau = cleReseau
        self.cleApplication = cleApplication
        self.lampes = lampes
        self.source = source
        self.date = date
    }

    public var empreinteReseau: String { Empreinte.de(cleReseau) }
    public var empreinteApplication: String { Empreinte.de(cleApplication) }

    /// Pre-controles avant tout envoi (spec 3b, section 5) : rien n'est ecrit dans le
    /// pont si l'un d'eux echoue.
    public func verifier() throws(ErreurReseau) {
        guard cleReseau.count == 16 else { throw .cle("réseau") }
        guard cleApplication.count == 16 else { throw .cle("application") }
        guard (1...Self.capacite).contains(lampes.count) else { throw .nombreLampes(lampes.count) }
        var adresses = Set<UInt16>()
        var macs = Set<String>()
        for (i, l) in lampes.enumerated() {
            let n = i + 1
            guard (0x0001...0x7FFF).contains(l.adresse) else { throw .adresse(lampe: n, l.adresse) }
            guard !Self.plageDuPont.contains(l.adresse) else { throw .adresseDuPont(lampe: n, l.adresse) }
            guard adresses.insert(l.adresse).inserted else { throw .adresseEnDouble(l.adresse) }
            guard Self.macValide(l.mac) else { throw .mac(lampe: n) }
            guard macs.insert(l.mac.uppercased()).inserted else { throw .macEnDouble(l.mac.uppercased()) }
            if let raison = Self.fauteNom(l.nom) { throw .nom(lampe: n, raison) }
        }
    }

    static func macValide(_ mac: String) -> Bool {
        mac.wholeMatch(of: /[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}/) != nil
    }

    /// Ce qui empeche un nom de passer tel quel : vide, plus de 31 octets, un
    /// caractere de controle.
    static func fauteNom(_ nom: String) -> String? {
        if nom.isEmpty { return "nom vide" }
        if nom.utf8.count > nomMax { return "nom de \(nom.utf8.count) octets, \(nomMax) au plus" }
        if nom.unicodeScalars.contains(where: { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) }) {
            return "caractère de contrôle dans le nom"
        }
        return nil
    }

    /// Le nom en un seul argument de la console du pont (`esp_console_split_argv`) :
    /// entre guillemets, `"` et `\` echappes ; les espaces passent tels quels.
    static func argument(_ nom: String) -> String {
        "\"" + nom.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Les commandes du chargement (docs/PROTOCOLE-JSON.md 6.4) : `mesh cles`, `mesh
    /// lampes <N>`, puis une ligne par lampe, le code avant le nom. La premiere porte
    /// les cles : a soumettre en secret (Correlateur), jamais a afficher.
    public func commandes() -> [String] {
        func hex(_ d: Data) -> String { d.map { String(format: "%02X", $0) }.joined() }
        var c = ["mesh cles \(hex(cleReseau)) \(hex(cleApplication))", "mesh lampes \(lampes.count)"]
        for (i, l) in lampes.enumerated() {
            c.append("mesh lampe \(i + 1) 0x\(String(format: "%04X", l.adresse)) \(l.mac.uppercased()) \(l.code) "
                     + Self.argument(l.nom))
        }
        return c
    }

    /// Meme reseau et memes lampes (cles, puis adresse, MAC, nom et code de chaque lampe).
    public func memeContenu(que autre: ReseauMesh) -> Bool {
        cleReseau == autre.cleReseau && cleApplication == autre.cleApplication && lampes == autre.lampes
    }
}
