// Messages de session du pont amaran (docs/PROTOCOLE-JSON.md 5.1, 5.6, 6.3), sur le
// modele de ceux de Halo Compagnon (commit e114cd5). Tout champ est facultatif,
// sauf ceux sans lesquels le message ne sert a rien (section 8).
import Foundation

// MARK: - hello (5.1)

/// `hello`, bloc `base`.
public struct HelloBase: Codable, Sendable, Equatable {
    public struct ReglagesSession: Codable, Sendable, Equatable {
        /// `usb` ou `udp` (rev 1).
        public var transport: TransportSession?
        public var periodeMs: Int?
        public var lampesMs: Int?
        public var compteursMs: Int?
        public var reseauMs: Int?
        public var bailS: Int?
        public var log: Bool?
        /// Messages `trame` demandes (`json trames 1`, rev 1).
        public var trames: Bool?

        public init(transport: TransportSession? = nil, periodeMs: Int? = nil, lampesMs: Int? = nil,
                    compteursMs: Int? = nil, reseauMs: Int? = nil, bailS: Int? = nil, log: Bool? = nil,
                    trames: Bool? = nil) {
            self.transport = transport
            self.periodeMs = periodeMs
            self.lampesMs = lampesMs
            self.compteursMs = compteursMs
            self.reseauMs = reseauMs
            self.bailS = bailS
            self.log = log
            self.trames = trames
        }
    }

    public struct Limites: Codable, Sendable, Equatable {
        public var ligneMax: Int?
        public var cmdMax: Int?
    }

    public var rev: Int?
    public var fw: String?
    public var date: String?
    public var heure: String?
    public var idf: String?
    public var puce: String?
    public var boot: String?
    public var reset: String?
    public var resetN: Int?
    public var upS: Int?
    public var session: ReglagesSession?
    public var limites: Limites?
}

/// `hello`, bloc `identite`.
public struct HelloIdentite: Codable, Sendable, Equatable {
    public struct Identite: Codable, Sendable, Equatable {
        public var fabricant: String?
        public var produit: String?
        public var serie: String?
        public var nom: String?
    }

    public var boot: String?
    public var mac: String?
    public var id: Identite?
    public var caps: [String]?
}

// MARK: - hb, fin (5.6)

public struct Battement: Codable, Sendable, Equatable {
    public var boot: String?
    public var upS: Int?
    public var jsonPerdus: Int?
    /// Id de la commande de la console en cours (6.2).
    public var commande: Int?
}

public struct FinSession: Codable, Sendable, Equatable {
    public var cause: CauseFin?
}

// MARK: - reponse (6.3)

public struct Reponse: Codable, Sendable, Equatable {
    public var id: Int
    public var etape: EtapeReponse
    public var cmd: String?
    public var ok: Bool
    public var code: CodeReponse
    public var msg: String?
    public var dureeMs: Int?
    public var suite: SuiteReponse?
    /// Ordre de lampe : son numero (1 a 16).
    public var lampe: Int?
    public var bailS: Int?
    public var upS: Int?
    /// `json cle nouvelle` : la cle, rendue une seule fois (jamais gardee, voir `sansCle`).
    public var cle: String?
    /// `json cle nouvelle` : empreinte de la cle (8 premiers hexa majuscules de son SHA-256).
    public var empreinte: String?

    public init(id: Int, etape: EtapeReponse, cmd: String? = nil, ok: Bool, code: CodeReponse, msg: String? = nil,
                dureeMs: Int? = nil, suite: SuiteReponse? = nil, lampe: Int? = nil, bailS: Int? = nil, upS: Int? = nil,
                cle: String? = nil, empreinte: String? = nil) {
        self.id = id
        self.etape = etape
        self.cmd = cmd
        self.ok = ok
        self.code = code
        self.msg = msg
        self.dureeMs = dureeMs
        self.suite = suite
        self.lampe = lampe
        self.bailS = bailS
        self.upS = upS
        self.cle = cle
        self.empreinte = empreinte
    }

    /// La meme reponse, sans la cle : aucun historique (suivis de commandes, journal des
    /// trames) ne doit jamais la garder, seule l'empreinte y a sa place.
    public var sansCle: Reponse {
        var r = self
        r.cle = nil
        return r
    }
}
