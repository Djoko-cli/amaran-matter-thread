// Liste blanche a distance (docs/PROTOCOLE-JSON.md 10.5) : miroir de `refusDistant`
// (components/protocole/json_amaran.cpp), avec tous les cas de `testDistant`
// (tests/hote/test_json.cpp).
import Foundation
import Testing
@testable import AmaranProtocole

@Suite("Decoupage comme esp_console_split_argv")
struct DecoupageArgvTests {
    @Test func motsSimples() {
        #expect(LigneCommande.argv("json 1 bail 60") == ["json", "1", "bail", "60"])
        #expect(LigneCommande.argv("  lampe   1  on ") == ["lampe", "1", "on"])
        #expect(LigneCommande.argv("") == [])
        #expect(LigneCommande.argv("   ") == [])
    }

    @Test func guillemetsEtEchappements() {
        #expect(LigneCommande.argv(#"json "1" "bail" 0"#) == ["json", "1", "bail", "0"])
        #expect(LigneCommande.argv(#""mesh lampe" 1 masquer"#) == ["mesh lampe", "1", "masquer"])
        #expect(LigneCommande.argv(#""mesh"cles a"#) == ["mesh", "cles", "a"], "le guillemet fermant finit le mot")
        #expect(LigneCommande.argv(#"json\ 1"#) == ["json 1"], "espace echappee : un seul mot")
        #expect(LigneCommande.argv(#"a\"b"#) == [#"a"b"#])
        #expect(LigneCommande.argv(#"a\\b"#) == [#"a\b"#])
        #expect(LigneCommande.argv(#"le\d"#) == ["le"], "echappement inconnu : les deux octets oublies")
        #expect(LigneCommande.argv(#""x\"y" z"#) == [#"x"y"#, "z"])
        #expect(LigneCommande.argv(#""" x"#) == ["", "x"], "guillemets vides : un mot vide")
        #expect(LigneCommande.argv(#""non ferme"#) == ["non ferme"])
        #expect(LigneCommande.argv("json\t1") == ["json\t1"], "la tabulation fait partie du mot")
        #expect(LigneCommande.argv("Lumière fenêtre") == ["Lumière", "fenêtre"], "UTF-8 intact")
    }

    @Test func septArgumentsAuPlus() {
        #expect(LigneCommande.argv("1 2 3 4 5 6 7 8 9") == ["1", "2", "3", "4", "5", "6", "7"])
        #expect(LigneCommande.argv("1 2 3 4 5 6 7") == ["1", "2", "3", "4", "5", "6", "7"])
    }
}

@Suite("Liste blanche a distance (10.5)", .langue(.francais))
struct ListeBlancheTests {
    /// `kPermises` de testDistant.
    static let permises = [
        "json 1", "json 1 bail 10", "json 1 bail 120", "json 0", "json etat", "json hello", "json ping",
        "json periode 2000", "json periode 0", "json periode 60000", "json lampes 10000", "json lampes 0",
        "json compteurs 0", "json compteurs 5000", "json reseau 10000", "json reseau 0", "json trames 1",
        "json trames 0", "json log 1", "lampe 1", "lampe 2 on", "lampe 16 off", "lampe 1 niveau 500",
        "lampe 3 releve", "mesh", "mesh lampe 2 masquer", "mesh lampe 2 afficher", "led test", "led stop",
        "lampes", "matter", "taches", "cause",
    ]

    /// `kInterdites` de testDistant.
    static let interdites = [
        "json 1 bail 0", "json 1 bail 9", "json 1 bail 121", "json 1 bail", "json 1 xyz 30", "json periode 1999",
        "json periode 60001", "json lampes 9999", "json compteurs 4999", "json reseau 9999", "json trames 2",
        "json cle nouvelle 00", "json cle efface", "json", "json periode", "json periode 2000 3000",
        "lampe", "lampe x on", "lampe 1 clignote", "lampe 1 niveau", "lampe 1 niveau x", "lampe 1 on 2",
        "mesh cles 00 11", "mesh lampes 2", "mesh lampe 1 0x0002 02:00:00:00:00:01 40065 nom", "mesh oublie",
        "mesh adresse suivante", "mesh iv 5", "mesh releve 2", "mesh balayage", "mesh lampe 2 masquer x",
        "decommission", "redemarre", "led", "led test x", "taches x", "help", "",
    ]

    @Test(arguments: permises)
    func permise(_ c: String) {
        #expect(PolitiqueCommandes.autoriseeADistance(c) == nil)
    }

    @Test(arguments: interdites)
    func interdite(_ c: String) {
        #expect(PolitiqueCommandes.autoriseeADistance(c) != nil)
        if case .interdite = PolitiqueCommandes.verdictConsole(c, transport: .udp) {} else {
            Issue.record("\(c) doit etre refusee a distance")
        }
    }

    @Test func raisonsDuPont() {
        #expect(PolitiqueCommandes.autoriseeADistance("json 1 bail 0") == "json 1 : bail de 10 a 120 s a distance")
        #expect(PolitiqueCommandes.autoriseeADistance("json periode 100") == "json periode : 0 ou 2000..60000 ms a distance")
        #expect(PolitiqueCommandes.autoriseeADistance("json lampes 1") == "json lampes : 0 ou 10000..60000 ms a distance")
        #expect(PolitiqueCommandes.autoriseeADistance("json compteurs 1") == "json compteurs : 0 ou 5000..60000 ms a distance")
        #expect(PolitiqueCommandes.autoriseeADistance("json reseau 1") == "json reseau : 0 ou 10000..60000 ms a distance")
        #expect(PolitiqueCommandes.autoriseeADistance("redemarre") == "interdite a distance : USB seulement")
    }

    /// Un mot entre guillemets reste un seul mot une fois decoupe : la liste blanche le
    /// voit tel que la console l'executera.
    @Test func guillemetsEtEchappementsNeLaContournentPas() {
        for c in [#"json "1" "bail" 0"#, #"json 1 "bail" "0""#, #""json" 1 bail 0"#] {
            #expect(PolitiqueCommandes.autoriseeADistance(c) == "json 1 : bail de 10 a 120 s a distance", "\(c)")
        }
        #expect(PolitiqueCommandes.autoriseeADistance(#""mesh lampe" 1 masquer"#) != nil, "un seul mot 'mesh lampe'")
        #expect(PolitiqueCommandes.autoriseeADistance(#""json"cle efface"#) != nil)
        #expect(PolitiqueCommandes.autoriseeADistance(#"json\ 1"#) != nil, "un seul mot 'json 1'")
        #expect(PolitiqueCommandes.autoriseeADistance("JSON 1") != nil, "la console distingue la casse")
        #expect(PolitiqueCommandes.autoriseeADistance("json\t1") != nil, "la tabulation ne separe pas")
        #expect(PolitiqueCommandes.autoriseeADistance("lampe 1 niveau 1234567890") != nil, "10 chiffres : pas un nombre")
        #expect(PolitiqueCommandes.autoriseeADistance("lampe 1 niveau 123456789") == nil, "9 chiffres : un nombre")
        #expect(PolitiqueCommandes.autoriseeADistance("lampe 1 niveau -5") != nil)
        // Les guillemets autour d'un mot permis ne changent rien : decoupe identique.
        #expect(PolitiqueCommandes.autoriseeADistance(#""lampe" "1" "on""#) == nil)
        #expect(PolitiqueCommandes.autoriseeADistance("  led test  ") == nil, "espaces de bord retires a l'envoi")
    }

    @Test func consoleADistance() {
        #expect(PolitiqueCommandes.verdictConsole("lampe 1 on", transport: .udp) == .autorisee)
        #expect(PolitiqueCommandes.verdictConsole("mesh lampe 2 masquer", transport: .udp)
                == PolitiqueCommandes.verdictConsole("mesh lampe 2 masquer"), "permise : confirmation inchangee")
        // La raison du pont, citee une seule fois, telle quelle.
        #expect(PolitiqueCommandes.verdictConsole("redemarre", transport: .udp)
                == .interdite("Commande non envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »)."))
        #expect(PolitiqueCommandes.verdictConsole("redemarre")
                == .confirmation("Redémarre le pont (le port USB va se ré-énumérer)."), "USB : inchange")
    }

    /// La cle UDP ne se cree que par le geste de l'app (elle doit etre rangee).
    @Test func cleUDPParLaConsole() {
        let nouvelle = CleReseau.commande(alea: Data((0x40...0x5F).map { UInt8($0) }))
        if case .interdite(let raison) = PolitiqueCommandes.verdictConsole(nouvelle) {
            #expect(raison.contains("Nouvelle clé"))
        } else {
            Issue.record("json cle nouvelle doit etre refusee dans la console")
        }
        if case .confirmation = PolitiqueCommandes.verdictConsole("json cle efface") {} else {
            Issue.record("json cle efface demande confirmation")
        }
        #expect(PolitiqueCommandes.autoriseeADistance(nouvelle) != nil)
    }

    /// Par l'USB aussi, les regles de la console jugent la ligne decoupee comme la console
    /// du pont la decoupe : une barre oblique inverse devant un autre octet que `\`, `"` ou
    /// une espace disparait avec lui (split_argv.c d'ESP-IDF), et des guillemets autour d'un
    /// mot ne le changent pas. Ni refus ni confirmation ne se contournent ainsi.
    @Test func reglesDeLaConsoleJugeesSurArgv() {
        let alea = String(repeating: "AB", count: 32)
        #expect(LigneCommande.argv(#"re\xdemarre"#) == ["redemarre"])
        #expect(PolitiqueCommandes.verdictConsole(#"re\xdemarre"#)
                == PolitiqueCommandes.verdictConsole("redemarre"), "confirmation de redemarre")
        #expect(PolitiqueCommandes.verdictConsole(#"json c\xle efface"#)
                == PolitiqueCommandes.verdictConsole("json cle efface"), "confirmation de json cle efface")
        if case .interdite(let raison) = PolitiqueCommandes.verdictConsole(#"js\xon cle nouvelle "# + alea) {
            #expect(raison.contains("Nouvelle clé"))
        } else {
            Issue.record("js\\xon cle nouvelle : refusee comme json cle nouvelle")
        }
        for (ligne, pareille) in [(#"decommi\xssion"#, "decommission"), (#"mesh oub\xlie"#, "mesh oublie"),
                                  (#""mesh" "cles" 00 11"#, "mesh cles 00 11"), (#"js\xon 0"#, "json 0")] {
            #expect(LigneCommande.argv(ligne) == LigneCommande.argv(pareille), "\(ligne)")
            #expect(PolitiqueCommandes.verdictConsole(pareille) != .autorisee)
            #expect(PolitiqueCommandes.verdictConsole(ligne) == PolitiqueCommandes.verdictConsole(pareille), "\(ligne)")
        }
        #expect(PolitiqueCommandes.verdictConsole(#""mesh lampe" 1 masquer"#) == .autorisee,
                "un seul mot « mesh lampe » : le pont ne connait pas cette commande")
        // Sensible a la casse, comme la console : le pont ne connait pas REDEMARRE.
        #expect(PolitiqueCommandes.verdictConsole("REDEMARRE") == .autorisee)
        #expect(PolitiqueCommandes.attendReenumeration(#"re\xdemarre"#))
        #expect(PolitiqueCommandes.attendReenumeration(#""decommission""#))
        #expect(!PolitiqueCommandes.attendReenumeration("REDEMARRE"))
    }

    /// Confirmation de `decommission` : la cle de l'acces par Thread est effacee (10.2).
    @Test func decommissionDitLaCleThreadEffacee() {
        guard case .confirmation(let texte) = PolitiqueCommandes.verdictConsole("decommission") else {
            Issue.record("decommission demande confirmation")
            return
        }
        #expect(texte.contains("clés du Mesh et lampes gardées"))
        #expect(texte.contains("la clé de l'accès par Thread est effacée"))
    }

    @Test func bornesDuMoteurEtDeLaListe() {
        for (k, min) in PolitiqueCommandes.bornesDistantes {
            let c = MoteurSession.Cadence(rawValue: k)
            #expect(c != nil)
            #expect(c.map { MoteurSession.bornes($0, genre: .udp) } == min...60_000)
            #expect(PolitiqueCommandes.autoriseeADistance("json \(k) \(min)") == nil)
            #expect(PolitiqueCommandes.autoriseeADistance("json \(k) \(min - 1)") != nil)
        }
    }
}
