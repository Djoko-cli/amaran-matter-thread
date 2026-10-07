// Tests des cles (spec 3b, section 5) : empreintes, pre-controles, commandes du
// chargement, lecture d'une base d'amaran Desktop factice, sauvegarde chiffree,
// controles du chargement. Aucune vraie cle : des octets inventes.
import Foundation
import SQLite3
import Testing
@testable import AmaranProtocole

enum Factice {
    static let cleReseau = Data((0..<16).map { UInt8($0) })
    static let cleApplication = Data((16..<32).map { UInt8($0) })

    static func reseau(_ lampes: [LampeReseau]? = nil) -> ReseauMesh {
        ReseauMesh(cleReseau: cleReseau, cleApplication: cleApplication,
                   lampes: lampes ?? [
                       LampeReseau(adresse: 0x0002, mac: "02:00:00:00:00:01", nom: "Lampe bureau", code: 40065),
                       LampeReseau(adresse: 0x0004, mac: "02:00:00:00:00:02", nom: "Lumière fenêtre", code: 40065),
                   ],
                   source: .amaranDesktop, date: Date(timeIntervalSinceReferenceDate: 800_000_000))
    }

    /// Base d'amaran Desktop factice, en memoire puis serialisee : les tables et
    /// colonnes que lit outils/cles_amaran.py.
    static func base(_ sql: [String]) throws -> Data {
        var db: OpaquePointer?
        let ouverte = sqlite3_open(":memory:", &db)
        try #require(ouverte == SQLITE_OK)
        defer { sqlite3_close(db) }
        for s in sql {
            let r = sqlite3_exec(db, s, nil, nil, nil)
            try #require(r == SQLITE_OK, "\(s)")
        }
        var taille: sqlite3_int64 = 0
        let serialisee = sqlite3_serialize(db, "main", &taille, 0)
        let p = try #require(serialisee)
        defer { sqlite3_free(p) }
        return Data(bytes: p, count: Int(taille))
    }

    static let tables = [
        "create table mesh (net_key text, app_key text)",
        "create table fixtures (node_address integer, mac_address text, name text, code text, composition_data text)",
    ]
    /// Base de la mise a jour de la fiche des lampes : les versions du logiciel de commande et du module Bluetooth.
    static let tablesVersions = [
        "create table mesh (net_key text, app_key text)",
        "create table fixtures (node_address integer, mac_address text, name text, code text, composition_data text, "
            + "control_software_version text, ble_software_version text)",
    ]
    static let cles = "insert into mesh values ('000102030405060708090A0B0C0D0E0F', '101112131415161718191a1b1c1d1e1f')"
}

@Suite("Cles du reseau", .langue(.francais))
struct ClesTests {
    @Test func empreinte() {
        #expect(Empreinte.de(Data(count: 16)) == "374708FF")
        #expect(Factice.reseau().empreinteReseau == "BE45CB26")
    }

    @Test func preControles() throws {
        try Factice.reseau().verifier()
        func faute(_ lampes: [LampeReseau]) -> ErreurReseau? {
            do { try Factice.reseau(lampes).verifier() } catch { return error }
            return nil
        }
        let ok = LampeReseau(adresse: 2, mac: "02:00:00:00:00:01", nom: "A", code: 0)
        #expect(faute([]) == .nombreLampes(0))
        #expect(faute(Array(repeating: ok, count: 17)) == .nombreLampes(17))
        #expect(faute([LampeReseau(adresse: 0x7F38, mac: ok.mac, nom: "A", code: 0)]) == .adresseDuPont(lampe: 1, 0x7F38))
        #expect(faute([LampeReseau(adresse: 0, mac: ok.mac, nom: "A", code: 0)]) == .adresse(lampe: 1, 0))
        #expect(faute([ok, LampeReseau(adresse: 2, mac: "02:00:00:00:00:02", nom: "B", code: 0)]) == .adresseEnDouble(2))
        #expect(faute([ok, LampeReseau(adresse: 4, mac: "02:00:00:00:00:01", nom: "B", code: 0)])
                == .macEnDouble("02:00:00:00:00:01"))
        #expect(faute([LampeReseau(adresse: 2, mac: "02-00-00-00-00-01", nom: "A", code: 0)]) == .mac(lampe: 1))
        #expect(faute([LampeReseau(adresse: 2, mac: ok.mac, nom: "", code: 0)]) == .nom(lampe: 1, "nom vide"))
        #expect(faute([LampeReseau(adresse: 2, mac: ok.mac, nom: String(repeating: "é", count: 16), code: 0)])
                == .nom(lampe: 1, "nom de 32 octets, 31 au plus"))
        #expect(faute([LampeReseau(adresse: 2, mac: ok.mac, nom: "a\tb", code: 0)])
                == .nom(lampe: 1, "caractère de contrôle dans le nom"))
        var cle = Factice.reseau()
        cle.cleApplication = Data(count: 15)
        #expect(throws: ErreurReseau.cle("application")) { try cle.verifier() }
    }

    @Test func commandesDuChargement() {
        let c = Factice.reseau().commandes()
        #expect(c == [
            "mesh cles 000102030405060708090A0B0C0D0E0F 101112131415161718191A1B1C1D1E1F",
            "mesh lampes 2",
            "mesh lampe 1 0x0002 02:00:00:00:00:01 40065 \"Lampe bureau\"",
            "mesh lampe 2 0x0004 02:00:00:00:00:02 40065 \"Lumière fenêtre\"",
        ])
        // Guillemets et barres echappes : un seul argument pour esp_console_split_argv.
        #expect(ReseauMesh.argument(#"La "bonne" \ lampe"#) == #""La \"bonne\" \\ lampe""#)
    }

    /// Le jeton de version, avant le nom : `v<logiciel>/<ble>`, `v<logiciel>` si le module Bluetooth
    /// est inconnu, rien si le logiciel est inconnu (meme si le module est connu).
    @Test func commandesAvecLesVersions() throws {
        let r = Factice.reseau([
            LampeReseau(adresse: 0x0002, mac: "02:00:00:00:00:01", nom: "Lampe bureau", code: 40065, logiciel: "1.4", ble: "1.69"),
            LampeReseau(adresse: 0x0004, mac: "02:00:00:00:00:02", nom: "Lumière fenêtre", code: 40065, logiciel: "1.4"),
            LampeReseau(adresse: 0x0006, mac: "02:00:00:00:00:03", nom: "Lampe du fond", code: 40065, ble: "1.69"),
            LampeReseau(adresse: 0x0008, mac: "02:00:00:00:00:04", nom: "Sans version", code: 40065),
        ])
        try r.verifier()
        #expect(r.commandes().dropFirst(2) == [
            "mesh lampe 1 0x0002 02:00:00:00:00:01 40065 v1.4/1.69 \"Lampe bureau\"",
            "mesh lampe 2 0x0004 02:00:00:00:00:02 40065 v1.4 \"Lumière fenêtre\"",
            "mesh lampe 3 0x0006 02:00:00:00:00:03 40065 \"Lampe du fond\"",
            "mesh lampe 4 0x0008 02:00:00:00:00:04 40065 \"Sans version\"",
        ])
    }

    /// Une version mal formee ne part jamais au pont ; une ligne qui deviendrait trop longue avec le
    /// jeton est refusee avant tout envoi (sinon le pont garderait les nouvelles cles et l'ancienne liste).
    @Test func preControlesDesVersions() throws {
        func faute(_ l: LampeReseau) -> ErreurReseau? {
            do { try Factice.reseau([l]).verifier() } catch { return error }
            return nil
        }
        let ok = LampeReseau(adresse: 0x7EFF, mac: "02:00:00:00:00:01", nom: "A", code: .max)
        func avec(logiciel: String? = nil, ble: String? = nil, nom: String = "A") -> LampeReseau {
            var l = ok
            l.logiciel = logiciel
            l.ble = ble
            l.nom = nom
            return l
        }
        #expect(faute(avec(logiciel: "123.456", ble: "0.0")) == nil)
        #expect(faute(avec(logiciel: "1.2.3")) == .version(lampe: 1, "1.2.3"))
        #expect(faute(avec(logiciel: "1.4", ble: "v1.69")) == .version(lampe: 1, "v1.69"))
        #expect(faute(avec(logiciel: "1234.5")) == .version(lampe: 1, "1234.5"))
        #expect(faute(avec(ble: "")) == .version(lampe: 1, ""))
        #expect(ErreurReseau.version(lampe: 1, "1.2.3").description == "Lampe 1 : version « 1.2.3 » illisible (forme 1.4 attendue).")
        // Le plus long code et le pire nom (31 guillemets) tiennent pile sans jeton (cf. lignesDansLaLimite) ;
        // avec le jeton, la ligne depasse 127 octets : refusee avant tout envoi.
        let pire = String(repeating: "\"", count: 31)
        #expect(faute(avec(nom: pire)) == nil)
        guard case .ligneTropLongue(let lampe, let octets)? = faute(avec(logiciel: "1.4", ble: "1.69", nom: pire)) else {
            Issue.record("ligne trop longue attendue")
            return
        }
        #expect(lampe == 1 && octets == 136, "\(octets) octets")
        #expect(faute(avec(logiciel: "1.4", ble: "1.69", nom: "Lampe bureau")) == nil)
    }

    /// Le pire nom (31 guillemets, echappes en 62 octets) tient encore dans une ligne
    /// de 127 octets, avec le plus long id et le plus long code.
    @Test func lignesDansLaLimite() throws {
        let pire = (0..<16).map { i in
            LampeReseau(adresse: 0x7EFF - UInt16(i), mac: String(format: "02:00:00:00:00:%02X", i),
                        nom: String(repeating: "\"", count: 31), code: .max)
        }
        let r = Factice.reseau(pire)
        try r.verifier()
        for c in r.commandes() {
            let ligne = try LigneCommande.valider(c, id: LigneCommande.idMax).get()
            #expect(ligne.utf8.count <= 127, "\(ligne.utf8.count) octets")
        }
    }

    @Test func masquage() {
        let c = Factice.reseau().commandes()[0]
        #expect(PolitiqueCommandes.masquerCle(c) == "mesh cles •••••••• ••••••••")
        // Apres `mesh cles`, tout ce qui suit est masque, un masque par mot (ici la cle et « x »).
        #expect(PolitiqueCommandes.masquerCle("id=7 MESH  Cles 00112233445566778899aabbccddeeff x")
                == "id=7 MESH  Cles •••••••• ••••••••")
        #expect(PolitiqueCommandes.masquerCle("ok cles 1A2B3C4D 5E6F7A8B (redemarrer)") == "ok cles 1A2B3C4D 5E6F7A8B (redemarrer)",
                "les empreintes restent visibles")
        #expect(PolitiqueCommandes.verdictConsole(c)
                == .confirmation("Remplace les clés du réseau des lampes dans le pont (effet au redémarrage). « Charger le pont » vérifie en plus les empreintes."))
    }

    /// Un guillemet fermant coupe le mot, comme dans esp_console_split_argv.
    @Test func guillemetsColles() {
        #expect(LigneCommande.mots("\"mesh\"cles a b") == ["mesh", "cles", "a", "b"])
        if case .interdite(_) = PolitiqueCommandes.verdictConsole("\"json\"\"0\"") {} else {
            Issue.record("json 0 entre guillemets colles : doit rester interdit")
        }
    }

    /// Le pont retire les guillemets (`esp_console_split_argv`) : les masquer ou les
    /// confirmer de meme, sinon `"mesh" "cles" ...` passerait sans masque ni confirmation.
    @Test func guillemetsNeContournentNiMasqueNiConfirmation() {
        let k1 = "00112233445566778899aabbccddeeff"
        let k2 = "ffeeddccbbaa99887766554433221100"
        let confirmeCles = PolitiqueCommandes.verdictConsole("mesh cles \(k1) \(k2)")
        for ligne in ["\"mesh\" \"cles\" \(k1) \(k2)", "mesh \"cles\" \"\(k1)\" \"\(k2)\"", "\"mesh\" cles \(k1) \(k2)"] {
            let m = PolitiqueCommandes.masquerCle(ligne)
            #expect(!m.contains(k1) && !m.contains(k2) && !m.contains("0011") && !m.contains("ffee"), "\(m)")
            #expect(m.hasSuffix("•••••••• ••••••••"), "\(m)")
            #expect(PolitiqueCommandes.verdictConsole(ligne) == confirmeCles)
        }
        // Ligne affichee avec son id (jamais tapee ainsi) : masquee aussi.
        #expect(PolitiqueCommandes.masquerCle("id=3 \"MESH\"  \"Cles\" \(k1) \(k2)") == "id=3 \"MESH\"  \"Cles\" •••••••• ••••••••")
        #expect(PolitiqueCommandes.verdictConsole("\"redemarre\"")
                == .confirmation("Redémarre le pont (le port USB va se ré-énumérer)."))
        #expect(PolitiqueCommandes.verdictConsole("\"mesh\" \"oublie\"")
                == PolitiqueCommandes.verdictConsole("mesh oublie"))
        #expect(PolitiqueCommandes.verdictConsole("\"json\" \"0\"")
                == PolitiqueCommandes.verdictConsole("json 0"))
        #expect(PolitiqueCommandes.attendReenumeration("\"decommission\""))
    }
}

@Suite("Base d'amaran Desktop", .langue(.francais))
struct BaseAmaranDesktopTests {
    static let lampes = [
        // Composition (page 0) : en-tete de 11 octets, puis un element : OnOff et Lightness...
        "insert into fixtures values (2, '02:00:00:00:00:01', 'Lampe bureau', '40065', '0000000000000000000000' || '00000200' || '00100013')",
        // ... et, pour la seconde, Lightness, Light CTL et Light HSL.
        "insert into fixtures values (4, '02:00:00:00:00:02', 'Lumière fenêtre', ' 40065 ', '0000000000000000000000' || '00000300' || '001303130713')",
        "insert into fixtures values (null, '02:00:00:00:00:03', 'jamais provisionnee', null, null)",
    ]

    @Test func lecture() throws {
        let base = try Factice.base(Factice.tables + [Factice.cles] + Self.lampes)
        let r = try BaseAmaranDesktop.lire(octets: base, maintenant: Date(timeIntervalSinceReferenceDate: 1))
        #expect(r.cleReseau == Factice.cleReseau)
        #expect(r.cleApplication == Factice.cleApplication)
        #expect(r.lampes.map(\.adresse) == [2, 4], "les fixtures sans adresse sont ignorees")
        #expect(r.lampes[1].nom == "Lumière fenêtre")
        #expect(r.lampes.map(\.code) == [40065, 40065], "code en texte, espaces tolerees")
        #expect(r.lampes[0].declarees.isEmpty)
        #expect(r.lampes[1].declarees == ["cct", "couleur"], "Light CTL et Light HSL dans la composition")
        #expect(r.source == .amaranDesktop)
    }

    @Test func baseAncienneSansCodeNiComposition() throws {
        let base = try Factice.base([
            "create table mesh (net_key text, app_key text)",
            "create table fixtures (node_address integer, mac_address text, name text)",
            Factice.cles,
            "insert into fixtures values (2, '02:00:00:00:00:01', 'Lampe bureau')",
        ])
        let r = try BaseAmaranDesktop.lire(octets: base)
        #expect(r.lampes.first?.code == 0)
        #expect(r.lampes.first?.logiciel == nil && r.lampes.first?.ble == nil, "versions inconnues, sans gravite")
    }

    /// Les versions (colonnes `control_software_version`, `ble_software_version`) : lues telles
    /// quelles si elles ont la forme 1 a 3 chiffres, un point, 1 a 3 chiffres ; sinon inconnues.
    @Test func versions() throws {
        func ligne(_ n: Int, _ logiciel: String, _ ble: String) -> String {
            "insert into fixtures values (\(n), '02:00:00:00:00:\(String(format: "%02d", n))', 'L\(n)', '40065', null, \(logiciel), \(ble))"
        }
        let base = try Factice.base(Factice.tablesVersions + [Factice.cles,
            ligne(1, "'1.4'", "'1.69'"),
            ligne(2, "'123.456'", "'0.0'"),
            ligne(3, "'1.4'", "null"),
            ligne(4, "null", "'1.69'"),
            ligne(5, "'1.2.3'", "'v1.69'"),
            ligne(6, "'1234.5'", "'1.'"),
            ligne(7, "''", "' 1.69'"),
            ligne(8, "'1.4\n'", "'１.６９'"),
            ligne(9, "14", "1.69"),  // nombres : l'affinite TEXT de la colonne les rend en texte ('14', '1.69')
            ligne(10, "X'312E34'", "'1.69 '"),
        ])
        let r = try BaseAmaranDesktop.lire(octets: base)
        #expect(r.lampes.map(\.logiciel) == ["1.4", "123.456", "1.4", nil, nil, nil, nil, nil, nil, nil])
        #expect(r.lampes.map(\.ble) == ["1.69", "0.0", nil, "1.69", nil, nil, nil, nil, "1.69", nil])
        #expect(r.lampes[0].jetonVersion == "v1.4/1.69")
        #expect(r.lampes[3].jetonVersion == nil, "module Bluetooth seul : rien n'est envoye")
    }

    /// Une base avec une seule des deux colonnes : celle-la est lue, l'autre est inconnue.
    @Test func uneSeuleColonneDeVersion() throws {
        let base = try Factice.base([
            "create table mesh (net_key text, app_key text)",
            "create table fixtures (node_address integer, mac_address text, name text, code text, composition_data text, control_software_version text)",
            Factice.cles,
            "insert into fixtures values (2, '02:00:00:00:00:01', 'Lampe bureau', '40065', null, '1.4')",
        ])
        let l = try #require(try BaseAmaranDesktop.lire(octets: base).lampes.first)
        #expect(l.logiciel == "1.4" && l.ble == nil)
    }

    @Test func refus() throws {
        func erreur(_ sql: [String]) throws -> ErreurBase? {
            let base = try Factice.base(Factice.tables + sql)
            do { _ = try BaseAmaranDesktop.lire(octets: base) } catch { return error }
            return nil
        }
        #expect(try erreur([]) == .reseaux(0))
        #expect(try erreur([Factice.cles, Factice.cles]) == .reseaux(2))
        #expect(try erreur(["insert into mesh values ('0011', '2233')"]) == .cle)
        #expect(try erreur(["insert into mesh values ('zz0102030405060708090A0B0C0D0E0F', '101112131415161718191A1B1C1D1E1F')"]) == .cle)
        #expect(try erreur([Factice.cles]) == .aucuneLampe)
        // Une valeur qui n'est pas du texte (spec 3b, section 5) : un nom en BLOB, que
        // l'affinite TEXT de la colonne ne convertit pas.
        #expect(try erreur([Factice.cles, "insert into fixtures values (2, '02:00:00:00:00:01', X'41', null, null)"])
                == .lampe(adresse: "2"))
        #expect(try erreur([Factice.cles, "insert into fixtures values (2, 'pas une mac', 'A', null, null)"])
                == .lampe(adresse: "2"))
        #expect(try erreur([Factice.cles, "insert into fixtures values ('deux', '02:00:00:00:00:01', 'A', null, null)"])
                == .lampe(adresse: "?"))
        #expect(throws: ErreurBase.illisible("fichier vide")) { try BaseAmaranDesktop.lire(octets: Data()) }
    }

    @Test func dossierSansBase() {
        let vide = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(throws: ErreurBase.introuvable) { try BaseAmaranDesktop.trouver(dans: vide) }
    }
}

@Suite("Sauvegarde chiffree", .langue(.francais))
struct SauvegardeTests {
    static let phrase = "une phrase de passe assez longue"

    @Test func allerRetour() throws {
        let f = try Sauvegarde.chiffrer(Factice.reseau(), phrase: Self.phrase, tours: 1000)
        #expect(f.prefix(8) == Data("AMARANSV".utf8))
        #expect(f.range(of: Factice.cleReseau) == nil, "la cle n'apparait pas en clair")
        let r = try Sauvegarde.dechiffrer(f, phrase: Self.phrase)
        #expect(r == Factice.reseau())
    }

    /// Les versions passent dans la sauvegarde ; une sauvegarde sans ces champs (faite avant la fiche
    /// des lampes) se relit avec des versions inconnues.
    @Test func versionsEtAncienneSauvegarde() throws {
        var r = Factice.reseau()
        r.lampes[0].logiciel = "1.4"
        r.lampes[0].ble = "1.69"
        let f = try Sauvegarde.chiffrer(r, phrase: Self.phrase, tours: 1000)
        let lu = try Sauvegarde.dechiffrer(f, phrase: Self.phrase)
        #expect(lu == r)
        #expect(lu.lampes.map(\.logiciel) == ["1.4", nil] && lu.lampes.map(\.ble) == ["1.69", nil])
        // Sans version, rien n'est ecrit : le fichier est celui d'avant, et il se relit.
        let ancien = try Sauvegarde.dechiffrer(try Sauvegarde.chiffrer(Factice.reseau(), phrase: Self.phrase, tours: 1000),
                                               phrase: Self.phrase)
        #expect(ancien == Factice.reseau())
        #expect(ancien.lampes.allSatisfy { $0.logiciel == nil && $0.ble == nil })
    }

    @Test func toursParDefaut() throws {
        let f = try Sauvegarde.chiffrer(Factice.reseau(), phrase: Self.phrase)
        #expect(f[9..<13] == Data([0x00, 0x09, 0x27, 0xC0]), "600 000 tours dans l'en-tete")
        #expect(try Sauvegarde.dechiffrer(f, phrase: Self.phrase) == Factice.reseau())
    }

    @Test func phraseFausseOuFichierAltere() throws {
        let f = try Sauvegarde.chiffrer(Factice.reseau(), phrase: Self.phrase, tours: 1000)
        #expect(throws: ErreurSauvegarde.ouvertureImpossible) { try Sauvegarde.dechiffrer(f, phrase: "une autre phrase longue") }
        #expect(throws: ErreurSauvegarde.ouvertureImpossible) { try Sauvegarde.dechiffrer(f, phrase: "") }
        // Chaque octet apres la version (tours, sel, nonce, contenu, etiquette) est verifie.
        for i in stride(from: 9, to: f.count, by: 7) {
            var g = f
            g[i] ^= 0x01
            #expect(throws: ErreurSauvegarde.ouvertureImpossible) { try Sauvegarde.dechiffrer(g, phrase: Self.phrase) }
        }
        var v = f
        v[8] = 2
        #expect(throws: ErreurSauvegarde.versionInconnue(2)) { try Sauvegarde.dechiffrer(v, phrase: Self.phrase) }
        #expect(throws: ErreurSauvegarde.pasUneSauvegarde) { try Sauvegarde.dechiffrer(Data("AMARANS".utf8), phrase: Self.phrase) }
        #expect(throws: ErreurSauvegarde.pasUneSauvegarde) { try Sauvegarde.dechiffrer(f.prefix(29), phrase: Self.phrase) }
    }

    @Test func phraseDePasse() {
        #expect(throws: ErreurSauvegarde.phraseTropCourte(11)) { try Sauvegarde.verifierPhrase("onze lettre", confirmation: "onze lettre") }
        #expect(throws: ErreurSauvegarde.phrasesDifferentes) { try Sauvegarde.verifierPhrase(Self.phrase, confirmation: Self.phrase + "!") }
        #expect(throws: Never.self) { try Sauvegarde.verifierPhrase("douze lettre", confirmation: "douze lettre") }
    }

    /// La phrase est normalisee (NFC) avant PBKDF2 : compose ou decompose, le meme « e » accentue ouvre la sauvegarde.
    @Test func phraseNormalisee() throws {
        let compose = "phrase de passe \u{E9}t\u{E9}"
        let decompose = "phrase de passe e\u{301}te\u{301}"
        let f = try Sauvegarde.chiffrer(Factice.reseau(), phrase: compose, tours: 1000)
        #expect(try Sauvegarde.dechiffrer(f, phrase: decompose) == Factice.reseau())
    }
}

@Suite("Copie du trousseau : versions des lampes", .langue(.francais))
struct VersionsCopieTests {
    /// Le JSON d'une copie ou d'une sauvegarde faite avant la fiche des lampes : sans `logiciel` ni `ble`.
    @Test func copieSansLesChampsSeRelit() throws {
        var r = Factice.reseau()
        r.lampes[1].logiciel = "1.4"
        r.lampes[1].ble = "1.69"
        let plein = try JSONEncoder().encode(r)
        var o = try #require(try JSONSerialization.jsonObject(with: plein) as? [String: Any])
        var lampes = try #require(o["lampes"] as? [[String: Any]])
        #expect(lampes[1]["logiciel"] as? String == "1.4" && lampes[1]["ble"] as? String == "1.69")
        #expect(lampes[0]["logiciel"] == nil && lampes[0]["ble"] == nil, "inconnue : rien n'est ecrit")
        #expect(try JSONDecoder().decode(ReseauMesh.self, from: plein) == r)
        for i in lampes.indices {
            lampes[i].removeValue(forKey: "logiciel")
            lampes[i].removeValue(forKey: "ble")
        }
        o["lampes"] = lampes
        let ancien = try JSONDecoder().decode(ReseauMesh.self, from: JSONSerialization.data(withJSONObject: o))
        #expect(ancien.lampes.allSatisfy { $0.logiciel == nil && $0.ble == nil })
        #expect(ancien.lampes.map(\.nom) == r.lampes.map(\.nom))
        // Valeurs `null` : inconnues aussi.
        let nulles = Data(#"{"adresse":2,"mac":"02:00:00:00:00:01","nom":"A","code":1,"declarees":[],"logiciel":null,"ble":null}"#.utf8)
        #expect(try JSONDecoder().decode(LampeReseau.self, from: nulles).logiciel == nil)
    }
}

@Suite("Controles du chargement", .langue(.francais))
struct ChargementTests {
    @Test func reponsesDuPont() {
        let e = VerificationChargement.empreintesRendues(["ok cles 1a2b3c4d 5E6F7A8B (redemarrer pour les appliquer)"])
        #expect(e?.reseau == "1A2B3C4D" && e?.application == "5E6F7A8B")
        #expect(VerificationChargement.empreintesRendues(["erreur : ecriture NVS"]) == nil)
        #expect(VerificationChargement.listeEnregistree([
            "ok lampe 2 0x0004 modele 40065 amaran COB 60d [intensite] : Lumière fenêtre ; liste de 2 lampe(s) enregistree (redemarrer pour l'appliquer)",
        ]) == 2)
        #expect(VerificationChargement.listeEnregistree(["ok lampe 1 0x0002 modele 40065 amaran COB 60d [intensite] : A"]) == nil)
    }

    @Test func apresLeRedemarrage() throws {
        let r = Factice.reseau()
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let mesh = try d.decode(ConfigMesh.self, from: Data(#"{"cles":true,"empreintes":{"reseau":"BE45CB26","application":"\#(r.empreinteApplication)"},"lampes":2}"#.utf8))
        func lampe(_ n: Int, _ a: String, _ mac: String, _ nom: String) throws -> ConfigLampe {
            try d.decode(ConfigLampe.self, from: Data(#"{"lampe":\#(n),"adresse":"\#(a)","mac":"\#(mac)","nom":"\#(nom)","code":40065}"#.utf8))
        }
        let lampes = [1: try lampe(1, "0002", "020000000001", "Lampe bureau"),
                      2: try lampe(2, "0004", "020000000002", "Lumière fenêtre")]
        #expect(VerificationChargement.ecart(r.apercu, mesh: mesh, lampes: lampes) == nil)
        #expect(VerificationChargement.ecart(r.apercu, mesh: mesh, lampes: [1: lampes[1]!]) == "1 lampe(s), 2 attendue(s)")
        var autre = r
        autre.lampes[0].nom = "Autre nom"
        #expect(VerificationChargement.ecart(autre.apercu, mesh: mesh, lampes: lampes) == "lampe 1 différente")
        autre = r
        autre.cleReseau = Data(count: 16)
        #expect(VerificationChargement.ecart(autre.apercu, mesh: mesh, lampes: lampes)?.hasPrefix("empreintes BE45CB26") == true)
        #expect(VerificationChargement.ecart(r.apercu, mesh: nil, lampes: lampes) == "pas de clés")
    }
}

extension ChargementTests {
    /// La verification apres le redemarrage compare aussi les versions : celles que le pont montre
    /// (`logiciel`, `ble` du bloc `config` `lampe`) contre celles du jeton envoye.
    @Test func apresLeRedemarrageLesVersions() throws {
        var r = Factice.reseau()
        r.lampes[0].logiciel = "1.4"
        r.lampes[0].ble = "1.69"
        r.lampes[1].logiciel = "1.4"
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let mesh = try d.decode(ConfigMesh.self, from: Data(#"{"cles":true,"empreintes":{"reseau":"BE45CB26","application":"\#(r.empreinteApplication)"},"lampes":2}"#.utf8))
        func lampe(_ n: Int, _ a: String, _ mac: String, _ nom: String, _ versions: String) throws -> ConfigLampe {
            try d.decode(ConfigLampe.self, from: Data(#"{"lampe":\#(n),"adresse":"\#(a)","mac":"\#(mac)","nom":"\#(nom)","code":40065\#(versions)}"#.utf8))
        }
        func pont(_ v1: String, _ v2: String) throws -> [Int: ConfigLampe] {
            [1: try lampe(1, "0002", "020000000001", "Lampe bureau", v1), 2: try lampe(2, "0004", "020000000002", "Lumière fenêtre", v2)]
        }
        #expect(VerificationChargement.ecart(r.apercu, mesh: mesh,
                                             lampes: try pont(#","logiciel":"1.4","ble":"1.69""#, #","logiciel":"1.4","ble":null"#)) == nil)
        // Le pont n'a pas garde les versions : ecart nomme.
        let sans = VerificationChargement.ecart(r.apercu, mesh: mesh, lampes: try pont("", #","logiciel":"1.4""#))
        #expect(sans == "lampe 1 : versions différentes (pont : inconnues, chargées : 1.4 (BLE 1.69))")
        // Autre version, ou module Bluetooth en moins.
        #expect(VerificationChargement.ecart(r.apercu, mesh: mesh,
                                             lampes: try pont(#","logiciel":"1.5","ble":"1.69""#, #","logiciel":"1.4""#))
                == "lampe 1 : versions différentes (pont : 1.5 (BLE 1.69), chargées : 1.4 (BLE 1.69))")
        #expect(VerificationChargement.ecart(r.apercu, mesh: mesh,
                                             lampes: try pont(#","logiciel":"1.4","ble":"1.69""#, #","logiciel":"1.4","ble":"1.69""#))
                == "lampe 2 : versions différentes (pont : 1.4 (BLE 1.69), chargées : 1.4)")
        // Version mal formee venue du pont : inconnue, jamais de plantage.
        #expect(VerificationChargement.ecart(r.apercu, mesh: mesh,
                                             lampes: try pont(#","logiciel":"abc","ble":"1.69""#, #","logiciel":"1.4""#))
                == "lampe 1 : versions différentes (pont : inconnues, chargées : 1.4 (BLE 1.69))")
        // Un module Bluetooth connu sans logiciel n'est pas envoye, donc pas attendu.
        var seulBle = Factice.reseau()
        seulBle.lampes[0].ble = "1.69"
        #expect(VerificationChargement.ecart(seulBle.apercu, mesh: mesh, lampes: try pont("", "")) == nil)
    }
}

@Suite("Comparaison des cles", .langue(.francais))
struct ComparaisonTests {
    static let copie = Factice.reseau().apercu

    @Test func pontDepuisSaConfig() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let mesh = try d.decode(ConfigMesh.self, from: Data(#"{"cles":true,"empreintes":{"reseau":"BE45CB26","application":"\#(Self.copie.empreinteApplication)"},"lampes":2}"#.utf8))
        let l1 = try d.decode(ConfigLampe.self, from: Data(#"{"lampe":1,"adresse":"0002","mac":"020000000001","nom":"Lampe bureau","code":40065}"#.utf8))
        let l2 = try d.decode(ConfigLampe.self, from: Data(#"{"lampe":2,"adresse":"0004","mac":"020000000002","nom":"Lumière fenêtre","code":40065}"#.utf8))
        let pont = try #require(ApercuReseau.dePont(mesh: mesh, lampes: [1: l1, 2: l2]))
        #expect(pont.memeReseau(que: Self.copie))
        #expect(pont.lampes[0].mac == "02:00:00:00:00:01")
        #expect(ApercuReseau.dePont(mesh: nil, lampes: [:]) == nil)
    }

    /// Donnees du pont mal formees (nombre de lampes negatif ou enorme, MAC de mauvaise longueur) :
    /// jamais de plantage, la lampe est ignoree.
    @Test func pontMalForme() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        func mesh(_ n: Int) throws -> ConfigMesh {
            try d.decode(ConfigMesh.self, from: Data(#"{"cles":true,"empreintes":{"reseau":"1A2B3C4D","application":"5E6F7A8B"},"lampes":\#(n)}"#.utf8))
        }
        #expect(ApercuReseau.dePont(mesh: try mesh(-3), lampes: [:])?.lampes.isEmpty == true)
        #expect(ApercuReseau.dePont(mesh: try mesh(2_000_000_000), lampes: [:])?.lampes.isEmpty == true)
        let deuxPoints = try d.decode(ConfigLampe.self, from: Data(#"{"lampe":1,"adresse":"0002","mac":"02:00:00:00:00:01","nom":"A","code":40065}"#.utf8))
        let impaire = try d.decode(ConfigLampe.self, from: Data(#"{"lampe":2,"adresse":"0004","mac":"02000000000","nom":"B","code":40065}"#.utf8))
        #expect(ApercuReseau.dePont(mesh: try mesh(2), lampes: [1: deuxPoints, 2: impaire])?.lampes.isEmpty == true)
    }

    @Test func ecarts() {
        let c = Self.copie
        #expect(ComparaisonCles.ecarts(base: c, copie: c, pont: c, pontConnu: true).isEmpty)
        #expect(ComparaisonCles.ecarts(base: c, copie: nil, pont: nil, pontConnu: true) == [.pasDeCopie])
        #expect(ComparaisonCles.ecarts(base: nil, copie: c, pont: nil, pontConnu: true) == [.pontSansCles])
        #expect(ComparaisonCles.ecarts(base: nil, copie: c, pont: nil, pontConnu: false).isEmpty, "pas de pont : rien a en dire")
        var autre = c
        autre.lampes.removeLast()
        #expect(ComparaisonCles.ecarts(base: c, copie: c, pont: autre, pontConnu: true) == [.pontDifferent])
        #expect(ComparaisonCles.ecarts(base: autre, copie: c, pont: c, pontConnu: true) == [.lampesChangees])
        var recree = c
        recree.empreinteReseau = "00000000"
        #expect(ComparaisonCles.ecarts(base: recree, copie: c, pont: c, pontConnu: true) == [.reseauRecree])
        // Les capacites declarees ne comptent pas : le pont ne les connait pas.
        var declarees = c
        declarees.lampes[0].declarees = ["cct"]
        #expect(declarees.memeReseau(que: c))
    }

    /// Les versions font partie de la lampe : inconnue d'un cote et connue de l'autre, ou changee,
    /// est un ecart nomme, avec le geste qui le resout.
    @Test func ecartsDeVersions() {
        var c = Self.copie
        c.lampes[0].logiciel = "1.4"
        c.lampes[0].ble = "1.69"
        #expect(ComparaisonCles.ecarts(base: c, copie: c, pont: c, pontConnu: true).isEmpty)
        // Le pont n'a pas les versions de la copie.
        let sans = Self.copie
        #expect(ComparaisonCles.ecarts(base: c, copie: c, pont: sans, pontConnu: true) == [.pontVersionsDifferentes])
        #expect(!sans.memeReseau(que: c) && sans.memesLampes(que: c) && !sans.memesVersions(que: c))
        // Autre version.
        var autre = c
        autre.lampes[0].logiciel = "1.5"
        #expect(ComparaisonCles.ecarts(base: c, copie: c, pont: autre, pontConnu: true) == [.pontVersionsDifferentes])
        // Le module Bluetooth change aussi.
        var ble = c
        ble.lampes[0].ble = "1.70"
        #expect(ComparaisonCles.ecarts(base: c, copie: c, pont: ble, pontConnu: true) == [.pontVersionsDifferentes])
        // La copie n'a aucune version (faite avant le plan 3b-3) : autre explication, memes gestes.
        #expect(ComparaisonCles.ecarts(base: c, copie: sans, pont: sans, pontConnu: true) == [.copieSansVersions])
        // La base a d'autres versions que la copie (mise a jour par Sidus).
        #expect(ComparaisonCles.ecarts(base: autre, copie: c, pont: c, pontConnu: true) == [.versionsChangees])
        // Des lampes changees passent avant des versions changees.
        var moinsUne = autre
        moinsUne.lampes.removeLast()
        #expect(ComparaisonCles.ecarts(base: moinsUne, copie: c, pont: c, pontConnu: true) == [.lampesChangees])
        // Un module Bluetooth seul n'est pas envoye au pont : pas un ecart.
        var seulBle = Self.copie
        seulBle.lampes[1].ble = "1.69"
        #expect(ComparaisonCles.ecarts(base: seulBle, copie: Self.copie, pont: Self.copie, pontConnu: true).isEmpty)
        // Les textes nomment le geste.
        #expect(EcartCles.pontVersionsDifferentes.texte.contains("« Charger le pont »"))
        #expect(EcartCles.versionsChangees.texte.contains("« Copier depuis amaran Desktop », puis « Charger le pont »"))
        #expect(EcartCles.copieSansVersions.texte.contains("pas encore les versions"))
        #expect(EcartCles.copieSansVersions.texte.contains("« Copier depuis amaran Desktop », puis « Charger le pont »"))
    }

    /// Un pont sans la capacite `logiciel` ne prend pas les versions : les recharger n'y changerait rien
    /// (boucle). L'ecart est nomme (firmware a mettre a jour), pas resolu par « Charger le pont ».
    @Test func pontQuiNePrendPasLesVersions() {
        var c = Self.copie
        c.lampes[0].logiciel = "1.4"
        let sans = Self.copie
        #expect(ComparaisonCles.ecarts(base: c, copie: c, pont: sans, pontConnu: true, pontPrendLesVersions: false)
                == [.pontSansVersions])
        #expect(EcartCles.pontSansVersions.texte == "Ce pont ne prend pas la version des lampes : mettre à jour son firmware.")
        // Copie sans version : rien a dire de ce pont.
        #expect(ComparaisonCles.ecarts(base: sans, copie: sans, pont: sans, pontConnu: true, pontPrendLesVersions: false).isEmpty)
        // Les autres ecarts restent dits.
        var autre = sans
        autre.lampes.removeLast()
        #expect(ComparaisonCles.ecarts(base: c, copie: c, pont: autre, pontConnu: true, pontPrendLesVersions: false) == [.pontDifferent])
    }

    /// Le bloc `config` `lampe` : `logiciel` et `ble`, chaines ou `null` ; une forme illisible devient inconnue.
    @Test func blocLampeAvecVersions() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        func lampe(_ champs: String) throws -> ConfigLampe {
            try d.decode(ConfigLampe.self, from: Data(#"{"lampe":1,"adresse":"0002","mac":"020000000001","nom":"A","code":40065\#(champs)}"#.utf8))
        }
        let pleine = try lampe(#","logiciel":"1.4","ble":"1.69""#)
        #expect(pleine.logiciel == "1.4" && pleine.ble == "1.69")
        #expect(Interpretation.logiciel(pleine, pontPrendLesVersions: true) == "1.4 (BLE 1.69)")
        let nulles = try lampe(#","logiciel":null,"ble":null"#)
        #expect(nulles.logiciel == nil && nulles.ble == nil)
        #expect(Interpretation.logiciel(nulles, pontPrendLesVersions: true) == "inconnu (recharger le pont)")
        let absentes = try lampe("")
        #expect(absentes.logiciel == nil && Interpretation.logiciel(absentes, pontPrendLesVersions: true) == "inconnu (recharger le pont)")
        #expect(Interpretation.logiciel(try lampe(#","logiciel":"1.4","ble":null"#), pontPrendLesVersions: true) == "1.4")
        #expect(Interpretation.logiciel(try lampe(#","logiciel":"1.4""#), pontPrendLesVersions: true) == "1.4")
        #expect(Interpretation.logiciel(try lampe(#","logiciel":null,"ble":"1.69""#), pontPrendLesVersions: true) == "inconnu (recharger le pont)")
        #expect(Interpretation.logiciel(try lampe(#","logiciel":"quatorze","ble":"1.69""#), pontPrendLesVersions: true) == "inconnu (recharger le pont)")
        #expect(Interpretation.logiciel(try lampe(#","logiciel":"1.4","ble":"x""#), pontPrendLesVersions: true) == "1.4")
        // Sans la capacite `logiciel` du pont, recharger ne sert a rien : le conseil change ; une version connue ne change pas.
        #expect(Interpretation.logiciel(absentes, pontPrendLesVersions: false) == "inconnu (firmware du pont à mettre à jour)")
        #expect(Interpretation.logiciel(pleine, pontPrendLesVersions: false) == "1.4 (BLE 1.69)")
        // Dans l'apercu du pont : les versions bien formees, sinon inconnues.
        let mesh = try d.decode(ConfigMesh.self, from: Data(#"{"cles":true,"empreintes":{"reseau":"1A2B3C4D","application":"5E6F7A8B"},"lampes":2}"#.utf8))
        let l2 = try d.decode(ConfigLampe.self, from: Data(#"{"lampe":2,"adresse":"0004","mac":"020000000002","nom":"B","code":40065,"logiciel":"1.4.0","ble":"1.69"}"#.utf8))
        let apercu = try #require(ApercuReseau.dePont(mesh: mesh, lampes: [1: pleine, 2: l2]))
        #expect(apercu.lampes.map(\.logiciel) == ["1.4", nil] && apercu.lampes.map(\.ble) == ["1.69", "1.69"])
        #expect(apercu.lampes.map(\.jetonVersion) == ["v1.4/1.69", nil])
    }

    /// Comme outils/cles_amaran.py : une capacite declaree dans la base, que le pont
    /// ne connait pas a la lampe (meme MAC), fait un modele a cataloguer.
    @Test func modelesACataloguer() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let l1 = try d.decode(ConfigLampe.self, from: Data(#"{"lampe":1,"mac":"020000000001","capacites":["intensite"]}"#.utf8))
        let l2 = try d.decode(ConfigLampe.self, from: Data(#"{"lampe":2,"mac":"020000000002","capacites":["intensite","cct"]}"#.utf8))
        var base = Self.copie
        base.lampes[0].declarees = []
        base.lampes[1].declarees = ["cct", "couleur"]
        let m = ComparaisonCles.modelesACataloguer(base: base, pont: [1: l1, 2: l2])
        #expect(m == [ModeleACataloguer(lampe: 2, nom: "Lumière fenêtre", code: 40065, capacite: "couleur")])
        #expect(m.first?.texte == "Lampe 2 (Lumière fenêtre, code 40065) : déclare la couleur, que le pont ne lui connaît pas : marche et intensité seulement, modèle à cataloguer.")
        #expect(ComparaisonCles.modelesACataloguer(base: nil, pont: [1: l1]).isEmpty)
        #expect(ComparaisonCles.modelesACataloguer(base: base, pont: [:]).isEmpty, "pas de pont : rien a en dire")
    }
}
