// Masquage de la cle UDP (docs/PROTOCOLE-JSON.md 10.2) : aucune cle ne survit dans une
// ligne journalisee, entiere, coupee ou abimee. Cle inventee : les octets 0x40 a 0x5F.
import Foundation
import Testing
@testable import AmaranProtocole

enum CleInventee {
    static let octets = Data((0x40...0x5F).map { UInt8($0) })
    static let hexa = "404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F"
    /// La reponse de 10.6 qui rend la cle.
    static let reponse = #"{"v":1,"t":"reponse","n":60,"ms":860000,"id":5,"etape":"fin","cmd":"json cle nouvelle","ok":true,"code":"ok","duree_ms":12,"cle":"404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F","empreinte":"CA2A4FE7"}"#

    /// Vrai si un morceau de 6 hexa de la cle (casse quelconque) figure dans le texte.
    static func fuit(_ texte: String) -> Bool {
        let t = texte.uppercased()
        let h = Array(hexa)
        return (0...(h.count - 6)).contains { t.contains(String(h[$0..<($0 + 6)])) }
    }
}

@Suite("Masquage de la cle UDP (10.2)")
struct MasquageCleTests {
    @Test func commandeDeCreation() {
        let c = CleReseau.commande(alea: CleReseau.alea())
        #expect(PolitiqueCommandes.masquerCle(c) == "json cle nouvelle ••••••••")
        #expect(PolitiqueCommandes.masquerCle("id=5 " + CleReseau.commande(alea: CleInventee.octets))
                == "id=5 json cle nouvelle ••••••••")
        #expect(PolitiqueCommandes.masquerCle("JSON  Cle nouvelle " + CleInventee.hexa.lowercased())
                == "JSON  Cle nouvelle ••••••••")
        #expect(PolitiqueCommandes.masquerCle("json \"cle\" \"nouvelle\" \"\(CleInventee.hexa)\"")
                == "json \"cle\" \"nouvelle\" ••••••••")
        #expect(PolitiqueCommandes.masquerCle("json cle nouvelle 0011") == "json cle nouvelle ••••••••",
                "un alea court aussi")
        #expect(PolitiqueCommandes.masquerCle("‹ id=5 « json cle nouvelle » : ok (12 ms)")
                == "‹ id=5 « json cle nouvelle » : ok (12 ms)", "la commande citee par le pont ne porte rien")
        // Le suivi d'une commande secrete n'en garde que le masque.
        var c2 = Correlateur()
        let a = c2.soumettre(c, origine: .interface, secret: PolitiqueCommandes.masquerCle(c) != c, maintenant: 0)
        #expect(c2.suivi(a)?.commande == "json cle nouvelle ••••••••")
    }

    @Test func champCleDUneReponse() {
        let m = PolitiqueCommandes.masquerCle(CleInventee.reponse)
        #expect(!CleInventee.fuit(m))
        #expect(m.contains(#""cle":"••••••••","empreinte":"CA2A4FE7""#), "l'empreinte reste visible")
        #expect(PolitiqueCommandes.masquerCle(#"{"v":1,"t":"reseau","n":1,"bloc":"ip","srp":"1A2B3C4D5E6F7081","udp":{"cle":true,"empreinte":"CA2A4FE7"}}"#)
                == #"{"v":1,"t":"reseau","n":1,"bloc":"ip","srp":"1A2B3C4D5E6F7081","udp":{"cle":true,"empreinte":"CA2A4FE7"}}"#,
                "le bloc ip ne porte pas la cle : intact")
    }

    @Test func ligneMachineSansCle() throws {
        var r = RecepteurLignes()
        let e = r.alimenter(ligneMachine(CleInventee.reponse))
        guard case .machine(let l) = try #require(e.first) else {
            Issue.record("ligne machine attendue")
            return
        }
        guard case .reponse(let brute) = l.message else { Issue.record("reponse attendue"); return }
        #expect(brute.cle == CleInventee.hexa, "decodee, la cle est la (pour le trousseau)")
        let propre = l.sansCle
        #expect(!CleInventee.fuit(propre.json))
        #expect(!CleInventee.fuit(String(describing: propre)))
        guard case .reponse(let rep) = propre.message else { Issue.record("reponse attendue"); return }
        #expect(rep.cle == nil && rep.empreinte == "CA2A4FE7")
        #expect(propre.enveloppe == l.enveloppe)
        #expect(!CleInventee.fuit(String(describing: l.message.sansCle)))
        #expect(!CleInventee.fuit(String(describing: try #require(e.first).sansCle)))
        // Une ligne sans cle passe telle quelle.
        let autre = r.alimenter(ligneMachine(#"{"v":1,"t":"hb","n":61,"ms":1,"boot":"3FA2C901","up_s":1,"json_perdus":0,"commande":null}"#))
        if case .machine(let h) = autre.first { #expect(h.sansCle == h) } else { Issue.record("hb attendu") }
    }

    /// La reponse coupee en deux a chaque octet (un LF perdu au milieu) : la premiere
    /// part est abimee, la seconde un fragment ; ou le debut perdu : un texte seul.
    @Test func ligneCoupeeAChaqueOctet() {
        let json = Array(CleInventee.reponse.utf8)
        for k in 1..<json.count {
            var r = RecepteurLignes()
            let coupee = r.alimenter([Octets.rs] + json[..<k] + [Octets.lf] + json[k...] + [Octets.lf])
            var seule = RecepteurLignes()
            let finSeule = seule.alimenter(Array(json[k...]) + [Octets.lf])
            for e in coupee + finSeule {
                let vu = String(describing: e.sansCle)
                #expect(!CleInventee.fuit(vu), "coupe a \(k) : \(vu)")
            }
        }
    }

    /// Un journal intercale au milieu de la ligne, sans LF : une seule ligne abimee.
    @Test func journalIntercale() {
        let json = Array(CleInventee.reponse.utf8)
        let journal = Array("E (12345) wifi: cafe".utf8)
        for k in 1..<json.count {
            var r = RecepteurLignes()
            for e in r.alimenter([Octets.rs] + json[..<k] + journal + json[k...] + [Octets.lf]) {
                let vu = String(describing: e.sansCle)
                #expect(!CleInventee.fuit(vu), "journal a \(k) : \(vu)")
            }
        }
    }

    @Test func debordement() {
        var r = RecepteurLignes()
        let long = Array(String(repeating: "x", count: 2100).utf8) + Array(CleInventee.reponse.utf8)
        let e = r.alimenter(long)
        #expect(!e.isEmpty)
        for x in e { #expect(!CleInventee.fuit(String(describing: x.sansCle))) }
    }

    /// Cles du Mesh inventees, et les memes ecrites avec un `\x` tous les 4 hexa : la console
    /// du pont oublie chaque barre oblique inverse et l'octet qui la suit (split_argv.c).
    static let k1 = "404142434445464748494A4B4C4D4E4F"
    static let k2 = "505152535455565758595A5B5C5D5E5F"
    static func echappee(_ k: String) -> String {
        stride(from: 0, to: k.count, by: 4).map { i in
            String(k.dropFirst(i).prefix(4))
        }.joined(separator: #"\x"#)
    }

    /// Vrai si un morceau de 6 hexa d'une cle se lit encore dans le texte, une fois decoupe
    /// comme le pont le decoupe (echappements et guillemets retires).
    static func fuiteLue(_ texte: String, _ cles: [String]) -> Bool {
        let lu = LigneCommande.arguments(Array(texte.utf8)).map { String(decoding: $0.valeur, as: UTF8.self) }
            .joined().uppercased()
        return cles.contains { cle in
            let h = Array(cle.uppercased())
            return (0...(h.count - 6)).contains { lu.contains(String(h[$0..<($0 + 6)])) }
        }
    }

    /// Relecture (reste du rapport) : guillemets et echappements que la console du pont
    /// retire ne cachent aucune cle au masque, ni dans la commande, ni la ou elle est citee
    /// (journal des envois, echo de la console, citation de l'app).
    @Test func echappementsEtGuillemetsNeCachentPasLaCle() {
        let (k1, k2) = (Self.k1, Self.k2)
        let (e1, e2) = (Self.echappee(k1), Self.echappee(k2))
        #expect(e1 == #"4041\x4243\x4445\x4647\x4849\x4A4B\x4C4D\x4E4F"#)
        #expect(LigneCommande.argv("mesh cles \(e1) \(e2)") == ["mesh", "cles", k1, k2], "le pont lit bien les cles")
        let cas: [(String, String)] = [
            ("mesh cles \(e1) \(e2)", "mesh cles •••••••• ••••••••"),
            (#"mesh cles "\#(k1)" "\#(k2)""#, "mesh cles •••••••• ••••••••"),
            (#"mesh cles "\#(e1)" \#(k2)"#, "mesh cles •••••••• ••••••••"),
            (#"me\xsh c\xles \#(k1) \#(k2)"#, #"me\xsh c\xles •••••••• ••••••••"#),
            (#""mesh" "cles" "\#(e1)" "\#(e2)""#, #""mesh" "cles" •••••••• ••••••••"#),
            (#""mesh cles \#(k1) \#(k2)""#, "mesh cles •••••••• ••••••••"),
            (#"mesh\ cles \#(e1) \#(e2)"#, #"mesh\ cles •••••••• ••••••••"#),
            ("json cle nouvelle \(e1)\(e2)", "json cle nouvelle ••••••••"),
            (#"js\xon cle nouvelle "\#(k1)\#(k2)""#, #"js\xon cle nouvelle ••••••••"#),
            ("› id=12 mesh cles \(e1) \(e2)", "› id=12 mesh cles •••••••• ••••••••"),
            ("› mesh cles \(e1) \(e2)", "› mesh cles •••••••• ••••••••"),
            ("amaran> mesh cles \(e1) \(e2)", "amaran> mesh cles •••••••• ••••••••"),
            // Un `»` tape n'arrete pas le masque : seule une citation de l'app (apres `«`) finit a `»`.
            ("mesh cles » \(e1) \(e2)", "mesh cles •••••••• •••••••• ••••••••"),
            ("› id=2 mesh cles » \(e1) \(e2)", "› id=2 mesh cles •••••••• •••••••• ••••••••"),
            ("json cle nouvelle » \(e1)\(e2)", "json cle nouvelle •••••••• ••••••••"),
            ("« mesh cles \(e1) \(e2) » n'est pas envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »).",
             "« mesh cles •••••••• •••••••• » n'est pas envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »)."),
        ]
        for (ligne, attendue) in cas {
            let m = PolitiqueCommandes.masquerCle(ligne)
            #expect(m == attendue, "\(ligne)")
            #expect(!Self.fuiteLue(m, [k1, k2]), "\(ligne) -> \(m)")
            #expect(PolitiqueCommandes.masquerCle(m) == m, "le masque est stable : \(m)")
            #expect(!Self.fuiteLue(PolitiqueCommandes.masquerCleStricte(ligne), [k1, k2]), "\(ligne)")
            #expect(!Self.fuiteLue(String(describing: ElementRecu.texte(ClasseurTexte.classer(ligne)).sansCle), [k1, k2]),
                    "texte recu du pont (echo) : \(ligne)")
        }
    }

    /// La regle ne masque que la commande : le texte d'usage du pont, une commande citee sans
    /// argument, ou toute autre commande, restent tels quels.
    @Test func lesAutresTextesRestentLisibles() {
        for t in ["erreur : mesh cles <reseau 32 hexa> <application 32 hexa>",
                  "‹ id=5 « json cle » : arguments invalides — json cle nouvelle <64 hexa> | json cle efface (0 ms)",
                  "‹ id=12 « mesh cles » : ok (12 ms)", "ok cles 1A2B3C4D 5E6F7A8B (redemarrer pour les appliquer)",
                  "mesh cles", "json cle efface", "json cle nouvelle", "mesh lampes 2", #""mesh lampe" 1 masquer"#,
                  "lampe 1 on", #"re\xdemarre"#, "etat ; mesh cles|lampes|lampe|iv|adresse|oublie ... ; "] {
            #expect(PolitiqueCommandes.masquerCle(t) == t, "\(t)")
        }
    }

    /// Le suivi d'une commande dont le masque change ne garde que le masque, meme si
    /// l'appelant ne l'a pas dite secrete ; la ligne envoyee, elle, porte les cles.
    @Test func leSuiviNeGardeJamaisLaCle() throws {
        let ligne = "mesh cles \(Self.echappee(Self.k1)) \(Self.echappee(Self.k2))"
        var c = Correlateur()
        let a = c.soumettre(ligne, origine: .console, maintenant: 0)
        #expect(c.suivi(a)?.commande == "mesh cles •••••••• ••••••••")
        let envoi = c.prochainEnvoi(maintenant: 0)
        let p = try #require(envoi)
        #expect(texte(p.octets) == "id=1 " + ligne + "\n", "le pont recoit la ligne telle quelle")
        #expect(!c.suivis.contains { Self.fuiteLue($0.commande, [Self.k1, Self.k2]) })
    }

    @Test func strictNeTouchePasAuTexteOrdinaire() {
        // Le texte d'une commande garde son nom SRP (16 hexa) et ses empreintes.
        let t = "srp : 1A2B3C4D5E6F7081, cle CA2A4FE7"
        #expect(PolitiqueCommandes.masquerCle(t) == t)
        let e = ElementRecu.texte(ClasseurTexte.classer(t))
        #expect(e.sansCle == e)
        // Les cles du Mesh (32 hexa) restent masquees partout.
        let mesh = "mesh cles 00112233445566778899aabbccddeeff ffeeddccbbaa99887766554433221100"
        #expect(PolitiqueCommandes.masquerCle(mesh) == "mesh cles •••••••• ••••••••")
        #expect(PolitiqueCommandes.masquerCleStricte(mesh) == "mesh cles •••••••• ••••••••")
    }
}
