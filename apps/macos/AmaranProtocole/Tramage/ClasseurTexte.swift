// Repris de Halo Compagnon (commit e114cd5) : textes du pont amaran (docs/PROTOCOLE-JSON.md 2.4).
import Foundation

/// Classe d'une ligne de texte (hors RS), section 2.5.
public enum ClasseTexte: String, Sendable, Equatable, CaseIterable {
    /// `E (12345) tag: ...`
    case logIDF
    /// `[lampes] ...`, `[mesh] ...`, `[bouton] ...`, `!! ...`
    case annonce
    /// ROM : indice de redemarrage.
    case demarrage
    /// `amaran> ` : invite de la console en mode texte (ignoree).
    case invite
    /// Tout le reste : texte des commandes.
    case commande

    /// Filtre "logs systeme" de la console.
    public var estLogSysteme: Bool { self == .logIDF }
}

/// Ligne de texte classee.
public struct LigneTexte: Sendable, Equatable {
    /// Texte sans les sequences ANSI.
    public var texte: String
    public var classe: ClasseTexte
    /// Niveau d'un log (`E`, `W`, `I`, `D`, `V`).
    public var niveau: Character?

    public init(texte: String, classe: ClasseTexte, niveau: Character? = nil) {
        self.texte = texte
        self.classe = classe
        self.niveau = niveau
    }
}

public enum ClasseurTexte {
    private static let niveaux: Set<Character> = ["E", "W", "I", "D", "V"]

    public static func classer(_ brut: String) -> LigneTexte {
        let texte = sansANSI(brut)
        if let niv = niveauLogIDF(texte) { return LigneTexte(texte: texte, classe: .logIDF, niveau: niv) }
        if ["[lampes] ", "[mesh] ", "[bouton] ", "!! "].contains(where: texte.hasPrefix) {
            return LigneTexte(texte: texte, classe: .annonce)
        }
        if estDemarrage(texte) { return LigneTexte(texte: texte, classe: .demarrage) }
        if texte.trimmingCharacters(in: .whitespaces) == "amaran>" {
            return LigneTexte(texte: texte, classe: .invite)
        }
        return LigneTexte(texte: texte, classe: .commande)
    }

    /// Retire les sequences `ESC [ ... lettre`.
    public static func sansANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        var sortie = String.UnicodeScalarView()
        var it = s.unicodeScalars.makeIterator()
        while let c = it.next() {
            if c == "\u{1B}" {
                guard let suivant = it.next() else { break }
                if suivant == "[" {
                    while let x = it.next() {
                        if (x.value >= 0x41 && x.value <= 0x5A) || (x.value >= 0x61 && x.value <= 0x7A) { break }
                    }
                }
                continue
            }
            sortie.append(c)
        }
        return String(sortie)
    }

    /// `^[EWIDV] \(\d+\) [^:]+: `
    static func niveauLogIDF(_ s: String) -> Character? {
        let c = Array(s)
        guard c.count >= 8, niveaux.contains(c[0]), c[1] == " ", c[2] == "(" else { return nil }
        var i = 3
        var chiffres = 0
        while i < c.count, c[i].isASCII, c[i].isNumber { i += 1; chiffres += 1 }
        guard chiffres > 0, i + 1 < c.count, c[i] == ")", c[i + 1] == " " else { return nil }
        i += 2
        var tag = 0
        while i < c.count, c[i] != ":" { i += 1; tag += 1 }
        guard tag > 0, i + 1 < c.count, c[i] == ":", c[i + 1] == " " else { return nil }
        return c[0]
    }

    static func estDemarrage(_ s: String) -> Bool {
        s.hasPrefix("ESP-ROM:") || s.hasPrefix("rst:0x") || s.hasPrefix("boot:0x")
    }

    /// Firmware sans mode JSON (3.2) : sa console (la REPL d'ESP-IDF) lit `id=1`
    /// comme le nom d'une commande. Le firmware du plan 3b ne l'ecrit jamais.
    public static func estRefusIdAncienFirmware(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespaces) == "Unrecognized command"
    }
}
