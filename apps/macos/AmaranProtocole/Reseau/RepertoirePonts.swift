// Repris de Halo Compagnon (Reseau/RepertoirePonts.swift) : le numero de serie du pont
// amaran est `AMARAN-<MAC>` (docs/PROTOCOLE-JSON.md 5.1), son nom SRP vient du bloc `ip` (5.5).
import Foundation

/// Ponts deja vus par l'app, retenus par MAC : leur modele, tire du numero de serie
/// du pont (`hello` `identite` : `id.serie` = `AMARAN-<MAC>`, 5.1), et leur nom SRP
/// (bloc `ip`, 5.5). Sert a nommer un port USB avant la connexion (son numero de
/// serie USB est la MAC) et l'entree reseau du meme pont : "AMARAN · F0:F5:BD:0A:0B:0C".
/// Codable : le modele de l'app le garde dans les reglages (`cleReglages`).
public struct RepertoirePonts: Codable, Sendable, Equatable {
    public struct Entree: Codable, Sendable, Equatable {
        /// "AMARAN" : le numero de serie sans sa MAC.
        public var modele: String?
        /// Nom SRP, sans `.local`.
        public var srp: String?

        public init(modele: String? = nil, srp: String? = nil) {
            self.modele = modele
            self.srp = srp
        }
    }

    /// Cle des reglages (UserDefaults) ou le modele de l'app le range.
    public static let cleReglages = "repertoirePonts"

    /// Cle : MAC en 12 hexa majuscules.
    public private(set) var parMac: [String: Entree] = [:]

    public init() {}

    /// Relu depuis les reglages ; nil si les donnees sont illisibles.
    public init?(donnees: Data) {
        guard let r = try? JSONDecoder().decode(Self.self, from: donnees) else { return nil }
        self = r
    }

    /// Pour les reglages.
    public var donnees: Data? { try? JSONEncoder().encode(self) }

    /// MAC en 12 hexa majuscules, separateurs (":" ou "-") retires ; nil si le texte
    /// n'en est pas une.
    public static func mac(_ texte: String?) -> String? {
        guard let texte else { return nil }
        let h = texte.uppercased().filter { $0 != ":" && $0 != "-" }
        guard h.count == 12, h.allSatisfy(\.isHexDigit) else { return nil }
        return h
    }

    /// "F0:F5:BD:0A:0B:0C" pour "F0F5BD0A0B0C".
    public static func macLisible(_ mac: String) -> String {
        var s = ""
        for (i, c) in mac.enumerated() {
            if i > 0, i % 2 == 0 { s.append(":") }
            s.append(c)
        }
        return s
    }

    /// Modele du numero de serie "AMARAN-F0F5BD0A0B0C" : "AMARAN". nil si la serie ne
    /// finit pas par "-" et la MAC de ce pont.
    public static func modele(serie: String?, mac: String) -> String? {
        guard let serie, let tiret = serie.lastIndex(of: "-") else { return nil }
        let avant = String(serie[..<tiret])
        guard !avant.isEmpty, Self.mac(String(serie[serie.index(after: tiret)...])) == mac else { return nil }
        return avant
    }

    /// Note ce que le pont dit de lui (`hello` `identite`, bloc `ip`) ; vrai si le
    /// repertoire change. Un nom SRP n'appartient qu'a un pont : retire a celui qui
    /// l'avait (pont remplace, nouvelle mise en service).
    @discardableResult
    public mutating func noter(mac texte: String?, serie: String?, srp: String?) -> Bool {
        guard let mac = Self.mac(texte) else { return false }
        let avant = self
        var e = parMac[mac] ?? Entree()
        if let m = Self.modele(serie: serie, mac: mac) { e.modele = m }
        if let srp, !srp.isEmpty {
            for (autre, x) in parMac where autre != mac && x.srp == srp { parMac[autre]?.srp = nil }
            e.srp = srp
        }
        parMac[mac] = e
        return self != avant
    }

    /// Note ce que l'etat du pont en dit : MAC et serie du `hello` `identite`, nom
    /// SRP du bloc `ip`.
    @discardableResult
    public mutating func noter(_ etat: EtatPont) -> Bool {
        noter(mac: etat.mac, serie: etat.identite?.valeur.id?.serie, srp: etat.srp)
    }

    /// Oublie un pont (reglages "Oublier ce pont").
    public mutating func oublier(mac texte: String) {
        guard let mac = Self.mac(texte) else { return }
        parMac[mac] = nil
    }

    /// MAC du pont qui porte ce nom SRP.
    public func mac(pourSrp srp: String) -> String? {
        parMac.first { $0.value.srp == srp }?.key
    }

    /// Ponts joignables par le reseau (nom SRP connu), par MAC.
    public var pontsReseau: [(mac: String, srp: String)] {
        parMac.compactMap { m, e in e.srp.map { (m, $0) } }.sorted { $0.mac < $1.mac }
    }

    /// "AMARAN · F0:F5:BD:0A:0B:0C" ; modele encore inconnu (pont jamais connecte) :
    /// "ESP32 · F0:F5:BD:0A:0B:0C".
    public func titre(mac: String) -> String {
        "\(parMac[mac]?.modele ?? "ESP32") · \(Self.macLisible(mac))"
    }
}
