// Repris de Halo Compagnon (commit e114cd5) : l'evenement ordre et le bloc sante du pont amaran.
import Foundation
import Testing
@testable import AmaranProtocole

func texte(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

func reponse(_ id: Int, _ etape: EtapeReponse = .fin, code: CodeReponse = .ok, ok: Bool = true,
             suite: SuiteReponse? = nil, lampe: Int? = nil, cmd: String? = nil) -> Reponse {
    Reponse(id: id, etape: etape, cmd: cmd, ok: ok, code: code, dureeMs: 1, suite: suite, lampe: lampe)
}

func ordre(lampe: Int, _ issue: IssueOrdre, ids: [Int], perdus: Int = 0) -> EvenementOrdre {
    EvenementOrdre(lampe: lampe, issue: issue, delaiMs: 410, essai: 1, ids: ids, idsPerdus: perdus)
}

@Suite("Correlation des commandes (6.2 a 6.4)")
struct CorrelateurTests {
    @Test func uneSeuleCommandeEnVol() throws {
        var c = Correlateur()
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        let b = c.soumettre("lampe 1 niveau 500", origine: .interface, maintenant: 0)
        let p1 = c.prochainEnvoi(maintenant: 0)
        let e1 = try #require(p1)
        #expect(e1.id == a)
        #expect(texte(e1.octets) == "id=1 lampe 1 on\n")
        #expect(c.prochainEnvoi(maintenant: 0.1) == nil, "une seule commande en vol")

        #expect(c.recevoir(reponse(1, code: .accepte, suite: .ordre, lampe: 1), maintenant: 0.2)
                    == .fin(a, ordreAttendu: true))
        #expect(c.suivi(a)?.etat == .attenteOrdre)
        #expect(c.suivi(a)?.lampe == 1)
        let p2 = c.prochainEnvoi(maintenant: 0.2)
        let e2 = try #require(p2)
        #expect(e2.id == b)
        #expect(texte(e2.octets) == "id=2 lampe 1 niveau 500\n")
    }

    @Test func ordreCouvreLesOrdresDeSaLampe() throws {
        var c = Correlateur()
        let a = c.soumettre("lampe 1 niveau 100", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(reponse(1, code: .accepte, suite: .ordre, lampe: 1), maintenant: 0)
        let b = c.soumettre("lampe 1 niveau 150", origine: .interface, maintenant: 0.1)
        _ = c.prochainEnvoi(maintenant: 0.1)
        _ = c.recevoir(reponse(2, code: .accepte, suite: .ordre, lampe: 1), maintenant: 0.1)
        let autre = c.soumettre("lampe 2 on", origine: .interface, maintenant: 0.2)
        _ = c.prochainEnvoi(maintenant: 0.2)
        _ = c.recevoir(reponse(3, code: .accepte, suite: .ordre, lampe: 2), maintenant: 0.2)
        let d = c.soumettre("mesh releve 2", origine: .interface, maintenant: 0.3)
        _ = c.prochainEnvoi(maintenant: 0.3)
        _ = c.recevoir(reponse(4), maintenant: 0.3)

        // Le pont fond les ordres d'une lampe : l'evenement porte les id en attente
        // (ici 1 est sorti de sa liste : ids_perdus). La lampe 2 n'est pas touchee.
        let touches = c.recevoir(ordre(lampe: 1, .confirme, ids: [2], perdus: 1), maintenant: 1)
        #expect(Set(touches) == [a, b])
        #expect(c.suivi(a)?.etat == .confirmee)
        #expect(c.suivi(b)?.etat == .confirmee)
        #expect(c.suivi(b)?.ordre?.delaiMs == 410)
        #expect(c.suivi(autre)?.etat == .attenteOrdre, "un ordre d'une autre lampe reste en attente")
        #expect(c.suivi(d)?.etat == .terminee, "pas un ordre : rien a attendre")
        // Un ordre de Maison (ids vides) ne touche rien.
        #expect(c.recevoir(ordre(lampe: 2, .abandon, ids: []), maintenant: 2).isEmpty)
        #expect(c.recevoir(ordre(lampe: 2, .confirme, ids: [3]), maintenant: 3) == [autre])
    }

    @Test func abandonEtDejaTenu() {
        var c = Correlateur()
        let a = c.soumettre("lampe 2 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(reponse(1, code: .accepte, suite: .ordre, lampe: 2), maintenant: 0)
        c.recevoir(ordre(lampe: 2, .abandon, ids: [1]), maintenant: 5)
        #expect(c.suivi(a)?.etat == .abandonnee)
        #expect(c.suivi(a)?.ordre?.issue == .abandon)

        let b = c.soumettre("lampe 2 off", origine: .interface, maintenant: 6)
        _ = c.prochainEnvoi(maintenant: 6)
        _ = c.recevoir(reponse(2, code: .accepte, suite: .ordre, lampe: 2), maintenant: 6)
        c.recevoir(ordre(lampe: 2, .tenu, ids: [2]), maintenant: 6.01)
        #expect(c.suivi(b)?.etat == .tenue)
    }

    @Test func ordrePerduApresDixSecondes() {
        var c = Correlateur()
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(reponse(1, code: .accepte, suite: .ordre, lampe: 1), maintenant: 0.1)
        #expect(c.verifierOrdres(maintenant: 10.0).isEmpty)
        #expect(c.verifierOrdres(maintenant: 10.1).map(\.id) == [a])
        #expect(c.suivi(a)?.etat == .ordrePerdu)
    }

    @Test func commandeSecreteJamaisGardee() throws {
        var c = Correlateur()
        let cles = "mesh cles 000102030405060708090A0B0C0D0E0F 101112131415161718191A1B1C1D1E1F"
        let a = c.soumettre(cles, origine: .interface, secret: true, maintenant: 0)
        #expect(c.suivi(a)?.commande == "mesh cles •••••••• ••••••••", "le suivi n'en garde que le masque")
        let envoi = c.prochainEnvoi(maintenant: 0)
        let p = try #require(envoi)
        #expect(texte(p.octets) == "id=1 " + cles + "\n", "la ligne envoyee porte les cles")
        #expect(!c.suivis.contains { $0.commande.contains("0001020304") })
    }

    @Test func sansReponseSousTroisSecondes() throws {
        var c = Correlateur()
        let a = c.soumettre("mesh", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.verifierDelais(maintenant: 2.9).isEmpty)
        let expirees = c.verifierDelais(maintenant: 3.0)
        #expect(expirees.map(\.id) == [a])
        #expect(c.suivi(a)?.etat == .sansReponse)
        #expect(c.enVol == nil, "la suivante peut partir, sans reemission")
        #expect(c.prochainEnvoi(maintenant: 3) == nil)
        // Une reponse tardive met encore le suivi a jour.
        _ = c.recevoir(reponse(1, code: .erreur, ok: false), maintenant: 4)
        #expect(c.suivi(a)?.etat == .terminee)
    }

    @Test func commandeHistoriqueEtTexteRattache() throws {
        var c = Correlateur()
        let a = c.soumettre("mesh", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.recevoir(reponse(1, .debut, code: .enCours), maintenant: 0.01) == .debut(a))
        #expect(c.texte("mesh pret : oui") == a)
        #expect(c.commandeDeBanc?.id == a)
        // Apres debut : pas de verdict de silence, meme longtemps apres.
        #expect(c.verifierDelais(maintenant: 600).isEmpty)
        _ = c.recevoir(reponse(1, .fin, code: .ok), maintenant: 601)
        #expect(c.suivi(a)?.texte == ["mesh pret : oui"])
        #expect(c.suivi(a)?.etat == .terminee)
        #expect(c.texte("apres") == nil)
    }

    @Test func fusionDesCurseurs() throws {
        var c = Correlateur()
        _ = c.soumettre("json ping", origine: .session, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        let v1 = c.soumettre("lampe 1 niveau 100", origine: .interface, fusion: "niveau1", maintenant: 0.1)
        let v2 = c.soumettre("lampe 1 niveau 120", origine: .interface, fusion: "niveau1", maintenant: 0.2)
        let t = c.soumettre("lampe 2 niveau 300", origine: .interface, fusion: "niveau2", maintenant: 0.3)
        #expect(c.suivi(v1)?.etat == .remplacee)
        #expect(c.enFile == 2)
        _ = c.recevoir(reponse(1), maintenant: 0.4)
        let p1 = c.prochainEnvoi(maintenant: 0.4)
        #expect(p1?.id == v2)
        _ = c.recevoir(reponse(2), maintenant: 0.5)
        let p2 = c.prochainEnvoi(maintenant: 0.5)
        #expect(p2?.id == t)
    }

    @Test func reponseInattendueEtReinitialisation() throws {
        var c = Correlateur()
        #expect(c.recevoir(reponse(42), maintenant: 0) == .inattendue)
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        let b = c.soumettre("lampe 1 off", origine: .interface, maintenant: 0)
        c.reinitialiser(maintenant: 1)
        #expect(c.suivi(a)?.etat == .perdue)
        #expect(c.suivi(b)?.etat == .perdue)
        #expect(c.enVol == nil)
        // Les numeros ne repartent pas a 1 : un ordre tardif de l'ancienne
        // connexion (ids [1]) ne doit pas tomber sur une commande neuve.
        _ = c.soumettre("lampe 1 niveau 300", origine: .interface, maintenant: 2)
        let p = c.prochainEnvoi(maintenant: 2)
        #expect(p.map { texte($0.octets) } == "id=2 lampe 1 niveau 300\n")
        _ = c.recevoir(reponse(2, code: .accepte, suite: .ordre, lampe: 1), maintenant: 2.1)
        #expect(c.recevoir(ordre(lampe: 1, .confirme, ids: [1]), maintenant: 2.2).isEmpty)
    }

    @Test func etapeInconnueNeClotRien() throws {
        var c = Correlateur()
        let a = c.soumettre("mesh", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.recevoir(reponse(1, .inconnu, code: .enCours), maintenant: 0.1) == .inattendue)
        #expect(c.suivi(a)?.etat == .envoyee, "une etape future ne vaut pas fin")
        #expect(c.enVol == a, "la place en vol reste prise")
        let b = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0.2)
        #expect(c.prochainEnvoi(maintenant: 0.2) == nil)
        _ = c.recevoir(reponse(1, .fin, code: .ok), maintenant: 0.3)
        #expect(c.prochainEnvoi(maintenant: 0.3)?.id == b)
    }

    @Test func auPlusVingtLignesParSeconde() throws {
        var c = Correlateur()
        _ = c.soumettre("json ping", origine: .session, maintenant: 0)
        let b = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(reponse(1), maintenant: 0.01)
        #expect(c.prochainEnvoi(maintenant: 0.02) == nil, "50 ms au moins entre deux lignes (6.3, cadence)")
        #expect(c.prochainEnvoi(maintenant: 0.05)?.id == b)
    }

    @Test func debutTardifBloqueLaFile() throws {
        var c = Correlateur()
        let banc = c.soumettre("mesh iv cherche", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.verifierDelais(maintenant: 3).map(\.id) == [banc])
        let etat = c.soumettre("json etat", origine: .session, maintenant: 3)
        _ = c.prochainEnvoi(maintenant: 3)
        // Le debut arrive apres le verdict "sans reponse" : la console du pont est occupee.
        #expect(c.recevoir(reponse(1, .debut, code: .enCours), maintenant: 3.5) == .debut(banc))
        #expect(c.commandeDeBanc?.id == banc)
        #expect(c.occupe)
        #expect(c.texte("recherche de l'IV Index...") == banc, "le texte va a la commande en cours")
        let suivante = c.soumettre("lampe 1 on", origine: .interface, maintenant: 4)
        _ = c.verifierDelais(maintenant: 6)  // json etat sans reponse : la console du pont ne lit plus
        #expect(c.suivi(etat)?.etat == .sansReponse)
        #expect(c.prochainEnvoi(maintenant: 60) == nil, "rien ne part pendant la commande")
        _ = c.recevoir(reponse(1, .fin, code: .ok), maintenant: 600)
        #expect(c.commandeDeBanc == nil)
        #expect(c.prochainEnvoi(maintenant: 600)?.id == suivante)
    }

    @Test func finPerdueRattrapeeParLeBlocSante() throws {
        var c = Correlateur()
        let a = c.soumettre("mesh", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(reponse(1, .debut, code: .enCours), maintenant: 0.1)
        let b = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0.2)
        // Le bloc sante porte l'id de la commande en cours : elle tourne encore.
        #expect(c.periodiqueRecu(commande: 1, maintenant: 0.5).isEmpty)
        #expect(c.suivi(a)?.etat == .enCours)
        // La fin est perdue ; le bloc sante suivant ne porte plus son id.
        #expect(c.periodiqueRecu(commande: nil, maintenant: 1) == [a])
        #expect(c.suivi(a)?.etat == .finPerdue)
        #expect(c.prochainEnvoi(maintenant: 1)?.id == b)
    }

    @Test func numerotationBouclee() {
        #expect(LigneCommande.suivant(1) == 2)
        #expect(LigneCommande.suivant(999_999_999) == 1)
    }
}

@Suite("Moteur de session (3.2 a 3.6)")
struct MoteurSessionTests {
    static let hello = #"{"v":1,"t":"hello","n":0,"ms":83512,"bloc":"base","boot":"3FA2C901","up_s":83,"session":{"periode_ms":1000,"lampes_ms":10000,"bail_s":30}}"#

    static func element(_ json: String) -> ElementRecu {
        var r = RecepteurLignes()
        return r.alimenter(ligneMachine(json))[0]
    }

    static func envois(_ effets: [MoteurSession.Effet]) -> [String] {
        effets.compactMap { if case .envoyer(let d) = $0 { return texte(d) } else { return nil } }
    }

    static func finJson1(_ id: Int = 1, n: Int = 11) -> ElementRecu {
        element(#"{"v":1,"t":"reponse","n":\#(n),"ms":83523,"id":\#(id),"etape":"fin","cmd":"json 1","ok":true,"code":"ok","duree_ms":12,"bail_s":30,"up_s":83}"#)
    }

    /// Ouverture, hello puis reponse au json 1 : session etablie, file libre.
    static func connecte(a t: TimeInterval = 0) -> MoteurSession {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: t)
        _ = m.recu(element(hello), maintenant: t)
        _ = m.recu(finJson1(), maintenant: t)
        return m
    }

    @Test func sequenceDeConnexion() {
        var m = MoteurSession()
        let e = m.ouvert(maintenant: 0)
        #expect(Self.envois(e) == ["\u{15}\n", "id=1 json 1\n"])
        #expect(m.phase == .attenteHello(essai: 1))
        #expect(m.historique)
        _ = m.recu(Self.element(Self.hello), maintenant: 0.1)
        #expect(m.phase == .connecte)
        #expect(!m.historique)
        #expect(m.boot == "3FA2C901")
        #expect(m.bailS == 30)
        // Une seule commande en vol (6.5) : rien ne part avant la reponse fin du json 1.
        #expect(m.instantaneEnCours)
        let (_, e1) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 0.15)
        #expect(Self.envois(e1).isEmpty)
        // La reponse au json 1 n'est pas une commande inattendue ; elle libere la file.
        let e2 = m.recu(Self.finJson1(), maintenant: 0.2)
        #expect(m.phase == .connecte)
        #expect(!m.instantaneEnCours)
        #expect(Self.envois(e2) == ["id=2 lampe 1 on\n"])
    }

    @Test func reponseAuJson1SansHelloRenvoieJson1() {
        // hello perdu (json_perdus, coupe par un journal) : la reponse seule n'etablit rien,
        // et json 1 (idempotent) repart 2 s apres le premier envoi.
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.finJson1(), maintenant: 0.4)
        #expect(m.phase == .attenteHello(essai: 1))
        #expect(m.historique)
        #expect(Self.envois(m.tic(maintenant: 2.0)) == ["id=2 json 1\n"])
        _ = m.recu(Self.element(Self.hello), maintenant: 2.1)
        _ = m.recu(Self.finJson1(2, n: 12), maintenant: 2.2)
        #expect(m.phase == .connecte)
        #expect(!m.instantaneEnCours)
    }

    @Test func reponseCadenceAuJson1RenvoieJson1() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":3,"ms":1,"id":1,"etape":"fin","cmd":"json 1","ok":false,"code":"cadence"}"#),
                   maintenant: 0.1)
        #expect(Self.envois(m.tic(maintenant: 2.0)) == ["id=2 json 1\n"])
    }

    @Test func reponseAuJson1PerdueLibereLaFile() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(Self.hello), maintenant: 0.1)
        let (_, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 0.2)
        #expect(Self.envois(e).isEmpty)
        _ = m.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 2.9)
        #expect(Self.envois(m.tic(maintenant: 2.9)).isEmpty)
        #expect(Self.envois(m.tic(maintenant: 3.0)) == ["id=2 lampe 1 on\n"])
    }

    @Test func numerosCroissantsApresReconnexion() {
        var m = MoteurSession()
        #expect(Self.envois(m.ouvert(maintenant: 0)).last == "id=1 json 1\n")
        m.ferme(maintenant: 1)
        #expect(Self.envois(m.ouvert(maintenant: 2)).last == "id=2 json 1\n")
    }

    @Test func pingAuTiersDUnBailCourt() {
        var m2 = MoteurSession()
        _ = m2.ouvert(maintenant: 0)
        _ = m2.recu(Self.element(Self.hello.replacingOccurrences(of: #""bail_s":30"#, with: #""bail_s":10"#)), maintenant: 0)
        _ = m2.recu(Self.element(#"{"v":1,"t":"reponse","n":11,"ms":1,"id":1,"etape":"fin","cmd":"json 1 bail 10","ok":true,"code":"ok","bail_s":10}"#),
                    maintenant: 0)
        #expect(m2.bailS == 10)
        _ = m2.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 3.3)
        #expect(Self.envois(m2.tic(maintenant: 3.3)).isEmpty)
        _ = m2.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 3.4)
        #expect(Self.envois(m2.tic(maintenant: 3.4)) == ["id=2 json ping\n"], "bail de 10 s : ping a 3,3 s")
    }

    @Test func reglagesSuivisDesCommandesJson() {
        var m = Self.connecte()
        #expect(m.reglages.log == false)
        _ = m.soumettre("json log 1", origine: .console, maintenant: 1)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":12,"ms":1,"id":2,"etape":"fin","cmd":"json log 1","ok":true,"code":"ok"}"#), maintenant: 1.1)
        #expect(m.reglages.log == true)
        _ = m.soumettre("json lampes 5000", origine: .console, maintenant: 2)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":13,"ms":1,"id":3,"etape":"fin","cmd":"json lampes 5000","ok":true,"code":"ok"}"#), maintenant: 2.1)
        #expect(m.reglages.lampesMs == 5000)
        // json 1 remet les reglages par defaut : le hello suivant les annonce.
        _ = m.recu(Self.element(Self.hello.replacingOccurrences(of: #""bail_s":30"#, with: #""bail_s":30,"log":false"#)), maintenant: 3)
        #expect(m.reglages.log == false)
        #expect(m.reglages.lampesMs == 10000)
    }

    @Test func redemarragePerdLesOrdresAttendus() throws {
        var m = Self.connecte()
        let (id, _) = m.soumettre("lampe 1 niveau 500", origine: .interface, maintenant: 1)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":12,"ms":1,"id":2,"etape":"fin","cmd":"lampe 1 niveau 500","ok":true,"code":"accepte","suite":"ordre","lampe":1}"#), maintenant: 1.1)
        #expect(m.correlateur.suivi(id)?.etat == .attenteOrdre)
        _ = m.recu(Self.element(#"{"v":1,"t":"hb","n":2,"ms":1000,"boot":"3FA2C901","up_s":1,"json_perdus":0,"commande":null}"#), maintenant: 2)
        #expect(m.correlateur.suivi(id)?.etat == .perdue, "le pont a redemarre : aucun ordre ne viendra")
    }

    @Test func ordreFinitLaCommande() throws {
        var m = Self.connecte()
        let (id, _) = m.soumettre("lampe 1 niveau 500", origine: .interface, maintenant: 1)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":12,"ms":1,"id":2,"etape":"fin","cmd":"lampe 1 niveau 500","ok":true,"code":"accepte","suite":"ordre","lampe":1}"#), maintenant: 1.1)
        _ = m.recu(Self.element(#"{"v":1,"t":"ordre","n":13,"ms":1410,"lampe":1,"issue":"confirme","delai_ms":410,"essai":1,"ids":[2],"ids_perdus":0}"#), maintenant: 1.5)
        #expect(m.correlateur.suivi(id)?.etat == .confirmee)
    }

    @Test func debutTardifSuspendSilenceEtPing() {
        var m = Self.connecte()
        let (banc, e) = m.soumettre("mesh iv cherche", origine: .console, maintenant: 0.1)
        #expect(Self.envois(e) == ["id=2 mesh iv cherche\n"])
        _ = m.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 3.0)
        // Pas de reponse sous 3 s : "sans reponse", json etat demande.
        #expect(Self.envois(m.tic(maintenant: 3.1)) == ["id=3 json etat\n"])
        // Le debut arrive enfin : la console du pont est occupee.
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":12,"ms":1,"id":2,"etape":"debut","cmd":"mesh iv cherche","ok":true,"code":"en_cours"}"#), maintenant: 3.5)
        #expect(m.correlateur.commandeDeBanc?.id == banc)
        for t in stride(from: 4.0, through: 900, by: 7) {
            #expect(Self.envois(m.tic(maintenant: t)).isEmpty, "ni json 1 de silence, ni ping, ni commande (t = \(t))")
        }
        #expect(m.phase == .connecte)
        // La fin s'est perdue : un bloc sante sans son id la clot.
        _ = m.recu(Self.element(#"{"v":1,"t":"etat","n":40,"ms":9,"bloc":"sante","boot":"3FA2C901","up_s":990,"commande":null}"#), maintenant: 990)
        #expect(m.correlateur.suivi(banc)?.etat == .finPerdue)
        #expect(!m.correlateur.occupe)
    }

    @Test func renvoisDuJson1PuisSansReponse() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        #expect(Self.envois(m.tic(maintenant: 1.9)).isEmpty)
        #expect(Self.envois(m.tic(maintenant: 2.0)) == ["id=2 json 1\n"])
        #expect(Self.envois(m.tic(maintenant: 4.0)) == ["id=3 json 1\n"])
        #expect(Self.envois(m.tic(maintenant: 6.0)) == ["id=4 json 1\n"])
        #expect(m.phase == .attenteHello(essai: 4))
        let e = m.tic(maintenant: 8.0)
        #expect(Self.envois(e).isEmpty)
        #expect(m.phase == .sansReponse)
        // Puis \x15\n et json 1 toutes les 30 s, pas plus souvent.
        #expect(Self.envois(m.tic(maintenant: 30)).isEmpty)
        #expect(Self.envois(m.tic(maintenant: 36.0)) == ["\u{15}\n", "id=5 json 1\n"])
        _ = m.recu(Self.element(Self.hello), maintenant: 37)
        #expect(m.phase == .connecte)
    }

    @Test func ancienFirmware() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        let e = m.recu(.texte(ClasseurTexte.classer("Unrecognized command")), maintenant: 0.1)
        #expect(m.phase == .ancienFirmware)
        #expect(e.contains(.note(.ancienFirmware)))
        #expect(MoteurSession.Note.ancienFirmware.grave, "montree en bandeau")
        #expect(Self.envois(m.tic(maintenant: 60)).isEmpty, "plus de json 1 vers un ancien firmware")
    }

    @Test func versionInconnue() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(.versionInconnue(v: 2, t: "hello"), maintenant: 0.1)
        #expect(m.phase == .versionInconnue(2))
    }

    @Test func pingApresDixSecondes() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(Self.hello), maintenant: 0.1)
        _ = m.recu(Self.finJson1(), maintenant: 0.2)
        // L'etat periodique arrive : pas de silence.
        for t in stride(from: 1.0, through: 9.0, by: 1.0) {
            _ = m.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: t)
            #expect(Self.envois(m.tic(maintenant: t)).isEmpty)
        }
        _ = m.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 10)
        #expect(Self.envois(m.tic(maintenant: 10)) == ["id=2 json ping\n"])
    }

    @Test func silencePuisReouverture() {
        var m = Self.connecte()
        // Une commande partie juste avant le silence : elle est perdue avec la session.
        let (enVol, _) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 5)
        // 3 x max(1 s, 2 s) = 6 s sans aucune ligne.
        #expect(Self.envois(m.tic(maintenant: 5.9)).isEmpty)
        let e = m.tic(maintenant: 6.0)
        #expect(Self.envois(e) == ["id=3 json 1\n"])
        #expect(m.phase == .resynchro)
        #expect(m.correlateur.suivi(enVol)?.etat == .perdue)
        #expect(m.correlateur.enVol == nil)
        let r = m.tic(maintenant: 11.0)
        #expect(r.contains { if case .rouvrir = $0 { return true } else { return false } })
    }

    @Test func pasDeSilencePendantUneCommandeDeBanc() {
        var m = Self.connecte()
        let (_, e) = m.soumettre("mesh iv cherche", origine: .console, maintenant: 0.1)
        #expect(Self.envois(e) == ["id=2 mesh iv cherche\n"])
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":1,"ms":1,"id":2,"etape":"debut","cmd":"mesh iv cherche","ok":true,"code":"en_cours"}"#), maintenant: 0.1)
        #expect(Self.envois(m.tic(maintenant: 300)).isEmpty)
        #expect(m.phase == .connecte)
        let long = m.tic(maintenant: 20 * 60 + 1)
        #expect(long.contains(.proposerFermeture))
    }

    @Test func commandeSansReponseDemandeUnInstantane() {
        var m = Self.connecte()
        let (id, _) = m.soumettre("mesh", origine: .interface, maintenant: 1)
        _ = m.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 3.5)
        let e = m.tic(maintenant: 4.0)
        #expect(e.contains(.commandeSansReponse(id)))
        #expect(Self.envois(e) == ["id=3 json etat\n"])
    }

    @Test func redemarrageParBootOuUpS() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(Self.hello), maintenant: 0)
        let hb = #"{"v":1,"t":"hb","n":1,"ms":90000,"boot":"3FA2C901","up_s":90,"json_perdus":0,"commande":null}"#
        #expect(m.recu(Self.element(hb), maintenant: 1).isEmpty)
        // up_s qui recule, meme boot : redemarrage, json 1 renvoye.
        let e = m.recu(Self.element(#"{"v":1,"t":"hb","n":2,"ms":1000,"boot":"3FA2C901","up_s":1,"json_perdus":0,"commande":null}"#),
                       maintenant: 2)
        #expect(e.contains(.redemarrage(ancien: "3FA2C901", nouveau: "3FA2C901")))
        #expect(Self.envois(e) == ["id=2 json 1\n"])
        // Nouveau boot au hello suivant : redemarrage signale, pas de json 1 de plus.
        let h = m.recu(Self.element(Self.hello.replacingOccurrences(of: "3FA2C901", with: "0BADCAFE")), maintenant: 3)
        #expect(h.contains(.redemarrage(ancien: "3FA2C901", nouveau: "0BADCAFE")))
        #expect(Self.envois(h).isEmpty)
        #expect(m.statistiques.redemarrages == 2)
    }

    @Test func finDeBailPuisJson1() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(Self.hello), maintenant: 0)
        let e = m.recu(Self.element(#"{"v":1,"t":"fin","n":662,"ms":231400,"cause":"bail"}"#), maintenant: 5)
        #expect(Self.envois(e) == ["id=2 json 1\n"])
        #expect(m.phase == .attenteHello(essai: 1))
    }

    @Test func libererLePort() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(Self.hello), maintenant: 0)
        #expect(Self.envois(m.liberer(maintenant: 1)) == ["id=2 json 0\n"])
        #expect(m.phase == .ferme)
    }

    @Test func periodeSuivieParLeSeuilDeSilence() {
        var m = Self.connecte()
        _ = m.soumettre("json periode 5000", origine: .console, maintenant: 0.1)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":1,"ms":1,"id":2,"etape":"fin","cmd":"json periode 5000","ok":true,"code":"ok"}"#), maintenant: 0.2)
        #expect(m.periodeMs == 5000)
        // 3 x 5 s = 15 s de silence toleres (ping a 10 s compris).
        _ = m.tic(maintenant: 10.2)
        #expect(m.phase == .connecte)
    }
}
