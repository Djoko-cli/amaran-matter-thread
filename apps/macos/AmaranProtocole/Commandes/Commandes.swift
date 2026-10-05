// Repris de Halo Compagnon (commit e114cd5) : regles et commandes du pont amaran.
import Foundation

/// Genre de transport. Thread (UDP) viendra au plan 3b-2.
public enum GenreTransport: String, Sendable, Equatable {
    case usb
    /// Pont simule (mode demo) : se comporte comme l'USB.
    case demo
}

/// Erreur de construction d'une ligne vers le pont (section 2.5).
public enum ErreurLigne: Error, Sendable, Equatable, CustomStringConvertible {
    case vide
    case tropLongue(octets: Int, max: Int)
    case caractereInterdit
    case prefixeId
    case json

    public var description: String {
        switch self {
        case .vide: "Ligne vide."
        case .tropLongue(let o, let m): "Ligne trop longue : \(o) octets, \(m) au plus avec le préfixe id=."
        case .caractereInterdit: "Aucun caractère de contrôle n'est permis."
        case .prefixeId: "L'app ajoute elle-même le préfixe id=<n>."
        case .json: "Jamais de JSON ni d'octet RS vers le pont."
        }
    }
}

/// Lignes app -> pont : texte de la console prefixe par `id=<n> ` (6.1).
public enum LigneCommande {
    /// 127 octets au plus, prefixe compris (2.5).
    public static let octetsMax = 127
    public static let idMax = 999_999_999

    /// Octets envoyes a l'ouverture : Ctrl-U puis LF (3.2).
    public static let effacement = Data([Octets.ctrlU, Octets.lf])

    /// Normalise une commande (espaces de bord) et verifie les regles de 2.5 : les
    /// noms des lampes peuvent porter des accents (UTF-8), jamais un caractere de controle.
    public static func valider(_ commande: String, id: Int?) -> Result<String, ErreurLigne> {
        let c = commande.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return .failure(.vide) }
        guard c.unicodeScalars.allSatisfy({ $0.value >= 0x20 && !(0x7F...0x9F).contains($0.value) }) else {
            return .failure(c.unicodeScalars.contains { $0.value == 0x1E } ? .json : .caractereInterdit)
        }
        if c.hasPrefix("{") { return .failure(.json) }
        if c.lowercased().hasPrefix("id=") { return .failure(.prefixeId) }
        let ligne = id.map { "id=\($0) \(c)" } ?? c
        guard ligne.utf8.count <= octetsMax else {
            return .failure(.tropLongue(octets: ligne.utf8.count, max: octetsMax))
        }
        return .success(ligne)
    }

    /// Ligne complete, terminee par LF.
    public static func octets(_ commande: String, id: Int?) -> Result<Data, ErreurLigne> {
        valider(commande, id: id).map { Data(($0 + "\n").utf8) }
    }

    /// Numero suivant : 1..999999999, repart a 1.
    public static func suivant(_ id: Int) -> Int {
        id >= idMax ? 1 : id + 1
    }

    /// Mots d'une commande (separes par des espaces), en minuscules. Les guillemets
    /// sont retires comme le fait la console du pont : `"redemarre"` est `redemarre`.
    public static func mots(_ commande: String) -> [String] {
        commande.lowercased().replacingOccurrences(of: "\"", with: "").split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }
}

/// Ce que la console fait d'une ligne tapee (6.4).
public enum VerdictConsole: Sendable, Equatable {
    case autorisee
    /// Demander confirmation avant d'envoyer.
    case confirmation(String)
    case interdite(String)
}

public enum PolitiqueCommandes {
    /// Commandes qui demandent confirmation (6.4).
    public static func verdictConsole(_ commande: String) -> VerdictConsole {
        let m = LigneCommande.mots(commande)
        guard let premier = m.first else { return .interdite(ErreurLigne.vide.description) }
        // Longueur jugee avec le plus long id possible : la ligne partira quel que soit son numero.
        if case .failure(let e) = LigneCommande.valider(commande, id: LigneCommande.idMax) {
            return .interdite(e.description)
        }
        if m == ["json", "0"] {
            return .interdite("Utiliser « Libérer le port » : l'app enverra json 0 et fermera le port.")
        }
        switch premier {
        case "redemarre":
            return .confirmation("Redémarre le pont (le port USB va se ré-énumérer).")
        case "decommission":
            return .confirmation("Retire le pont de Maison et de tout autre contrôleur Matter (clés et lampes gardées).")
        default:
            break
        }
        if premier == "mesh", m.count >= 2 {
            switch m[1] {
            case "cles":
                return .confirmation("Remplace les clés du réseau des lampes dans le pont (effet au redémarrage). « Charger le pont » vérifie en plus les empreintes.")
            case "oublie":
                return .confirmation("Efface les clés du réseau des lampes dans le pont.")
            case "adresse":
                return .confirmation("Change l'adresse Bluetooth Mesh du pont.")
            case "iv":
                return .confirmation(m.count >= 3 && m[2] == "cherche"
                    ? "Cherche l'IV Index : la console du pont reste occupée pendant la recherche."
                    : "Change l'IV Index du réseau des lampes.")
            case "lampes":
                return .confirmation("Ouvre une nouvelle liste de lampes (effet au redémarrage, une fois complète).")
            case "lampe" where m.count == 4 && m[3] == "masquer":
                return .confirmation("Retire la lampe de Maison : remise, elle y reviendra comme un nouvel accessoire, sans son nom, ses scènes ni ses automatisations.")
            default:
                break
            }
        }
        return .autorisee
    }

    /// Apres ces commandes, l'app attend la re-enumeration de l'USB (3.1).
    public static func attendReenumeration(_ commande: String) -> Bool {
        let m = LigneCommande.mots(commande)
        return m.first == "redemarre" || m.first == "decommission"
    }

    /// Masque les cles d'une ligne affichee : la commande `mesh cles <reseau>
    /// <application>` (casse, espaces et guillemets quelconques, comme la console les lit), et
    /// toute suite de 32 chiffres hexa ou plus (une cle tapee ailleurs).
    public static func masquerCle(_ texte: String) -> String {
        guard texte.utf8.count >= 32 || texte.range(of: "cles", options: .caseInsensitive) != nil else { return texte }
        var s = texte
        s.replace(/(?i)("?mesh"?[ \t]+"?cles"?)([ \t]+"?[0-9a-f]+"?)+/) { m in m.output.1 + " " + masque + " " + masque }
        s.replace(/[0-9A-Fa-f]{32,}/) { _ in masque }
        return s
    }

    private static let masque = String(repeating: "•", count: 8)
}
