// Acces reseau du pont (docs/PROTOCOLE-JSON.md 10), repris de Halo Compagnon (commit
// e114cd5, Modele/Pont.swift) : cle UDP creee par l'USB et rangee dans le trousseau des
// ponts, etat de l'acces, oubli d'un pont, repertoire et titres des sources reseau. La
// cle n'est jamais affichee ni journalisee : seule son empreinte l'est.
import AmaranProtocole
import Foundation

extension Pont {
    // MARK: - Repertoire et titres

    /// Titre de la source reseau choisie (comme Halo Compagnon) : celui de la carte,
    /// "AMARAN · F0:F5:BD:0A:0B:0C", si le repertoire connait sa MAC ; sinon `<nom>.local`.
    func titre(reseau nom: String) -> String {
        repertoire.mac(pourSrp: nom).map { repertoire.titre(mac: $0) } ?? "\(nom).local"
    }

    /// Titre d'un pont du trousseau dans les listes : celui de sa carte si le repertoire la
    /// connait (vue au moins une fois, par l'USB ou le reseau), sinon « Pont amaran ».
    func titre(pont p: PontConnu) -> String {
        guard let mac = repertoire.mac(pourSrp: p.nom) else { return "Pont amaran" }
        return repertoire.titre(mac: mac)
    }

    /// Identite et bloc `ip` d'un vrai pont (jamais la demo) : le repertoire apprend son
    /// modele et son nom SRP, et les preferences le gardent.
    func noterRepertoire() {
        guard genreTransport == .usb || genreTransport == .udp else { return }
        guard repertoire.noter(etat) else { return }
        if let d = repertoire.donnees { preferences.set(d, forKey: RepertoirePonts.cleReglages) }
    }

    // MARK: - Acces reseau

    /// Acces reseau (bloc `ip` du pont) : par l'USB ou la demo seulement. En demo,
    /// l'empreinte vient du trousseau isole de la demo, jamais du vrai.
    var accesReseau: EtatAccesReseau {
        guard genreTransport == .usb || genreTransport == .demo else { return .inconnu }
        let connus = genreTransport == .demo ? trousseauPontsDemo.lister() : pontsConnus
        return EtatAccesReseau.depuis(ip: etat.ip?.valeur) { nom in connus.first { $0.nom == nom }?.empreinte }
    }

    /// Ce que dit la section « Pont branche en USB » quand la cle ne peut pas s'y gerer
    /// (acces `.inconnu`) : pas de pont connecte par l'USB, ou un pont connecte qui n'a pas
    /// encore de nom SRP (la cle se range sous ce nom, `creerCle`).
    var texteSansAccesReseau: String {
        Self.texteSansAccesReseau(parUSB: (genreTransport == .usb || genreTransport == .demo) && peutCommander,
                                  udpAnnonce: etat.identite == nil || etat.a(.udp),
                                  ipRecu: etat.ip?.valeur.udp != nil, srpConnu: !(etat.srp ?? "").isEmpty)
    }

    static func texteSansAccesReseau(parUSB: Bool, udpAnnonce: Bool, ipRecu: Bool, srpConnu: Bool) -> String {
        guard parUSB else {
            return "Brancher le pont en USB et le connecter (menu Source) pour créer ou renouveler sa clé."
        }
        guard udpAnnonce else {
            return "Ce firmware du pont n'a pas d'accès par Thread (capacité udp absente)."
        }
        guard ipRecu else {
            return "Pont connecté par l'USB : son accès par Thread n'est pas encore connu (bloc ip attendu)."
        }
        guard srpConnu else {
            return "Pont connecté par l'USB, nom SRP inconnu : le pont doit d'abord rejoindre le réseau Thread (être dans Maison) ; sa clé se range sous ce nom."
        }
        return "Brancher le pont en USB et le connecter (menu Source) pour créer ou renouveler sa clé."
    }

    /// Une creation de cle est en file ou en vol.
    var creationCleEnCours: Bool {
        guard let c = creationCle, let s = moteur.correlateur.suivi(c.id) else { return false }
        return !s.etat.estFinal
    }

    /// « Activer l'acces reseau » et « Nouvelle cle… » : alea de l'app, cle calculee par
    /// le pont et rendue une fois, rangee dans le trousseau des ponts sous le nom SRP du
    /// bloc `ip` ; les sessions reseau en cours tombent (10.2). Par l'USB seulement, et
    /// avec un acces reseau connu (nom SRP et bloc `udp`) : jamais de cle rangee sous un
    /// compte vide. Bloque seulement si un essai est encore en file ou en vol.
    func creerCle() {
        guard !creationCleEnCours else { return }
        guard !aDistance, accesReseau != .inconnu, let nom = etat.srp, !nom.isEmpty else { return }
        // La ligne porte l'alea : secrete (jamais gardee dans un suivi, jamais renvoyee),
        // et masquee dans la console par `masquerCle`.
        guard let id = envoyer(CleReseau.commande(alea: CleReseau.alea()), secret: true) else { return }
        creationCle = (id, nom)
        note("Nouvelle clé réseau demandée au pont : les sessions réseau en cours tombent.")
    }

    /// La reponse `fin` a la creation de cle en cours, telle que recue (avec sa cle), et
    /// le nom SRP sous lequel la ranger ; nil pour toute autre ligne. `creationCle` est
    /// desarme ici : la reponse ne sert qu'une fois.
    func reponseACreationCle(_ element: ElementRecu) -> (Reponse, String)? {
        guard let c = creationCle, case .machine(let l) = element, case .reponse(let r) = l.message,
              r.etape == .fin, r.code != .dejaTraite, moteur.correlateur.suivi(numero: r.id)?.id == c.id else { return nil }
        creationCle = nil
        return (r, c.nom)
    }

    /// Verifie la cle rendue et la range. En mode demo, dans le trousseau isole de la
    /// demo : elle n'ecrase jamais celle d'un vrai pont.
    func terminerCreationCle(_ r: Reponse, nom: String) {
        switch CleReseau.verifier(r) {
        case .success(var c):
            defer { c.cle.resetBytes(in: 0..<c.cle.count) }
            do {
                if genreTransport == .demo {
                    try trousseauPontsDemo.ranger(nom: nom, cle: c.cle, empreinte: c.empreinte)
                    // Le pont simule n'a pas de source reseau : rien a joindre par Thread.
                    note("Clé réseau rangée dans le trousseau de la démo (empreinte \(c.empreinte)), à part du vrai : le pont simulé ne se joint pas par le réseau Thread.")
                } else {
                    try trousseauPonts.ranger(nom: nom, cle: c.cle, empreinte: c.empreinte)
                    pontsConnus = trousseauPonts.lister()
                    note("Clé réseau rangée dans le trousseau (empreinte \(c.empreinte)) : le pont est joignable par le réseau Thread.")
                }
                // Le bloc `ip` suit (json etat le renvoie) : l'acces passe a « cle connue ».
                rafraichir()
            } catch {
                // Le pont a deja adopte la nouvelle cle : le Mac doit recommencer.
                note("Le pont a déjà changé de clé, mais le Mac n'a pas pu la ranger (\(String(describing: error))) : relancer « Nouvelle clé… ».",
                     grave: true)
            }
        case .failure(let e):
            note(e.description, grave: true)
        }
    }

    /// La connexion ne portera plus la reponse d'une creation de cle (transport ferme,
    /// source changee) : le dire plutot que de bloquer un nouvel essai en silence.
    func interrompreCreationCle() {
        guard creationCle != nil else { return }
        creationCle = nil
        note("Création de clé interrompue : si le pont a changé de clé, l'accès réseau affichera « clé inconnue de ce Mac » ; recommencer.",
             grave: true)
    }

    /// « Oublier… » : retire la cle d'un pont du trousseau de ce Mac (le pont garde la
    /// sienne). La source en cours, si c'est ce pont, est deconnectee. Seulement si la
    /// suppression a reussi : sinon la cle reste, la console dit l'erreur, et la session
    /// continue.
    func oublierPont(_ nom: String) {
        do {
            try trousseauPonts.oublier(nom: nom)
        } catch {
            pontsConnus = trousseauPonts.lister()
            note("Clé du pont \(nom).local non oubliée : \(String(describing: error))", grave: true)
            return
        }
        pontsConnus = trousseauPonts.lister()
        note("Clé du pont \(nom).local oubliée par ce Mac (le pont garde la sienne).")
        if source == .reseau(nom: nom) { deconnecter() }
    }

    /// Relit la liste des ponts connus (trousseau modifie hors de l'app).
    func relirePontsConnus() {
        pontsConnus = trousseauPonts.lister()
    }
}
