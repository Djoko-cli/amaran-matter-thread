import Foundation
import Observation
import Testing
@testable import AmaranProtocole

/// Impose une langue aux textes du test (et de ses sous-taches), sans toucher
/// a la langue de l'app : les suites tournent en parallele.
struct LangueImposee: TestTrait, SuiteTrait, TestScoping {
    let langue: Langue
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @Sendable () async throws -> Void) async throws {
        try await Localisation.$imposee.withValue(langue) { try await function() }
    }
}

extension Trait where Self == LangueImposee {
    static func langue(_ l: Langue) -> Self { LangueImposee(langue: l) }
}

/// Les catalogues (`*.xcstrings`) lus dans le depot, et les cles que le
/// compilateur a extraites du code (`.stringsdata`).
enum Catalogues {
    static let racine = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AmaranProtocoleTests
        .deletingLastPathComponent()  // macos

    struct Catalogue: Sendable, CustomStringConvertible {
        let cible: String
        /// Table : le nom du fichier (`Localizable`, `Titres`).
        let table: String
        let chemin: URL
        var description: String { "\(cible)/\(table)" }
    }

    /// Catalogues du framework et de l'app, trouves dans leurs dossiers.
    static let tous: [Catalogue] = ["AmaranProtocole", "AmaranCompagnon"].flatMap { cible in
        let dossier = racine.appendingPathComponent(cible)
        let fichiers = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "xcstrings" } ?? []
        return fichiers.sorted { $0.path < $1.path }.map {
            Catalogue(cible: cible, table: $0.deletingPathExtension().lastPathComponent, chemin: $0)
        }
    }

    static func entrees(_ chemin: URL) throws -> (source: String, cles: [String: [String: Any]]) {
        let d = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: chemin)) as? [String: Any])
        let cles = try #require(d["strings"] as? [String: [String: Any]])
        return (d["sourceLanguage"] as? String ?? "", cles)
    }

    /// Dossier des produits (`.../Build/Products/Debug`) : celui du paquet de test.
    private final class Ancre {}
    static var produits: URL { Bundle(for: Ancre.self).bundleURL.deletingLastPathComponent() }

    /// `.stringsdata` d'une cible : `Build/Intermediates.noindex/<projet>.build/<config>/<cible>.build/Objects-normal/<arch>/`.
    static func stringsdata(cible: String) -> [URL] {
        let config = produits.lastPathComponent
        let intermediaires = produits.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Intermediates.noindex")
        let fm = FileManager.default
        guard let projets = try? fm.contentsOfDirectory(at: intermediaires, includingPropertiesForKeys: nil) else { return [] }
        var fichiers: [URL] = []
        for projet in projets {
            let objets = projet.appendingPathComponent(config).appendingPathComponent("\(cible).build/Objects-normal")
            for arch in (try? fm.contentsOfDirectory(at: objets, includingPropertiesForKeys: nil)) ?? [] {
                for f in (try? fm.contentsOfDirectory(at: arch, includingPropertiesForKeys: nil)) ?? []
                where f.pathExtension == "stringsdata" {
                    fichiers.append(f)
                }
            }
        }
        return fichiers
    }

    static var stringsdataDisponibles: Bool {
        !stringsdata(cible: "AmaranProtocole").isEmpty && !stringsdata(cible: "AmaranCompagnon").isEmpty
    }

    /// Cles extraites du code d'une cible, par table.
    static func clesExtraites(cible: String) throws -> [String: Set<String>] {
        var cles: [String: Set<String>] = [:]
        for f in stringsdata(cible: cible) {
            let d = try JSONSerialization.jsonObject(with: Data(contentsOf: f)) as? [String: Any]
            let tables = d?["tables"] as? [String: [[String: Any]]] ?? [:]
            for (table, entrees) in tables {
                for e in entrees { if let k = e["key"] as? String { cles[table, default: []].insert(k) } }
            }
        }
        return cles
    }

    /// Specificateurs d'un format, sans leur position (`%1$@` -> `@`), dans l'ordre.
    static func specificateurs(_ s: String) -> [String] {
        let motif = /%(?:\d+\$)?(lld|ld|d|@|lf|f|%)/
        return s.matches(of: motif).map { String($0.output.1) }
    }

    /// Unites de texte d'une localisation : simple, ou formes du pluriel.
    static func unites(_ loc: [String: Any]) -> [String: [String: Any]] {
        if let u = loc["stringUnit"] as? [String: Any] { return ["": u] }
        let pluriel = (loc["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] ?? [:]
        return pluriel.compactMapValues { $0["stringUnit"] as? [String: Any] }
    }
}

@Suite("Catalogues de textes (francais source, anglais complet)")
struct CataloguesTests {
    @Test func catalogues() {
        #expect(Catalogues.tous.map(\.description)
                == ["AmaranProtocole/Localizable", "AmaranCompagnon/InfoPlist", "AmaranCompagnon/Localizable",
                    "AmaranCompagnon/Titres"])
    }

    /// Catalogues des textes du code (l'Info.plist a le sien, sans cle extraite du code).
    static let duCode = Catalogues.tous.filter { $0.table != "InfoPlist" }

    @Test(arguments: Catalogues.tous)
    func chaqueCleATraductionAnglaise(_ c: Catalogues.Catalogue) throws {
        let (source, cles) = try Catalogues.entrees(c.chemin)
        #expect(source == "fr", "le francais est la langue de developpement")
        #expect(!cles.isEmpty)
        for (cle, entree) in cles {
            #expect(entree["extractionState"] as? String != "stale", "cle perimee : \(cle)")
            let locs = entree["localizations"] as? [String: [String: Any]] ?? [:]
            let en = try #require(locs["en"], "pas d'anglais : \(cle)")
            let unites = Catalogues.unites(en)
            #expect(!unites.isEmpty, "anglais vide : \(cle)")
            if unites.keys.contains(where: { !$0.isEmpty }) {
                #expect(unites["one"] != nil && unites["other"] != nil, "pluriel incomplet : \(cle)")
            }
            let attendus = Catalogues.specificateurs(cle)
            for (forme, u) in unites {
                #expect(u["state"] as? String == "translated", "anglais non valide (\(forme)) : \(cle)")
                let valeur = u["value"] as? String ?? ""
                #expect(!valeur.isEmpty, "anglais vide (\(forme)) : \(cle)")
                // Memes valeurs interpolees, de memes types (l'ordre peut changer avec %1$).
                #expect(Catalogues.specificateurs(valeur).sorted() == attendus.sorted(),
                        "specificateurs differents : \(cle) -> \(valeur)")
            }
            // Le francais du pluriel (s'il y en a un) garde lui aussi ses valeurs.
            for (forme, u) in Catalogues.unites(locs["fr"] ?? [:]) {
                let valeur = u["value"] as? String ?? ""
                #expect(Catalogues.specificateurs(valeur).sorted() == attendus.sorted(),
                        "francais (\(forme)) : \(cle) -> \(valeur)")
            }
        }
    }

    /// Le code et les catalogues vont ensemble : aucune cle extraite du code
    /// ne manque, aucune cle du catalogue n'est morte (rejouer
    /// `xcstringstool sync` apres un changement de texte, voir le README).
    @Test(.enabled(if: Catalogues.stringsdataDisponibles, "produits de compilation introuvables"),
          arguments: Self.duCode)
    func codeEtCatalogueAlignes(_ c: Catalogues.Catalogue) throws {
        let extraites = try Catalogues.clesExtraites(cible: c.cible)[c.table] ?? []
        let catalogue = Set(try Catalogues.entrees(c.chemin).cles.keys)
        #expect(!extraites.isEmpty)
        #expect(extraites.subtracting(catalogue).sorted() == [], "absentes du catalogue \(c)")
        #expect(catalogue.subtracting(extraites).sorted() == [], "inutilisees dans \(c)")
    }

    /// Chaque table utilisee par le code a son catalogue.
    @Test(.enabled(if: Catalogues.stringsdataDisponibles, "produits de compilation introuvables"),
          arguments: ["AmaranProtocole", "AmaranCompagnon"])
    func chaqueTableASonCatalogue(_ cible: String) throws {
        let tables = Set(try Catalogues.clesExtraites(cible: cible).keys)
        let catalogues = Set(Self.duCode.filter { $0.cible == cible }.map(\.table))
        #expect(tables == catalogues)
    }
}

@Suite("Reglage de la langue")
struct ChoixLangueTests {
    @Test func langueDuSysteme() {
        #expect(ChoixLangue.systeme.langue(preferences: ["en-GB", "fr-FR"]) == .anglais)
        #expect(ChoixLangue.systeme.langue(preferences: ["fr-CA", "en-US"]) == .francais)
        #expect(ChoixLangue.systeme.langue(preferences: ["de-DE", "en-US"]) == .anglais, "premiere langue servie")
        #expect(ChoixLangue.systeme.langue(preferences: ["de-DE"]) == .francais, "a defaut, la langue de developpement")
        #expect(ChoixLangue.systeme.langue(preferences: []) == .francais)
    }

    @Test func langueImposee() {
        #expect(ChoixLangue.anglais.langue(preferences: ["fr-FR"]) == .anglais)
        #expect(ChoixLangue.francais.langue(preferences: ["en-US"]) == .francais)
        #expect(ChoixLangue.allCases == [.systeme, .anglais, .francais])
        #expect(ChoixLangue(rawValue: "anglais") == .anglais, "valeur gardee dans les preferences")
    }

    @Test func localeDesFormats() {
        let france = Locale(identifier: "fr_FR")
        let anglais = ChoixLangue.anglais.locale(courante: france, preferences: ["fr-FR"])
        #expect(anglais.language.languageCode == .english)
        #expect(anglais.region == .france, "la region de l'utilisateur reste : anglais en France")
        let francais = ChoixLangue.francais.locale(courante: france, preferences: ["en-US"])
        #expect(francais == france, "la locale courante parle deja francais : gardee telle quelle")
        let systeme = ChoixLangue.systeme.locale(courante: Locale(identifier: "en_US"), preferences: ["en-US"])
        #expect(systeme.identifier == "en_US")
        let etats = ChoixLangue.francais.locale(courante: Locale(identifier: "en_US"), preferences: [])
        #expect(etats.language.languageCode == .french)
        #expect(etats.region == .unitedStates)
        // Les nombres suivent la locale choisie.
        #expect(2.5.formatted(.number.locale(Locale(identifier: "en_US"))) == "2.5")
        #expect(2.5.formatted(.number.locale(ChoixLangue.francais.locale(courante: france, preferences: []))) == "2,5")
    }

    @Test func changerDeLangueRedessineLesVues() {
        let l = Localisation(langue: .francais)
        final class Drapeau: @unchecked Sendable { var leve = false }
        let d = Drapeau()
        withObservationTracking { _ = l.langue } onChange: { d.leve = true }
        l.appliquer(.anglais, locale: Locale(identifier: "en_US"))
        #expect(d.leve, "une vue qui a lu un texte depend de la langue")
        #expect(l.langue == .anglais)
        #expect(l.locale.identifier == "en_US")
        #expect(l.texte("déjà traitée", paquet: .protocole) == "already handled")
        l.appliquer(.francais, locale: Locale(identifier: "fr_FR"))
        #expect(l.texte("déjà traitée", paquet: .protocole) == "déjà traitée")
    }
}

@Suite("Sens decode dans les deux langues")
struct SensDecodeTests {
    static func tout() throws -> [LigneMachine] { try ExemplesSpec.decoder() }

    static let abandon = EvenementOrdre(lampe: 1, issue: .abandon, delaiMs: 3700, essai: 3, ids: [4], idsPerdus: 0)
    static let refuse = EvenementOrdre(lampe: 1, issue: .abandon, delaiMs: 0, essai: 0, ids: [4], idsPerdus: 0)
    static let confirme = EvenementOrdre(lampe: 1, issue: .confirme, delaiMs: 410, essai: 1, ids: [2], idsPerdus: 0)
    static let tenu = EvenementOrdre(lampe: 1, issue: .tenu, delaiMs: 0, essai: 0, ids: [], idsPerdus: 0)

    @Test(.langue(.francais)) func enFrancais() throws {
        #expect(Interpretation.ordre(Self.abandon) == "abandonné après 3 essai(s), 3700 ms : la lampe ne répond pas")
        #expect(Interpretation.ordre(Self.refuse) == "abandonné : Bluetooth Mesh pas prêt, rien n'est parti vers la lampe")
        #expect(Interpretation.ordre(Self.confirme) == "confirmé en 410 ms (essai 1)")
        #expect(Interpretation.ordre(Self.tenu) == "déjà tenu : rien n'est parti vers la lampe")
        #expect(Interpretation.intensite(435) == "43,5 %" || Interpretation.intensite(435) == "43.5 %")
        #expect(Interpretation.intensite(430) == "43 %")
        #expect(Interpretation.code(.accepte) == "accepté")
        #expect(Interpretation.diag(.ivFaux) == "NetMIC faux, rien de déchiffré : IV Index faux (mesh iv cherche)")
        #expect(Interpretation.maison(nil) == "inconnue")
        #expect(Interpretation.etat(EtatLu(marche: true, intensite: 0)) == "noire : en marche à 0 %")
        #expect(MoteurSession.Note.silence(secondes: 6).texte == "Silence du pont depuis 6 s : json 1 renvoyé.")
        #expect(ErreurLigne.tropLongue(octets: 130, max: 127).description
                == "Ligne trop longue : 130 octets, 127 au plus avec le préfixe id=.")
        #expect(PolitiqueCommandes.verdictConsole("redemarre")
                == .confirmation("Redémarre le pont (le port USB va se ré-énumérer)."))
        #expect(PolitiqueCommandes.refusDistant("interdite a distance : USB seulement")
                == "la liste blanche du pont la refuse (« interdite a distance : USB seulement »)")
        #expect(ErreurReseau.version(lampe: 1, "1.2.3").description == "Lampe 1 : version « 1.2.3 » illisible (forme 1.4 attendue).")
    }

    @Test(.langue(.anglais)) func enAnglais() throws {
        #expect(Interpretation.ordre(Self.abandon) == "abandoned after 3 attempt(s), 3700 ms: the lamp is not responding")
        #expect(Interpretation.ordre(Self.refuse) == "abandoned: Bluetooth Mesh not ready, nothing was sent to the lamp")
        #expect(Interpretation.ordre(Self.confirme) == "confirmed in 410 ms (attempt 1)")
        #expect(Interpretation.ordre(Self.tenu) == "already satisfied: nothing was sent to the lamp")
        #expect(Interpretation.intensite(435).hasSuffix("5%") && Interpretation.intensite(435).hasPrefix("43"))
        #expect(Interpretation.intensite(430) == "43%", "pas d'espace avant « % » en anglais")
        #expect(Interpretation.code(.accepte) == "accepted")
        #expect(Interpretation.diag(.ivFaux) == "Bad NetMIC, nothing decrypted: wrong IV Index (mesh iv cherche)")
        #expect(Interpretation.maison(nil) == "unknown")
        #expect(Interpretation.etat(EtatLu(marche: true, intensite: 0)) == "dark: on at 0%")
        #expect(Interpretation.maison(BlocLampe.Maison(endpoint: 2, vue: true, masquee: nil)) == "in Apple Home (EP2)")
        #expect(MoteurSession.Note.silence(secondes: 6).texte == "Bridge silent for 6 s: json 1 sent again.")
        #expect(MoteurSession.Note.reseauSansHello.texte == "No answer to json 1 over the network: new handshake.")
        #expect(ErreurLigne.tropLongue(octets: 130, max: 127).description
                == "Line too long: 130 bytes, 127 at most including the id= prefix.")
        #expect(PolitiqueCommandes.verdictConsole("redemarre")
                == .confirmation("Restarts the bridge (the USB port will re-enumerate)."))
        #expect(PolitiqueCommandes.verdictConsole("json cle nouvelle 00")
                == .interdite("Use “New Key…”: the returned key must be stored in the keychain."))
        // La raison du pont n'est jamais traduite : citee telle quelle.
        #expect(PolitiqueCommandes.refusDistant("interdite a distance : USB seulement")
                == "the bridge's allow list refuses it (“interdite a distance : USB seulement”)")
        #expect(PolitiqueCommandes.verdictConsole("redemarre", transport: .udp)
                == .interdite("Command not sent: the bridge's allow list refuses it (“interdite a distance : USB seulement”)."))
        #expect(ErreurReseau.version(lampe: 1, "1.2.3").description == "Lamp 1: unreadable version “1.2.3” (form 1.4 expected).")
        #expect(ErreurTransportReseau.portInjoignable.description
                == "The bridge no longer has a key: plug it in over USB, then “Enable Network Access…”.")
        // Termes techniques intacts : champs JSON, commandes, unites.
        #expect(Interpretation.etat(EtatLu(marche: true, intensite: 500)) == "on, 50%")
    }

    /// Les trames du pont (7.6), dans les deux langues : sens, nature, lampe, essai, trames sautees.
    @Test func trames() throws {
        let trames = try Self.tout().compactMap { if case .trame(let t) = $0.message { t } else { nil } }
        let fr = Localisation.$imposee.withValue(.francais) { trames.map(Interpretation.trame) }
        let en = Localisation.$imposee.withValue(.anglais) { trames.map(Interpretation.trame) }
        #expect(fr == [
            "→ lampe 1 : ordre allumée, 50 % (essai 1)",
            "→ groupe : demande d'état",
            "← lampe 1 : état allumée, 50 % — 2 trame(s) non émise(s) avant",
        ])
        #expect(en == [
            "→ lamp 1: order on, 50% (attempt 1)",
            "→ group: state request",
            "← lamp 1: state on, 50% — 2 frame(s) not sent before",
        ])
    }

    /// `reponse` : la commande et le `msg` sont ceux du pont (jamais traduits), le reste suit la langue.
    @Test func reponseDuPontTelleQuelle() throws {
        let tout = try Self.tout()
        let deja = try #require(tout.compactMap { if case .reponse(let r) = $0.message, r.code == .dejaTraite { r } else { nil } }.first)
        let fr = Localisation.$imposee.withValue(.francais) { Interpretation.reponse(deja) }
        let en = Localisation.$imposee.withValue(.anglais) { Interpretation.reponse(deja) }
        #expect(fr.contains(": déjà traitée — id deja traite : reponse oubliee"), "\(fr)")
        #expect(en.contains(": already handled — id deja traite : reponse oubliee"), "\(en)")
    }

    @Test func langueImposeeParTache() async {
        // Deux taches en parallele, chacune sa langue : aucune ne deteint sur l'autre.
        async let fr = Localisation.$imposee.withValue(.francais) { Interpretation.code(.dejaTraite) }
        async let en = Localisation.$imposee.withValue(.anglais) { Interpretation.code(.dejaTraite) }
        #expect(await [fr, en] == ["déjà traitée", "already handled"])
    }
}
