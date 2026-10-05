// Lecture de la base d'amaran Desktop (spec 3b, section 5), en lecture seule : le
// fichier est lu en memoire, puis ouvert par SQLite depuis cette copie
// (sqlite3_deserialize) : rien ne s'ecrit jamais pres de la base, ni ailleurs sur
// le disque. Memes controles qu'outils/cles_amaran.py.
import Foundation
import SQLite3

public enum ErreurBase: Error, Sendable, Equatable, CustomStringConvertible {
    case introuvable
    case illisible(String)
    case reseaux(Int)
    case cle
    case aucuneLampe
    case lampe(adresse: String)

    public var description: String {
        switch self {
        case .introuvable: "Aucune base d'amaran Desktop (*/amaran.db) dans ce dossier."
        case .illisible(let raison): "Base d'amaran Desktop illisible (\(raison))."
        case .reseaux(let n): "\(n) réseaux dans la base d'amaran Desktop, 1 attendu."
        case .cle: "Clé illisible dans la base d'amaran Desktop."
        case .aucuneLampe: "Aucune lampe dans la base d'amaran Desktop."
        case .lampe(let a): "Lampe illisible dans la base d'amaran Desktop (adresse \(a))."
        }
    }
}

public enum BaseAmaranDesktop {
    /// Dossier d'amaran Desktop sur ce Mac (app sandboxee) : a proposer dans le
    /// panneau d'ouverture. Depuis le vrai dossier personnel : dans une app
    /// sandboxee, homeDirectoryForCurrentUser est le conteneur de l'app.
    public static var dossierHabituel: URL {
        let maison = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: maison, isDirectory: true)
            .appending(path: "Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support/amaran Desktop")
    }

    /// La base la plus recente du dossier : `*/amaran.db` (un sous-dossier par compte).
    public static func trouver(dans dossier: URL) throws(ErreurBase) -> URL {
        let fm = FileManager.default
        let sous = (try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil)) ?? []
        let bases = sous.map { $0.appending(path: "amaran.db") }.filter { fm.fileExists(atPath: $0.path) }
        func date(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        guard let plusRecente = bases.max(by: { date($0) < date($1) }) else { throw .introuvable }
        return plusRecente
    }

    /// Lit le reseau de la base. Le fichier lu est efface de la memoire apres usage.
    public static func lire(_ fichier: URL, maintenant: Date = Date()) throws(ErreurBase) -> ReseauMesh {
        var octets: Data
        do {
            octets = try Data(contentsOf: fichier)
        } catch {
            throw .illisible(error.localizedDescription)
        }
        defer { octets.resetBytes(in: 0..<octets.count) }
        return try lire(octets: octets, maintenant: maintenant)
    }

    /// Lit le reseau d'une base deja en memoire (tests : base factice).
    public static func lire(octets: Data, maintenant: Date = Date()) throws(ErreurBase) -> ReseauMesh {
        guard !octets.isEmpty else { throw .illisible("fichier vide") }
        var db: OpaquePointer?
        guard sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            throw .illisible("sqlite3_open_v2")
        }
        // Copie geree ici : effacee, puis rendue, apres la fermeture.
        let taille = octets.count
        let tampon = UnsafeMutableRawPointer.allocate(byteCount: taille, alignment: 8)
        octets.copyBytes(to: tampon.assumingMemoryBound(to: UInt8.self), count: taille)
        defer {
            sqlite3_close(db)
            tampon.initializeMemory(as: UInt8.self, repeating: 0, count: taille)
            tampon.deallocate()
        }
        guard sqlite3_deserialize(db, "main", tampon.assumingMemoryBound(to: UInt8.self), Int64(taille),
                                  Int64(taille), UInt32(SQLITE_DESERIALIZE_READONLY)) == SQLITE_OK else {
            throw .illisible(String(cString: sqlite3_errmsg(db)))
        }
        return try lireReseau(db, maintenant: maintenant)
    }

    private static func lireReseau(_ db: OpaquePointer, maintenant: Date) throws(ErreurBase) -> ReseauMesh {
        let reseaux = try lignes(db, "select net_key, app_key from mesh where net_key is not null and app_key is not null")
        guard reseaux.count == 1 else { throw .reseaux(reseaux.count) }
        guard case .texte(let reseau)? = reseaux[0].first, case .texte(let application)? = reseaux[0].last,
              let cleReseau = Data(hex: reseau), let cleApplication = Data(hex: application) else { throw .cle }
        guard cleReseau.count == 16, cleApplication.count == 16 else { throw .cle }
        // `code` et `composition_data` : absentes d'une base plus ancienne, sans gravite.
        let colonnes = Set(try lignes(db, "pragma table_info(fixtures)").compactMap { l -> String? in
            if l.count > 1, case .texte(let nom) = l[1] { return nom }
            return nil
        })
        let extra = ["code", "composition_data"].map { colonnes.contains($0) ? $0 : "null" }.joined(separator: ", ")
        let fixtures = try lignes(db, "select node_address, mac_address, name, \(extra) from fixtures "
                                      + "where node_address is not null order by node_address")
        guard !fixtures.isEmpty else { throw .aucuneLampe }
        var lampes: [LampeReseau] = []
        for f in fixtures {
            guard f.count == 5, case .entier(let adresse) = f[0] else { throw .lampe(adresse: "?") }
            let a = String(adresse)
            guard (1...0x7FFF).contains(adresse) else { throw .lampe(adresse: a) }
            guard case .texte(let mac) = f[1], ReseauMesh.macValide(mac) else { throw .lampe(adresse: a) }
            guard case .texte(let nom) = f[2], !nom.isEmpty,
                  !nom.unicodeScalars.contains(where: { $0.value < 0x20 }) else { throw .lampe(adresse: a) }
            lampes.append(LampeReseau(adresse: UInt16(adresse), mac: mac.uppercased(), nom: nom,
                                      code: Self.code(f[3]), declarees: Self.capacitesDeclarees(f[4])))
        }
        return ReseauMesh(cleReseau: cleReseau, cleApplication: cleApplication, lampes: lampes,
                          source: .amaranDesktop, date: maintenant)
    }

    /// Code produit Sidus (colonne `code`, texte) ; 0 s'il manque ou n'est pas un nombre.
    static func code(_ v: Valeur) -> UInt32 {
        guard case .texte(let t) = v else { return 0 }
        let s = t.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.allSatisfy(\.isASCII), s.allSatisfy(\.isNumber) else { return 0 }
        return UInt32(s) ?? 0
    }

    // Modeles SIG serveurs qui disent une capacite dans la composition d'une lampe.
    static let modeleCTL: UInt16 = 0x1303  // Light CTL Server : temperature de couleur
    static let modeleHSL: UInt16 = 0x1307  // Light HSL Server : couleur

    /// Capacites au-dela de l'intensite que la lampe declare : `cct`, `couleur`.
    static func capacitesDeclarees(_ v: Valeur) -> [String] {
        guard case .texte(let t) = v else { return [] }
        let m = modelesSIG(Data(hex: t) ?? Data())
        return (m.contains(modeleCTL) ? ["cct"] : []) + (m.contains(modeleHSL) ? ["couleur"] : [])
    }

    /// Modeles SIG d'une composition (page 0) : numero de page, CID, PID, VID,
    /// CRPL, fonctions (2 octets chacun), puis chaque element : emplacement (2),
    /// nombre de modeles SIG (1) et vendeur (1), les modeles SIG (2 octets) et
    /// vendeur (4 octets). Vide si illisible.
    static func modelesSIG(_ d: Data) -> Set<UInt16> {
        let o = [UInt8](d)
        var modeles = Set<UInt16>()
        var i = 11
        while i + 4 <= o.count {
            let sig = Int(o[i + 2]), vendeur = Int(o[i + 3])
            i += 4
            guard i + 2 * sig + 4 * vendeur <= o.count else { return [] }
            for k in 0..<sig { modeles.insert(UInt16(o[i + 2 * k]) | UInt16(o[i + 2 * k + 1]) << 8) }
            i += 2 * sig + 4 * vendeur
        }
        return modeles
    }

    // MARK: - SQLite

    enum Valeur: Equatable {
        case entier(Int)
        case texte(String)
        case autre
    }

    private static func lignes(_ db: OpaquePointer, _ sql: String) throws(ErreurBase) -> [[Valeur]] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else {
            throw .illisible(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(st) }
        var resultat: [[Valeur]] = []
        while true {
            let r = sqlite3_step(st)
            if r == SQLITE_DONE { break }
            guard r == SQLITE_ROW else { throw .illisible(String(cString: sqlite3_errmsg(db))) }
            resultat.append((0..<sqlite3_column_count(st)).map { c -> Valeur in
                switch sqlite3_column_type(st, c) {
                case SQLITE_INTEGER: .entier(Int(sqlite3_column_int64(st, c)))
                case SQLITE_TEXT: .texte(String(cString: sqlite3_column_text(st, c)))
                default: .autre
                }
            })
        }
        return resultat
    }
}

extension Data {
    /// Exactement 2 chiffres hexa par octet (casse libre) ; nil sinon.
    public init?(hex: String) {
        let c = Array(hex.utf8)
        guard c.count % 2 == 0 else { return nil }
        var o = [UInt8]()
        o.reserveCapacity(c.count / 2)
        func v(_ x: UInt8) -> UInt8? {
            switch x {
            case 0x30...0x39: x - 0x30
            case 0x41...0x46: x - 0x37
            case 0x61...0x66: x - 0x57
            default: nil
            }
        }
        var i = 0
        while i < c.count {
            guard let h = v(c[i]), let l = v(c[i + 1]) else { return nil }
            o.append(h << 4 | l)
            i += 2
        }
        self.init(o)
    }
}
