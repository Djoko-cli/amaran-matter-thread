// Repris de Halo Compagnon (HaloProtocoleTests/ReseauSessionTests.swift) : les regles du
// reseau (docs/PROTOCOLE-JSON.md 10.4, 10.5) pour le pont amaran : json 1 avec un bail
// permis a distance, texte en messages `texte`, reponse `deja_traite` (reponse oubliee),
// `ordre` arrive sans son `accepte`.
import Foundation
import Testing
@testable import AmaranProtocole

@Suite("Correlation a distance (10.4)")
struct CorrelationReseauTests {
    @Test func renvoisDuMemeIdPuisSansReponse() throws {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        let p = c.prochainEnvoi(maintenant: 0)
        let e = try #require(p)
        #expect(texte(e.octets) == "id=1 lampe 1 on\n")
        #expect(c.renvoisDus(maintenant: 1.9).isEmpty)
        #expect(c.renvoisDus(maintenant: 2.0).map(texte) == ["id=1 lampe 1 on\n"])
        #expect(c.renvoisDus(maintenant: 3.9).isEmpty)
        #expect(c.renvoisDus(maintenant: 4.0).map(texte) == ["id=1 lampe 1 on\n"])
        #expect(c.renvoisDus(maintenant: 5.9).isEmpty, "deux renvois au plus")
        #expect(c.verifierDelais(maintenant: 5.9).isEmpty)
        #expect(c.verifierDelais(maintenant: 6.0).map(\.id) == [a])
        #expect(c.suivi(a)?.etat == .sansReponse)
        #expect(c.suivi(a)?.renvois == 2)
    }

    @Test func reponseArreteLesRenvoisEtDoublonIgnore() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("json ping", origine: .session, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.renvoisDus(maintenant: 2)
        #expect(c.recevoir(reponse(1), maintenant: 2.3) == .fin(a, ordreAttendu: false))
        #expect(c.renvoisDus(maintenant: 4).isEmpty)
        #expect(c.recevoir(reponse(1), maintenant: 2.4) == .inattendue, "reponse rendue de nouveau par le pont : ignoree")
    }

    /// Un renvoi croise la reponse `accepte` : le pont rend la reponse gardee, sans
    /// executer l'ordre une seconde fois. Le doublon ne relance pas l'attente de l'ordre.
    @Test func doublonDAccepteSansEffet() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampe 2 niveau 300", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.renvoisDus(maintenant: 2)
        let accepte = reponse(1, code: .accepte, suite: .ordre, lampe: 2)
        #expect(c.recevoir(accepte, maintenant: 2.1) == .fin(a, ordreAttendu: true))
        #expect(c.recevoir(accepte, maintenant: 2.2) == .inattendue)
        #expect(c.suivi(a)?.termineeA == 2.1)
        #expect(c.verifierOrdres(maintenant: 12.1).map(\.id) == [a], "l'ordre garde son delai de 10 s")
    }

    static let dejaTraite = Reponse(id: 1, etape: .fin, cmd: "lampe 1 on", ok: false, code: .dejaTraite,
                                    msg: "id deja traite : reponse oubliee", dureeMs: 0)

    /// `deja_traite` (10.4) : le pont a oublie la reponse de cet `id`, la vraie ne viendra
    /// jamais (le renvoi d'un `id` encore en cours, lui, est ignore en silence). Le suivi
    /// se clot comme sur une `fin`, la place en vol se libere, plus aucun renvoi.
    @Test func dejaTraiteClotLeSuivi() throws {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        let b = c.soumettre("lampe 2 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.renvoisDus(maintenant: 2).count == 1)
        #expect(c.recevoir(Self.dejaTraite, maintenant: 2.2) == .fin(a, ordreAttendu: false))
        #expect(c.suivi(a)?.etat == .terminee)
        #expect(c.suivi(a)?.fin?.code == .dejaTraite)
        #expect(c.enVol == nil, "la file repart : aucune autre reponse ne viendra pour cet id")
        #expect(c.renvoisDus(maintenant: 2.25).isEmpty, "plus de renvoi")
        let p = c.prochainEnvoi(maintenant: 2.3)
        #expect(try #require(p).id == b, "la commande suivante part aussitot")
        #expect(c.recevoir(Self.dejaTraite, maintenant: 2.4) == .inattendue, "un second deja_traite : ignore")
        _ = c.verifierDelais(maintenant: 8.3)
        #expect(c.suivi(a)?.etat == .terminee, "jamais « sans reponse » ensuite")
    }

    /// Un `deja_traite` qui arrive apres le verdict « sans reponse » clot aussi le suivi.
    @Test func dejaTraiteApresSansReponseClotLeSuivi() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("json ping", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.verifierDelais(maintenant: 6)
        #expect(c.suivi(a)?.etat == .sansReponse)
        let deja = Reponse(id: 1, etape: .fin, ok: false, code: .dejaTraite)
        #expect(c.recevoir(deja, maintenant: 6.5) == .fin(a, ordreAttendu: false))
        #expect(c.suivi(a)?.etat == .terminee)
        #expect(c.suivi(a)?.fin?.code == .dejaTraite)
    }

    /// Une reponse `accepte` perdue sur Thread : l'evenement `ordre` qui porte l'`id` prouve
    /// l'acceptation. Il finit la commande encore `envoyee` et libere la place en vol ; la
    /// reponse gardee, rendue plus tard a un renvoi qui a croise l'evenement, est ignoree.
    @Test func ordreSansAccepteFinitLaCommande() throws {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        let b = c.soumettre("lampe 2 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.recevoir(ordre(lampe: 1, .confirme, ids: [1]), maintenant: 0.4) == [a])
        #expect(c.suivi(a)?.etat == .confirmee)
        #expect(c.suivi(a)?.lampe == 1)
        #expect(c.enVol == nil)
        #expect(c.renvoisDus(maintenant: 2).isEmpty, "rien a renvoyer")
        let p = c.prochainEnvoi(maintenant: 0.5)
        #expect(try #require(p).id == b)
        #expect(c.recevoir(reponse(1, code: .accepte, suite: .ordre, lampe: 1), maintenant: 2.1) == .inattendue)
        #expect(c.suivi(a)?.etat == .confirmee)
        #expect(c.verifierOrdres(maintenant: 12.5).isEmpty, "jamais « issue perdue »")
        // Un evenement ne finit que les commandes dont il porte l'id.
        #expect(c.recevoir(ordre(lampe: 2, .abandon, ids: [7]), maintenant: 3).isEmpty)
        #expect(c.suivi(b)?.etat == .envoyee)
    }

    /// Meme chose apres le verdict « sans reponse » : l'evenement donne la vraie issue.
    @Test func ordreApresSansReponseFinitLaCommande() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampe 3 niveau 200", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.verifierDelais(maintenant: 6)
        #expect(c.suivi(a)?.etat == .sansReponse)
        #expect(c.recevoir(ordre(lampe: 3, .abandon, ids: [1]), maintenant: 6.2) == [a])
        #expect(c.suivi(a)?.etat == .abandonnee)
        #expect(c.suivi(a)?.ordre?.issue == .abandon)
    }

    /// Le texte d'une commande a distance arrive en messages `texte` qui portent son id.
    @Test func texteADistanceRattacheParId() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("mesh", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.recevoir(reponse(1, .debut, code: .enCours), maintenant: 0.1) == .debut(a))
        #expect(c.texte("mesh pret : oui", id: 1, maintenant: 0.2) == a)
        #expect(c.texte("autre commande", id: 7, maintenant: 0.2) == nil, "id inconnu : ignore")
        _ = c.recevoir(reponse(1), maintenant: 0.3)
        #expect(c.suivi(a)?.texte == ["mesh pret : oui"])
        #expect(c.texte("apres la fin", id: 1, maintenant: 0.4) == nil)
    }

    /// `debut` perdu : le premier `texte` en tient lieu. Le pont execute la commande :
    /// ni renvoi (il l'ignorerait : la commande est en cours), ni "sans reponse".
    @Test func texteSansDebutTientLieuDeDebut() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampes", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.texte("lampe 1 : Lampe bureau", id: 1, maintenant: 0.5) == a)
        #expect(c.suivi(a)?.etat == .enCours)
        #expect(c.suivi(a)?.debutA == 0.5)
        #expect(c.renvoisDus(maintenant: 2).isEmpty)
        #expect(c.verifierDelais(maintenant: 6).isEmpty)
        #expect(c.commandeDeBanc?.id == a)
        _ = c.recevoir(reponse(1), maintenant: 6.5)
        #expect(c.suivi(a)?.etat == .terminee)
        #expect(c.suivi(a)?.texte == ["lampe 1 : Lampe bureau"])
    }

    @Test func texteTardifApresSansReponse() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("taches", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.verifierDelais(maintenant: 6)
        #expect(c.texte("json 1460", id: 1, maintenant: 7) == a)
        #expect(c.suivi(a)?.etat == .enCours, "comme un debut tardif : la commande tourne")
        #expect(c.suivi(a)?.termineeA == nil)
    }

    /// La ligne d'une commande secrete est oubliee des son envoi : elle ne repart jamais
    /// (le masque partirait a sa place).
    @Test func commandeSecreteJamaisRenvoyee() throws {
        var c = Correlateur()
        c.politique = .reseau
        let cles = "mesh cles 404142434445464748494A4B4C4D4E4F 505152535455565758595A5B5C5D5E5F"
        _ = c.soumettre(cles, origine: .interface, secret: true, maintenant: 0)
        let p = c.prochainEnvoi(maintenant: 0)
        #expect(try #require(p).numero == 1)
        #expect(c.renvoisDus(maintenant: 2).isEmpty)
        #expect(c.renvoisDus(maintenant: 4).isEmpty)
    }

    @Test func usbSansRenvoi() {
        var c = Correlateur()
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.renvoisDus(maintenant: 2.5).isEmpty)
        #expect(c.verifierDelais(maintenant: 3).map(\.id) == [a])
    }

    @Test func politiques() {
        #expect(PolitiqueDelais.pour(.udp) == .reseau)
        #expect(PolitiqueDelais.pour(.usb) == .usb)
        #expect(PolitiqueDelais.pour(.demo) == .usb)
        #expect(PolitiqueDelais.reseau.delaiOrdre == PolitiqueDelais.usb.delaiOrdre, "les ordres gardent leur delai")
        #expect(PolitiqueDelais.reseau.delaiInstantane == 12)
        #expect(MoteurSession.Parametres().delaiFinJson1Reseau == PolitiqueDelais.reseau.delaiInstantane,
                "json 1, json etat et json hello : meme attente a distance")
        #expect(PolitiqueDelais.usb.delaiReponse(pour: "json etat") == 3, "par l'USB, l'instantane part en moins d'une demi-seconde")
    }

    /// `json 1`, `json etat`, `json hello` : leur `fin` suit l'instantane (6.2), lu comme le
    /// pont decoupe la ligne ; aucune autre commande.
    @Test func commandesQuiRepondentApresLInstantane() {
        for c in ["json etat", "json hello", "json 1", "json 1 bail 60", #""json" etat"#, #"js\xon hello"#, "  json etat  "] {
            #expect(PolitiqueCommandes.repondApresInstantane(c), "\(c)")
        }
        for c in ["json ping", "json etat x", "json", "lampe 1 on", "JSON etat", "json trames 1", "mesh"] {
            #expect(!PolitiqueCommandes.repondApresInstantane(c), "\(c)")
        }
    }

    /// A distance, la `fin` de `json etat` part apres l'instantane : attendue 12 s, comme
    /// celle du `json 1`. Les renvois du meme `id` a 2 s et 4 s restent (le pont ignore le
    /// renvoi d'un `id` encore en cours). Une autre commande garde ses 6 s.
    @Test func instantaneAttenduDouzeSecondesADistance() {
        for commande in ["json etat", "json hello", "json 1 bail 60"] {
            var c = Correlateur()
            c.politique = .reseau
            let a = c.soumettre(commande, origine: .console, maintenant: 0)
            _ = c.prochainEnvoi(maintenant: 0)
            #expect(c.renvoisDus(maintenant: 2).count == 1, "\(commande) : renvoi a 2 s")
            #expect(c.renvoisDus(maintenant: 4).count == 1, "\(commande) : renvoi a 4 s")
            #expect(c.verifierDelais(maintenant: 6).isEmpty, "\(commande) : pas « sans reponse » a 6 s")
            #expect(c.verifierDelais(maintenant: 11.9).isEmpty)
            #expect(c.verifierDelais(maintenant: 12).map(\.id) == [a], "\(commande) : « sans reponse » a 12 s")
        }
        var autre = Correlateur()
        autre.politique = .reseau
        let b = autre.soumettre("lampes", origine: .console, maintenant: 0)
        _ = autre.prochainEnvoi(maintenant: 0)
        #expect(autre.verifierDelais(maintenant: 6).map(\.id) == [b], "une lecture garde ses 6 s")
        var usb = Correlateur()
        let u = usb.soumettre("json etat", origine: .interface, maintenant: 0)
        _ = usb.prochainEnvoi(maintenant: 0)
        #expect(usb.verifierDelais(maintenant: 3).map(\.id) == [u], "USB : inchange, 3 s")
    }
}

@Suite("Session par le reseau (10.4, 10.5)")
struct ReseauSessionTests {
    typealias M = MoteurSessionTests

    static let helloDistant = #"{"v":1,"t":"hello","n":0,"ms":900120,"bloc":"base","rev":1,"boot":"3FA2C901","up_s":900,"session":{"transport":"udp","periode_ms":2000,"lampes_ms":30000,"compteurs_ms":0,"reseau_ms":30000,"bail_s":60,"log":false,"trames":false}}"#

    static func finJson1(_ id: Int = 1, n: Int = 11, code: String = "ok") -> ElementRecu {
        let ok = code == "ok" ? "true" : "false"
        return M.element(#"{"v":1,"t":"reponse","n":\#(n),"ms":900200,"id":\#(id),"etape":"fin","cmd":"json 1 bail 60","ok":\#(ok),"code":"\#(code)","duree_ms":80,"bail_s":60,"up_s":900}"#)
    }

    static func connecte() -> MoteurSession {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        _ = m.recu(M.element(helloDistant), maintenant: 0.1)
        _ = m.recu(finJson1(), maintenant: 0.2)
        return m
    }

    @Test func ouvertureReseauSansCtrlUAvecUnBailPermis() {
        var m = MoteurSession()
        #expect(M.envois(m.ouvert(maintenant: 0, genre: .udp)) == ["id=1 json 1 bail 60\n"])
        #expect(PolitiqueCommandes.autoriseeADistance("json 1 bail 60") == nil)
        #expect(m.correlateur.politique == .reseau)
        #expect(m.genre == .udp)
        #expect(m.reglages == HelloBase.ReglagesSession(transport: .udp, periodeMs: 2000, lampesMs: 30000, compteursMs: 0,
                                                        reseauMs: 30000, bailS: 60, log: false, trames: false),
                "profil distant (10.5) avant le hello")
        var u = MoteurSession()
        #expect(M.envois(u.ouvert(maintenant: 0)) == ["\u{15}\n", "id=1 json 1\n"])
        #expect(u.correlateur.politique == .usb)
        #expect(u.reglages.transport == .usb && u.reglages.periodeMs == 1000)
    }

    @Test func bailDistantToujoursDansLesBornes() {
        for (demande, attendu) in [(0, 10), (5, 10), (60, 60), (120, 120), (600, 120)] {
            var m = MoteurSession()
            m.parametres.bailDistantS = demande
            #expect(M.envois(m.ouvert(maintenant: 0, genre: .udp)) == ["id=1 json 1 bail \(attendu)\n"])
            #expect(PolitiqueCommandes.autoriseeADistance(m.ligneJson1) == nil)
        }
    }

    @Test func sessionDistanteEtablie() {
        var m = Self.connecte()
        #expect(m.phase == .connecte)
        #expect(!m.instantaneEnCours)
        #expect(m.bailS == 60)
        #expect(m.reglages.transport == .udp)
        let (_, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 0.3)
        #expect(M.envois(e) == ["id=2 lampe 1 on\n"])
    }

    @Test func json1RenvoyeAvecLeMemeIdADistance() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        #expect(M.envois(m.tic(maintenant: 2.0)) == ["id=1 json 1 bail 60\n"], "le pont ne refait pas l'instantane")
        var u = MoteurSession()
        _ = u.ouvert(maintenant: 0)
        #expect(M.envois(u.tic(maintenant: 2.0)) == ["id=2 json 1\n"], "USB : inchange")
    }

    /// `deja_traite` au json 1, avant le hello : la reponse est oubliee (10.4), le meme id
    /// ne rendrait plus rien. Le renvoi suivant prend un id neuf, pour un nouvel instantane.
    @Test func json1DejaTraiteRepartAvecUnIdNeuf() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        #expect(M.envois(m.tic(maintenant: 2.0)) == ["id=1 json 1 bail 60\n"], "renvoi du meme id")
        _ = m.recu(Self.finJson1(code: "deja_traite"), maintenant: 2.5)
        #expect(m.phase == .attenteHello(essai: 2))
        #expect(M.envois(m.tic(maintenant: 4.0)) == ["id=2 json 1 bail 60\n"], "id neuf")
        #expect(M.envois(m.tic(maintenant: 6.0)) == ["id=2 json 1 bail 60\n"], "puis ce nouvel id est renvoye tel quel")
    }

    /// Apres le hello, `deja_traite` au json 1 est sa fin : la file repart, sans attendre
    /// les 12 s du verdict « reponse au json 1 perdue ».
    @Test func json1DejaTraiteApresLeHelloLibereLaFile() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        _ = m.recu(M.element(Self.helloDistant), maintenant: 0.5)
        let (_, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 0.6)
        #expect(M.envois(e).isEmpty, "l'instantane d'abord")
        #expect(M.envois(m.recu(Self.finJson1(code: "deja_traite"), maintenant: 2.5)) == ["id=2 lampe 1 on\n"])
        #expect(!m.instantaneEnCours)
        #expect(!m.tic(maintenant: 12.5).contains(.note(.reponseJson1Perdue)))
    }

    /// Reste du rapport : un `json etat` a distance dont la `fin` arrive 8 s apres l'envoi
    /// (deux instantanes de 16 lampes en meme temps) est conclu « ok », sans verdict « sans
    /// reponse » ni second `json etat`.
    @Test func jsonEtatADistanceAttendSonInstantane() {
        var m = Self.connecte()
        let (a, e) = m.soumettre("json etat", origine: .interface, maintenant: 1)
        #expect(M.envois(e) == ["id=2 json etat\n"])
        var effets: [MoteurSession.Effet] = []
        var t = 1.0
        while t < 9 {
            t += 0.25
            if Int(t * 4) % 6 == 0 { _ = m.recu(M.element(Self.helloDistant), maintenant: t) }  // l'instantane arrive
            effets += m.tic(maintenant: t)
        }
        #expect(M.envois(effets) == ["id=2 json etat\n", "id=2 json etat\n"], "renvois du meme id a 2 s et 4 s, rien d'autre")
        #expect(!effets.contains(.commandeSansReponse(a)))
        effets += m.recu(M.element(#"{"v":1,"t":"reponse","n":90,"ms":908000,"id":2,"etape":"fin","cmd":"json etat","ok":true,"code":"ok","duree_ms":7900}"#), maintenant: 9)
        effets += m.tic(maintenant: 9.25)
        #expect(m.correlateur.suivi(a)?.etat == .terminee)
        #expect(m.correlateur.suivi(a)?.fin?.code == .ok)
        #expect(!effets.contains(.commandeSansReponse(a)))
        #expect(M.envois(effets).filter { $0.hasSuffix(" json etat\n") }.count == 2, "pas de second json etat")
        #expect(m.statistiques.sansReponse == 0)
    }

    /// `deja_traite` d'une commande : sa reponse est oubliee, l'etat a pu changer sans que
    /// l'app le voie ; le moteur demande un instantane, comme Halo.
    @Test func dejaTraiteDemandeUnEtat() {
        var m = Self.connecte()
        let (a, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 1)
        #expect(M.envois(e) == ["id=2 lampe 1 on\n"])
        _ = m.recu(M.element(Self.helloDistant), maintenant: 2.5)
        #expect(M.envois(m.tic(maintenant: 3.0)) == ["id=2 lampe 1 on\n"])
        let deja = M.element(#"{"v":1,"t":"reponse","n":40,"ms":912010,"id":2,"etape":"fin","cmd":"lampe 1 on","ok":false,"code":"deja_traite","msg":"id deja traite : reponse oubliee","duree_ms":0}"#)
        #expect(M.envois(m.recu(deja, maintenant: 3.2)) == ["id=3 json etat\n"])
        #expect(m.correlateur.suivi(a)?.etat == .terminee)
        #expect(m.correlateur.suivi(a)?.fin?.code == .dejaTraite)
    }

    /// Scenario de la relecture : `accepte` perdu, `ordre` (confirme) a 1,4 s. La commande
    /// est confirmee aussitot, la place en vol libre ; ni renvoi, ni « issue perdue », meme
    /// si l'`accepte` garde par le pont arrive ensuite (rendu a un renvoi qui a croise).
    @Test func ordreSansAccepteJamaisPerdu() {
        var m = Self.connecte()
        let (a, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 1)
        #expect(M.envois(e) == ["id=2 lampe 1 on\n"])
        let ordre = M.element(#"{"v":1,"t":"ordre","n":20,"ms":901400,"lampe":1,"issue":"confirme","delai_ms":350,"essai":1,"ids":[2],"ids_perdus":0}"#)
        _ = m.recu(ordre, maintenant: 1.4)
        #expect(m.correlateur.suivi(a)?.etat == .confirmee)
        var t = 1.4
        var envois: [String] = []
        var effets: [MoteurSession.Effet] = []
        while t < 14 {
            t += 0.25
            if Int(t * 4) % 6 == 0 { _ = m.recu(M.element(Self.helloDistant), maintenant: t) }  // pas de silence
            if abs(t - 3.4) < 0.01 {
                // L'accepte garde, rendu a un renvoi : ignore.
                _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":21,"ms":903300,"id":2,"etape":"fin","cmd":"lampe 1 on","ok":true,"code":"accepte","duree_ms":0,"suite":"ordre","lampe":1}"#), maintenant: t)
            }
            let x = m.tic(maintenant: t)
            effets += x
            envois += M.envois(x)
        }
        #expect(!envois.contains("id=2 lampe 1 on\n"), "aucun renvoi : la commande est finie")
        #expect(!effets.contains(.ordrePerdu(a)))
        #expect(!effets.contains(.commandeSansReponse(a)))
        #expect(m.correlateur.suivi(a)?.etat == .confirmee)
    }

    /// Variante : l'`ordre` arrive apres le renvoi de 2 s, dont l'`accepte` se perd aussi.
    @Test func ordreApresLeRenvoiFinitLaCommande() {
        var m = Self.connecte()
        let (a, _) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 1)
        _ = m.recu(M.element(Self.helloDistant), maintenant: 2.5)
        #expect(M.envois(m.tic(maintenant: 3.0)) == ["id=2 lampe 1 on\n"])
        _ = m.recu(M.element(#"{"v":1,"t":"ordre","n":20,"ms":903200,"lampe":1,"issue":"abandon","delai_ms":3100,"essai":3,"ids":[2],"ids_perdus":0}"#), maintenant: 3.2)
        #expect(m.correlateur.suivi(a)?.etat == .abandonnee)
        _ = m.recu(M.element(Self.helloDistant), maintenant: 4.5)
        #expect(M.envois(m.tic(maintenant: 5.0)).isEmpty, "plus de renvoi a 4 s")
    }

    /// Hello perdu, `fin` recue : renvoyer le meme id ne rendrait que la reponse gardee,
    /// sans instantane. Le renvoi suivant prend un id neuf.
    @Test func finSansHelloRenvoiAvecUnIdNeuf() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        _ = m.recu(Self.finJson1(), maintenant: 1)
        #expect(m.phase == .attenteHello(essai: 1))
        #expect(M.envois(m.tic(maintenant: 2.0)) == ["id=2 json 1 bail 60\n"])
        #expect(M.envois(m.tic(maintenant: 4.0)) == ["id=2 json 1 bail 60\n"])
    }

    /// Sans `hello`, a distance : le pont n'a ouvert qu'une session H1 provisoire,
    /// oubliee 30 s apres le SALUT (10.3). La relance de 30 s est donc une nouvelle
    /// poignee de main (`.rouvrir`), jamais un `json 1` scelle pour une session que le
    /// pont ne connait plus.
    @Test func sansHelloADistanceRouvreApres30s() {
        var m = MoteurSession()
        #expect(M.envois(m.ouvert(maintenant: 0, genre: .udp)) == ["id=1 json 1 bail 60\n"])
        for t in [2.0, 4.0, 6.0] {
            #expect(M.envois(m.tic(maintenant: t)) == ["id=1 json 1 bail 60\n"], "renvoi du meme id a \(t) s")
        }
        let e8 = m.tic(maintenant: 8.0)
        #expect(m.phase == .sansReponse)
        #expect(e8 == [.note(.aucuneReponse)])
        #expect(m.tic(maintenant: 35.9).isEmpty)
        let e36 = m.tic(maintenant: 36.0)
        #expect(e36 == [.rouvrir(.reseauSansHello)], "nouvelle poignee de main, aucun json 1")
        #expect(!MoteurSession.Note.reseauSansHello.grave, "note de console, pas de bandeau de plus")
        #expect(m.statistiques.reouvertures == 1)
        #expect(m.tic(maintenant: 36.25).isEmpty, "pas de second .rouvrir avant la fermeture")
        m.ferme(maintenant: 36.5)
        #expect(M.envois(m.ouvert(maintenant: 37, genre: .udp)) == ["id=2 json 1 bail 60\n"])
        #expect(m.phase == .attenteHello(essai: 1))
    }

    @Test func sansHelloParUSBEtDemoInchange() {
        for genre in [GenreTransport.usb, .demo] {
            var u = MoteurSession()
            _ = u.ouvert(maintenant: 0, genre: genre)
            for t in [2.0, 4.0, 6.0, 8.0] { _ = u.tic(maintenant: t) }
            #expect(u.phase == .sansReponse)
            let e = u.tic(maintenant: 36.0)
            #expect(e == [.envoyer(LigneCommande.effacement), .envoyer(Data("id=5 json 1\n".utf8))],
                    "\(genre) : Ctrl-U et json 1 d'un id neuf, sur le meme port")
            #expect(u.statistiques.reouvertures == 0)
        }
    }

    @Test func reessayerADistanceRouvre() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        for t in [2.0, 4.0, 6.0, 8.0] { _ = m.tic(maintenant: t) }
        #expect(m.reessayer(maintenant: 10) == [.rouvrir(.reseauSansHello)])
        #expect(m.tic(maintenant: 36).isEmpty, "la relance de 30 s repart de cet essai")
    }

    @Test func finDuJson1AttendPlusLongtempsADistance() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        _ = m.recu(M.element(Self.helloDistant), maintenant: 0.3)
        #expect(!m.tic(maintenant: 3.5).contains(.note(.reponseJson1Perdue)), "instantane de ~11 Ko sur Thread")
        #expect(m.instantaneEnCours)
        for t in stride(from: 2.0, through: 11.0, by: 1.5) {
            _ = m.recu(M.element(Self.helloDistant), maintenant: t)  // le pont parle : pas de silence
        }
        #expect(!m.tic(maintenant: 11.9).contains(.note(.reponseJson1Perdue)))
        #expect(m.tic(maintenant: 12.0).contains(.note(.reponseJson1Perdue)))
    }

    @Test func renvoiDUneCommandeParLeTic() {
        var m = Self.connecte()
        let (a, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 1)
        #expect(M.envois(e) == ["id=2 lampe 1 on\n"])
        _ = m.recu(M.element(Self.helloDistant), maintenant: 2.5)
        #expect(M.envois(m.tic(maintenant: 3.0)) == ["id=2 lampe 1 on\n"], "meme id, a 2 s")
        _ = m.recu(M.element(Self.helloDistant), maintenant: 4.5)
        #expect(M.envois(m.tic(maintenant: 5.0)) == ["id=2 lampe 1 on\n"], "puis a 4 s")
        _ = m.recu(M.element(Self.helloDistant), maintenant: 6.5)
        let e7 = m.tic(maintenant: 7.0)
        #expect(e7.contains(.commandeSansReponse(a)), "sans reponse a 6 s")
        #expect(M.envois(e7) == ["id=3 json etat\n"])
    }

    @Test func texteRattacheParLeMoteur() {
        var m = Self.connecte()
        let (a, _) = m.soumettre("lampe 1", origine: .console, maintenant: 1)
        _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":20,"ms":913000,"id":2,"etape":"debut","cmd":"lampe 1","ok":true,"code":"en_cours"}"#), maintenant: 1.1)
        _ = m.recu(M.element(#"{"v":1,"t":"texte","n":21,"ms":913004,"id":2,"txt":"lampe 1 : Lampe bureau"}"#), maintenant: 1.2)
        _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":22,"ms":913006,"id":2,"etape":"fin","cmd":"lampe 1","ok":true,"code":"ok","duree_ms":6}"#), maintenant: 1.3)
        #expect(m.correlateur.suivi(a)?.texte == ["lampe 1 : Lampe bureau"])
        #expect(m.correlateur.suivi(a)?.etat == .terminee)
    }

    @Test func pingADistance() {
        var m = Self.connecte()
        #expect(m.intervallePing == 10, "bail de 60 s : ping toutes les 10 s")
        _ = m.recu(M.element(Self.helloDistant), maintenant: 9)
        #expect(M.envois(m.tic(maintenant: 9.9)).isEmpty)
        #expect(M.envois(m.tic(maintenant: 10.0)) == ["id=2 json ping\n"])
    }

    @Test func reglagesDistantsSuivis() {
        var m = Self.connecte()
        let (_, e) = m.soumettre("json trames 1", origine: .console, maintenant: 1)
        #expect(M.envois(e) == ["id=2 json trames 1\n"])
        _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":30,"ms":1,"id":2,"etape":"fin","cmd":"json trames 1","ok":true,"code":"ok","duree_ms":0}"#), maintenant: 1.1)
        #expect(m.reglages.trames == true)
        _ = m.recu(M.element(#"{"v":1,"t":"hello","n":31,"ms":2,"bloc":"base","boot":"3FA2C901","up_s":901,"session":{"transport":"udp","trames":false}}"#), maintenant: 1.2)
        #expect(m.reglages.trames == false, "le hello fait foi")
    }

    /// Les reglages suivent la commande telle que la console du pont la decoupe (argv) :
    /// `js\xon compteurs 5000` est `json compteurs 5000` pour le pont (10.5, split_argv.c).
    @Test func reglagesLusCommeLePontDecoupeLaCommande() {
        var m = Self.connecte()
        #expect(m.reglages.compteursMs == 0)
        _ = m.soumettre(#"js\xon compteurs 5000"#, origine: .console, maintenant: 1)
        _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":30,"ms":1,"id":2,"etape":"fin","cmd":"json compteurs 5000","ok":true,"code":"ok","duree_ms":0}"#), maintenant: 1.1)
        #expect(m.reglages.compteursMs == 5000)
        _ = m.soumettre(#"json "log" 1"#, origine: .console, maintenant: 2)
        _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":31,"ms":2,"id":3,"etape":"fin","cmd":"json log 1","ok":true,"code":"ok","duree_ms":0}"#), maintenant: 2.1)
        #expect(m.reglages.log == true)
    }

    /// Le moteur ne demande jamais a distance une ligne que la liste blanche refuserait :
    /// ouverture, ping, instantane apres "sans reponse", liberation, cadences.
    @Test func toutesLesLignesDuMoteurSontPermisesADistance() {
        var m = MoteurSession()
        var lignes = M.envois(m.ouvert(maintenant: 0, genre: .udp))
        lignes += M.envois(m.recu(M.element(Self.helloDistant), maintenant: 0.1))
        lignes += M.envois(m.recu(Self.finJson1(), maintenant: 0.2))
        // Une commande sans reponse : renvois, puis l'instantane demande par le moteur.
        lignes += M.envois(m.soumettre("lampe 1 on", origine: .interface, maintenant: 0.5).1)
        var t = 0.5
        while t < 40 {
            t += 0.5
            if Int(t * 2) % 3 == 0 { _ = m.recu(M.element(Self.helloDistant), maintenant: t) }
            lignes += M.envois(m.tic(maintenant: t))
        }
        lignes += M.envois(m.liberer(maintenant: t))
        #expect(lignes.contains("id=1 json 1 bail 60\n"))
        #expect(lignes.contains { $0.hasSuffix(" json ping\n") })
        #expect(lignes.contains { $0.hasSuffix(" json etat\n") })
        #expect(lignes.contains { $0.hasSuffix(" json 0\n") })
        for l in lignes {
            let commande = l.drop { $0 != " " }.dropFirst().trimmingCharacters(in: .newlines)
            #expect(PolitiqueCommandes.autoriseeADistance(commande) == nil, "\(l)")
        }
        var u = MoteurSession()
        _ = u.ouvert(maintenant: 0, genre: .udp)
        for c in MoteurSession.Cadence.allCases {
            for ms in [-5, 0, 1, 199, 200, 999, 1_000, 2_000, 4_999, 5_000, 9_999, 10_000, 30_000, 60_000, 60_001, 999_999] {
                let l = u.ligneCadence(c, ms: ms)
                #expect(PolitiqueCommandes.autoriseeADistance(l) == nil, "\(l)")
            }
        }
    }

    @Test func cadencesBorneesSelonLeTransport() {
        var u = MoteurSession()
        _ = u.ouvert(maintenant: 0)
        #expect(u.ligneCadence(.periode, ms: 100) == "json periode 200")
        #expect(u.ligneCadence(.lampes, ms: 500) == "json lampes 1000")
        #expect(u.ligneCadence(.compteurs, ms: 0) == "json compteurs 0")
        #expect(u.ligneCadence(.reseau, ms: 90_000) == "json reseau 60000")
        var r = MoteurSession()
        _ = r.ouvert(maintenant: 0, genre: .udp)
        #expect(r.ligneCadence(.periode, ms: 1_000) == "json periode 2000")
        #expect(r.ligneCadence(.lampes, ms: 1_000) == "json lampes 10000")
        #expect(r.ligneCadence(.compteurs, ms: 1_000) == "json compteurs 5000")
        #expect(r.ligneCadence(.reseau, ms: 5_000) == "json reseau 10000")
        #expect(r.ligneCadence(.compteurs, ms: 0) == "json compteurs 0")
        #expect(MoteurSession.bornes(.periode, genre: .udp) == 2_000...60_000)
        #expect(MoteurSession.bornes(.periode, genre: .usb) == 200...60_000)
    }
}
