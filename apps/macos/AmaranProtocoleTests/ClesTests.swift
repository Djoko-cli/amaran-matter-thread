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
    static let cles = "insert into mesh values ('000102030405060708090A0B0C0D0E0F', '101112131415161718191a1b1c1d1e1f')"
}

@Suite("Cles du reseau")
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
        #expect(PolitiqueCommandes.masquerCle("id=7 MESH  Cles 00112233445566778899aabbccddeeff x")
                == "id=7 MESH  Cles •••••••• •••••••• x")
        #expect(PolitiqueCommandes.masquerCle("ok cles 1A2B3C4D 5E6F7A8B (redemarrer)") == "ok cles 1A2B3C4D 5E6F7A8B (redemarrer)",
                "les empreintes restent visibles")
        #expect(PolitiqueCommandes.verdictConsole(c)
                == .confirmation("Remplace les clés du réseau des lampes dans le pont (effet au redémarrage). « Charger le pont » vérifie en plus les empreintes."))
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

@Suite("Base d'amaran Desktop")
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

@Suite("Sauvegarde chiffree")
struct SauvegardeTests {
    static let phrase = "une phrase de passe assez longue"

    @Test func allerRetour() throws {
        let f = try Sauvegarde.chiffrer(Factice.reseau(), phrase: Self.phrase, tours: 1000)
        #expect(f.prefix(8) == Data("AMARANSV".utf8))
        #expect(f.range(of: Factice.cleReseau) == nil, "la cle n'apparait pas en clair")
        let r = try Sauvegarde.dechiffrer(f, phrase: Self.phrase)
        #expect(r == Factice.reseau())
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

@Suite("Controles du chargement")
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

@Suite("Comparaison des cles")
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
