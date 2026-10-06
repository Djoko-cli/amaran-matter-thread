// Repris de Halo Compagnon (commit e114cd5) : les messages et les champs du pont amaran.
import Foundation
import Testing
@testable import AmaranProtocole

/// Couverture des cles : tout champ non nul d'une ligne du pont doit ressortir non
/// nul du modele decode. Une faute de frappe dans un nom de propriete decoderait
/// sinon en nil, sans rien dire (tous les champs sont optionnels, section 8).
enum CouvertureCles {
    /// Cle JSON -> nom de propriete, comme `.convertFromSnakeCase`.
    static func camel(_ cle: String) -> String {
        let parties = cle.split(separator: "_")
        guard parties.count > 1 else { return cle }
        return ([parties[0].lowercased()] + parties.dropFirst().map(\.capitalized)).joined()
    }

    /// Objets dont les cles sont des donnees (noms de taches), pas des champs : le
    /// decodeur ne les convertit pas.
    static let clesDonnees: Set<String> = ["sys.piles"]

    /// Chemins des valeurs non nulles : objets parcourus, tableaux indexes (un
    /// tableau vide compte comme une valeur presente).
    static func feuilles(_ v: Any, _ chemin: String = "", convertir: Bool) -> Set<String> {
        switch v {
        case let o as [String: Any]:
            var s = Set<String>()
            for (k, x) in o {
                let c = convertir && !clesDonnees.contains(chemin) ? camel(k) : k
                s.formUnion(feuilles(x, chemin.isEmpty ? c : chemin + "." + c, convertir: convertir))
            }
            return s
        case let a as [Any]:
            if a.isEmpty { return [chemin] }
            var s = Set<String>()
            for (i, x) in a.enumerated() { s.formUnion(feuilles(x, "\(chemin)[\(i)]", convertir: convertir)) }
            return s
        case is NSNull:
            return []
        default:
            return [chemin]
        }
    }

    static func encoder(_ m: MessageCarte) throws -> Data? {
        let e = JSONEncoder()
        switch m {
        case .helloBase(let v): return try e.encode(v)
        case .helloIdentite(let v): return try e.encode(v)
        case .configCatalogue(let v): return try e.encode(v)
        case .configMesh(let v): return try e.encode(v)
        case .configLampe(let v): return try e.encode(v)
        case .etatPont(let v): return try e.encode(v)
        case .etatLampe(let v): return try e.encode(v)
        case .etatSante(let v): return try e.encode(v)
        case .compteursMesh(let v): return try e.encode(v)
        case .reseauMatter(let v): return try e.encode(v)
        case .reseauThread(let v): return try e.encode(v)
        case .reseauIp(let v): return try e.encode(v)
        case .battement(let v): return try e.encode(v)
        case .fin(let v): return try e.encode(v)
        case .reponse(let v): return try e.encode(v)
        case .ordre(let v): return try e.encode(v)
        case .alerte(let v): return try e.encode(v)
        case .lampe(let v): return try e.encode(v)
        case .led(let v): return try e.encode(v)
        case .log(let v): return try e.encode(v)
        case .trame(let v): return try e.encode(v)
        case .texte(let v): return try e.encode(v)
        case .inconnu: return nil
        }
    }

    /// Champs non nuls de la ligne que le modele decode a perdus.
    static func perdus(_ json: String) throws -> [String] {
        var r = RecepteurLignes()
        let e = r.alimenter([Octets.rs] + Array(json.utf8) + [Octets.lf])
        guard e.count == 1, case .machine(let l) = e[0] else { return ["<ligne rejetee : \(e)>"] }
        guard let source = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let d = try encoder(l.message)
        else { return ["<type non gere : \(l.enveloppe.t)>"] }
        let attendus = feuilles(source, convertir: true).subtracting(["v", "t", "n", "ms", "bloc"])
        let obtenus = feuilles(try JSONSerialization.jsonObject(with: d), convertir: false)
        return attendus.subtracting(obtenus).sorted()
    }

    /// Champs que les exemples de la section 9 laissent nuls, vides ou absents.
    static let synthetiques: [String] = [
        // Un modele CCT au catalogue.
        #"{"v":1,"t":"config","n":1,"ms":1,"bloc":"catalogue","modeles":[{"code":40066,"nom":"amaran 150c","capacites":["intensite","cct","couleur"],"type":"couleur","cct_k":{"min":2500,"max":7500}}],"repli":{"nom":"modele non catalogue","capacites":["intensite"],"type":"variable","cct_k":null}}"#,
        // Mesh sans cles, puis une lampe masquee avec un ordre en attente.
        #"{"v":1,"t":"config","n":2,"ms":2,"bloc":"mesh","cles":false,"empreintes":null,"adresse":"7F38","iv_nvs":1,"balayage":{"fenetre_ms":20,"intervalle_ms":40},"lampes":0,"capacite":16,"releve_ms":2000,"groupe":"C000"}"#,
        #"{"v":1,"t":"etat","n":3,"ms":3,"bloc":"lampe","lampe":3,"maison":{"endpoint":null,"vue":true,"masquee":true},"entendue":true,"lue":{"marche":false,"intensite":0},"joignable":false,"reponse_ms":2,"consigne":{"marche":true,"intensite":null,"phase":"attente","essai":2},"repondues":1,"part_10min":null,"alerte":true}"#,
        // Pont sans Mesh, sante en test, hb en commande, journal plafonne.
        #"{"v":1,"t":"etat","n":4,"ms":4,"bloc":"pont","boot":"3FA2C901","up_s":4,"mesh":{"pret":false,"diag":"iv_faux"},"ordres":{"total":3,"confirmes":1,"abandons":1,"tenus":1,"delai_total_ms":500,"delai_max_ms":500,"lents":0},"releves":2,"trames":1}"#,
        #"{"v":1,"t":"etat","n":5,"ms":5,"bloc":"sante","boot":"3FA2C901","up_s":5,"commande":9,"led":{"motif":"panne_radio","test":true,"depuis_ms":3},"matter":{"en_service":false,"thread":false,"identifie":true,"ble":true},"sys":{"heap":1,"heap_min":2,"heap_bloc":3,"piles":{"json":4,"socle":null},"json_perdus":5,"json_trop_longs":6,"rejets":7}}"#,
        #"{"v":1,"t":"hb","n":6,"ms":6,"boot":"3FA2C901","up_s":6,"json_perdus":0,"commande":12}"#,
        #"{"v":1,"t":"log","n":7,"ms":7,"src":"bouton","niv":"notice","txt":"[bouton] relache : il etait tenu au demarrage, ignore","sautes":4}"#,
        // Matter hors service, sans codes connus ; Thread detache.
        #"{"v":1,"t":"reseau","n":8,"ms":8,"bloc":"matter","demarre":false,"fabriques":0,"ble":true,"identifie":false,"abonnements":{"demandes":0,"plafonnes":0,"etablis":0,"termines":0,"plafond_s":20},"code_manuel":null,"qr":null}"#,
        // Ordre perdu au-dela de 4 id ; alerte de releves revenue ; echec d'endpoint.
        #"{"v":1,"t":"ordre","n":9,"ms":9,"lampe":4,"issue":"confirme","delai_ms":1210,"essai":2,"ids":[5,6,7,8],"ids_perdus":2}"#,
        #"{"v":1,"t":"alerte","n":10,"ms":10,"quoi":"releves","lampe":4,"manque":false,"part":96}"#,
        #"{"v":1,"t":"lampe","n":11,"ms":11,"lampe":5,"quoi":"echec","endpoint":null}"#,
        // Trame d'ordre eteint par Thread, avec trames non emises ; adresse d'un autre type.
        #"{"v":1,"t":"trame","n":13,"ms":13,"sens":"tx","quoi":"ordre","lampe":16,"marche":false,"intensite":null,"essai":3,"sautes":9}"#,
        #"{"v":1,"t":"reseau","n":14,"ms":14,"bloc":"ip","srp":null,"adresses":[{"type":"autre","adresse":"fd12:34:5678:0:aaaa:bbbb:ccc:dddd"}],"udp":{"port":5480,"cle":true,"empreinte":"1A2B3C4D","ouvert":false,"sessions":2,"recus":1,"emis":2,"rejets":0,"perdus":5}}"#,
        // Lampe avec ses versions (fiche des lampes).
        #"{"v":1,"t":"config","n":16,"ms":16,"bloc":"lampe","lampe":1,"adresse":"0002","mac":"020000000001","nom":"Lampe bureau","code":40065,"modele":"amaran COB 60d","catalogue":true,"capacites":["intensite"],"type":"variable","logiciel":"1.4","ble":"1.69"}"#,
        // Session distante en trames et journal.
        #"{"v":1,"t":"hello","n":15,"ms":15,"bloc":"base","rev":1,"session":{"transport":"udp","periode_ms":0,"lampes_ms":0,"compteurs_ms":5000,"reseau_ms":0,"bail_s":120,"log":true,"trames":true}}"#,
        // Reponse complete : msg, suite aucune, lampe, bail.
        #"{"v":1,"t":"reponse","n":12,"ms":12,"id":17,"etape":"fin","cmd":"json ping","ok":true,"code":"ok","msg":"bail renouvele","duree_ms":1,"suite":"aucune","lampe":3,"bail_s":30,"up_s":90}"#,
    ]
}

@Suite("Couverture des cles (section 8)")
struct CouvertureClesTests {
    @Test(arguments: (try? ExemplesSpec.lignes()) ?? [])
    func chaqueChampDesExemplesEstLu(_ json: String) throws {
        let perdus = try CouvertureCles.perdus(json)
        #expect(perdus.isEmpty, "champs perdus au decodage : \(perdus)")
    }

    @Test(arguments: CouvertureCles.synthetiques)
    func chaqueChampHorsExemplesEstLu(_ json: String) throws {
        let perdus = try CouvertureCles.perdus(json)
        #expect(perdus.isEmpty, "champs perdus au decodage : \(perdus)")
    }

    /// A distance, le bloc `matter` porte `code_manuel` et `qr` a null (5.5, 10.1) : rien de
    /// secret ne passe par Thread. Le bloc se decode, et le reste de ses champs avec.
    @Test func matterADistanceSansCodes() throws {
        let json = #"{"v":1,"t":"reseau","n":15,"ms":83622,"bloc":"matter","demarre":true,"fabriques":1,"ble":false,"identifie":false,"abonnements":{"demandes":2,"plafonnes":2,"etablis":2,"termines":1,"plafond_s":20},"code_manuel":null,"qr":null}"#
        #expect(try CouvertureCles.perdus(json).isEmpty)
        var r = RecepteurLignes()
        guard case .machine(let l)? = r.alimenter(ligneMachine(json)).first, case .reseauMatter(let m) = l.message else {
            Issue.record("bloc matter attendu")
            return
        }
        #expect(m.codeManuel == nil && m.qr == nil)
        #expect(m.fabriques == 1 && m.abonnements?.actifs == 1)
        var e = EtatPont()
        e.appliquer(l, recueA: Date())
        #expect(e.enService == true)
        #expect(e.matter?.valeur.codeManuel == nil)
    }

    @Test func leTestVoitUneCleMalNommee() throws {
        // Temoin : un champ inconnu du modele est bien signale.
        let perdus = try CouvertureCles.perdus(#"{"v":1,"t":"lampe","n":1,"ms":1,"lampe":1,"quoi":"entree","champ_futur":3}"#)
        #expect(perdus == ["champFutur"])
    }

    @Test func etapeInconnueDecodeeEtIgnoree() throws {
        var r = RecepteurLignes()
        let e = r.alimenter(ligneMachine(#"{"v":1,"t":"reponse","n":1,"ms":1,"id":1,"etape":"progression","cmd":"mesh","ok":true,"code":"en_cours"}"#))
        guard case .machine(let l) = e.first, case .reponse(let rep) = l.message else {
            Issue.record("reponse attendue : \(e)")
            return
        }
        #expect(rep.etape == .inconnu)
        var c = Correlateur()
        _ = c.soumettre("mesh", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.recevoir(rep, maintenant: 0.1) == .inattendue)
        #expect(c.enVol != nil)
    }
}
