// Evenements du pont amaran (docs/PROTOCOLE-JSON.md, section 7) : des indices ;
// la verite est dans l'etat periodique.
import Foundation

/// `ordre` (7.1) : fin d'un ordre de lampe.
public struct EvenementOrdre: Codable, Sendable, Equatable {
    public var lampe: Int
    public var issue: IssueOrdre?
    public var delaiMs: Int?
    public var essai: Int?
    /// Id des ordres de l'app couverts (vide : ordre de Maison ou de la console sans id).
    public var ids: [Int]?
    public var idsPerdus: Int?
}

/// `alerte` (7.2) : relectures manquees d'une lampe, ou Bluetooth Mesh inoperant.
public struct Alerte: Codable, Sendable, Equatable {
    public var quoi: QuoiAlerte?
    public var lampe: Int?
    public var manque: Bool?
    public var part: Int?
    public var diag: DiagMesh?
}

/// `lampe` (7.3) : place d'une lampe dans Maison.
public struct EvenementLampe: Codable, Sendable, Equatable {
    public var lampe: Int
    public var quoi: QuoiLampe?
    public var endpoint: Int?
}

/// `led` (7.4).
public struct ChangementLed: Codable, Sendable, Equatable {
    public var motif: MotifLed?
    public var avant: MotifLed?
    public var test: Bool?
    public var depuisMs: Int?
}

/// `log` (7.5).
public struct MessageLog: Codable, Sendable, Equatable {
    public var src: String?
    public var niv: NiveauLog?
    public var txt: String?
    public var sautes: Int?
}
