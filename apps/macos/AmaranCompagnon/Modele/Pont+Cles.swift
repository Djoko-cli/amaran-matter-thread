// Gestes des cles (spec 3b, section 5) : dossier d'amaran Desktop, copie dans le
// trousseau, chargement du pont par l'USB, sauvegarde chiffree. Les cles ne sont
// jamais affichees, journalisees ni copiees ; elles sont lues au dernier moment.
import AmaranProtocole
import Foundation

/// Ou en est le chargement du pont.
enum EtatChargement: Equatable, Sendable {
    case repos
    case enCours(String)
    case attenteRedemarrage
    case reussi(Date)
    case echec(String)

    var actif: Bool {
        switch self {
        case .enCours, .attenteRedemarrage: true
        default: false
        }
    }
}

/// D'ou viennent les cles a charger.
enum SourceCles: Sendable {
    case amaranDesktop
    case trousseau
}

/// Chargement en cours : les commandes restantes (la premiere porte les cles, et
/// n'est gardee que jusqu'a sa soumission), ce que le pont doit montrer ensuite.
struct ChargementEnCours {
    var attendu: ApercuReseau
    var restantes: [String]
    var etape = 0
    var suivi: UUID?
    var commandeSuivie = ""
    var bootAvant: String?
    var redemarrageDepuis: TimeInterval?
    var etapeDepuis: TimeInterval
}

extension Pont {
    static let cleSignet = "dossierAmaranDesktop"
    static let cleSauvegarde = "derniereSauvegarde"
    /// Delais du chargement : une etape (reponse du pont), puis le redemarrage.
    static let delaiEtape: TimeInterval = 8
    static let delaiRedemarrage: TimeInterval = 40

    /// Trousseau en vigueur : celui de la demo en mode demo.
    var trousseauCourant: any TrousseauReseau { estDemo ? trousseauDemo : trousseau }

    func chargerPreferencesCles() {
        if let t = preferences.object(forKey: Self.cleSauvegarde) as? Date { derniereSauvegarde = t }
        dossierAmaran = resoudreSignet()
        rafraichirCopie()
    }

    /// Relit l'apercu de la copie (sans ses cles).
    func rafraichirCopie() {
        do {
            copie = try trousseauCourant.apercu()
        } catch {
            copie = nil
            note(String(describing: error), grave: true)
        }
    }

    // MARK: - Dossier d'amaran Desktop (signet)

    /// Le dossier choisi dans le panneau d'ouverture : l'app en garde un signet.
    func autoriserDossier(_ url: URL) {
        do {
            let signet = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                              includingResourceValuesForKeys: nil, relativeTo: nil)
            preferences.set(signet, forKey: Self.cleSignet)
            dossierAmaran = url
            relireBase()
        } catch {
            erreurBase = "Signet du dossier impossible : \(error.localizedDescription)"
        }
    }

    private func resoudreSignet() -> URL? {
        guard let signet = preferences.data(forKey: Self.cleSignet) else { return nil }
        var perime = false
        guard let url = try? URL(resolvingBookmarkData: signet, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &perime) else { return nil }
        if perime, let neuf = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                     includingResourceValuesForKeys: nil, relativeTo: nil) {
            preferences.set(neuf, forKey: Self.cleSignet)
        }
        return url
    }

    /// Lit la base d'amaran Desktop (ou le reseau de demonstration). Les cles lues
    /// doivent etre effacees par l'appelant des qu'il en a fini.
    private func lireBaseAmaran() throws -> ReseauMesh {
        if estDemo { return ReseauDemo.reseau }
        guard let dossier = dossierAmaran else {
            throw ErreurCles("Dossier d'amaran Desktop non autorisé : Réglages, « Changer… ».")
        }
        let acces = dossier.startAccessingSecurityScopedResource()
        defer { if acces { dossier.stopAccessingSecurityScopedResource() } }
        return try BaseAmaranDesktop.lire(try BaseAmaranDesktop.trouver(dans: dossier))
    }

    /// Relit la base pour la comparer (apercu seulement).
    func relireBase() {
        do {
            var r = try lireBaseAmaran()
            base = r.apercu
            erreurBase = nil
            effacer(&r)
        } catch {
            base = nil
            erreurBase = String(describing: error)
        }
    }

    /// « Copier depuis amaran Desktop » : la base remplace la copie du trousseau.
    func copierDepuisAmaranDesktop() {
        do {
            var r = try lireBaseAmaran()
            defer { effacer(&r) }
            try trousseauCourant.ranger(r)
            base = r.apercu
            erreurBase = nil
            rafraichirCopie()
            note("Clés copiées depuis amaran Desktop dans le trousseau (empreintes \(r.empreinteReseau) \(r.empreinteApplication), \(r.lampes.count) lampe(s)).")
        } catch {
            erreurBase = String(describing: error)
            note(String(describing: error), grave: true)
        }
    }

    // MARK: - Chargement du pont

    /// Le pont tel que la config le montre, sans ses cles (nil : pas de cles).
    var apercuPont: ApercuReseau? {
        ApercuReseau.dePont(mesh: etat.mesh?.valeur, lampes: etat.configLampes.mapValues(\.valeur))
    }

    /// Ecarts entre la base, la copie et le pont (panneau « Cles »).
    var ecartsCles: [EcartCles] {
        ComparaisonCles.ecarts(base: base, copie: copie, pont: apercuPont, pontConnu: etat.mesh != nil)
    }

    /// Lampes du pont que la base (ou, sans elle, la copie) dit capables de plus.
    var modelesACataloguer: [ModeleACataloguer] {
        ComparaisonCles.modelesACataloguer(base: base ?? copie, pont: etat.configLampes.mapValues(\.valeur))
    }

    /// « Charger le pont » : pre-controles, puis `mesh cles`, `mesh lampes`, une ligne
    /// par lampe, chacune verifiee avant la suivante, puis `redemarre` et la
    /// comparaison de ce que le pont montre apres (spec 3b, section 5).
    func chargerPont(depuis source: SourceCles) {
        guard !chargement.actif else { return }
        guard peutCommander, etat.capacites.contains("mesh") else {
            chargement = .echec(ErreurChargement.pasLePont.description)
            return
        }
        do {
            var r = try source == .amaranDesktop ? lireBaseAmaran() : trousseauCourant.lire()
            defer { effacer(&r) }
            try r.verifier()
            charge = ChargementEnCours(attendu: r.apercu, restantes: r.commandes(), etapeDepuis: maintenant())
            chargement = .enCours("clés")
            note("Chargement du pont : \(r.lampes.count) lampe(s), empreintes \(r.empreinteReseau) \(r.empreinteApplication).")
            avancerChargement()
        } catch {
            chargement = .echec(String(describing: error))
        }
    }

    /// Un pas du chargement : verifie l'etape finie, soumet la suivante. Appele a
    /// chaque ligne recue et a chaque tic.
    func avancerChargement() {
        guard !chargementAvance, var c = charge else { return }
        chargementAvance = true
        defer { chargementAvance = false }
        let t = maintenant()
        if let depuis = c.redemarrageDepuis {
            // Le pont doit revenir avec un autre boot, et montrer ce qui a ete charge.
            if let boot = etat.boot, boot != c.bootAvant, let mesh = etat.mesh?.valeur,
               etat.configLampes.count >= (mesh.lampes ?? 0) {
                if let e = VerificationChargement.ecart(c.attendu, mesh: mesh, lampes: etat.configLampes.mapValues(\.valeur)) {
                    finirChargement(.echec(ErreurChargement.apresRedemarrage(e).description))
                } else {
                    finirChargement(.reussi(Date()))
                    note("Pont chargé et redémarré : il montre les clés et les lampes de la copie.")
                }
            } else if t - depuis > Self.delaiRedemarrage {
                finirChargement(.echec(ErreurChargement.pasRedemarre.description))
            }
            return
        }
        if let id = c.suivi {
            guard let s = moteur.correlateur.suivi(id) else {
                return finirChargement(.echec(ErreurChargement.commande(c.commandeSuivie, "suivi perdu").description))
            }
            if !s.etat.estFinal {
                if t - c.etapeDepuis > Self.delaiEtape {
                    finirChargement(.echec(ErreurChargement.commande(c.commandeSuivie, "pas de réponse").description))
                }
                return
            }
            if let erreur = verifierEtape(c, s) { return finirChargement(.echec(erreur.description)) }
            c.suivi = nil
        }
        guard peutCommander else { return }
        if c.restantes.isEmpty {
            // Dernier controle : le redemarrage, puis ce que le pont montre.
            c.bootAvant = etat.boot
            c.redemarrageDepuis = t
            charge = c
            chargement = .attenteRedemarrage
            envoyer("redemarre")
            return
        }
        let commande = c.restantes.removeFirst()
        let secret = PolitiqueCommandes.masquerCle(commande) != commande
        c.commandeSuivie = secret ? PolitiqueCommandes.masquerCle(commande) : commande
        c.suivi = envoyer(commande, secret: secret)
        c.etape += 1
        c.etapeDepuis = t
        charge = c
        chargement = .enCours(c.etape == 1 ? "clés" : c.etape == 2 ? "liste" : "lampe \(c.etape - 2) sur \(c.attendu.lampes.count)")
    }

    /// Les controles d'une etape finie : reponse ok, empreintes rendues, liste enregistree.
    private func verifierEtape(_ c: ChargementEnCours, _ s: SuiviCommande) -> ErreurChargement? {
        guard s.etat == .terminee, s.fin?.ok == true else {
            let raison = s.fin.map { Interpretation.code($0.code) } ?? "pas de réponse"
            return .commande(c.commandeSuivie, s.texte.last ?? raison)
        }
        if c.etape == 1 {
            let attendues = "\(c.attendu.empreinteReseau) \(c.attendu.empreinteApplication)"
            guard let e = VerificationChargement.empreintesRendues(s.texte) else {
                return .commande(c.commandeSuivie, "réponse sans empreintes")
            }
            let rendues = "\(e.reseau) \(e.application)"
            if rendues != attendues { return .empreintes(rendues: rendues, attendues: attendues) }
        }
        if c.etape == c.attendu.lampes.count + 2, VerificationChargement.listeEnregistree(s.texte) != c.attendu.lampes.count {
            return .listeNonEnregistree
        }
        return nil
    }

    private func finirChargement(_ e: EtatChargement) {
        charge = nil
        chargement = e
        if case .echec(let raison) = e { note(raison, grave: true) }
    }

    /// La connexion ne portera plus le chargement (source changee...).
    func interrompreChargement(_ raison: String) {
        guard let c = charge, c.redemarrageDepuis == nil else { return }
        finirChargement(.echec("Chargement interrompu (\(raison)) : relancer « Charger le pont »."))
    }

    // MARK: - Sauvegarde chiffree

    /// « Exporter une sauvegarde » : la copie du trousseau, chiffree.
    func exporterSauvegarde(vers url: URL, phrase: String, confirmation: String) throws {
        try Sauvegarde.verifierPhrase(phrase, confirmation: confirmation)
        var r = try trousseauCourant.lire()
        defer { effacer(&r) }
        let fichier = try Sauvegarde.chiffrer(r, phrase: phrase)
        try fichier.write(to: url, options: .atomic)
        derniereSauvegarde = Date()
        preferences.set(derniereSauvegarde, forKey: Self.cleSauvegarde)
        note("Sauvegarde chiffrée exportée (empreintes \(r.empreinteReseau) \(r.empreinteApplication)).")
    }

    /// « Importer une sauvegarde » : dechiffrer et verifier, sans rien remplacer.
    func lireSauvegarde(_ url: URL, phrase: String) throws -> ReseauMesh {
        let acces = url.startAccessingSecurityScopedResource()
        defer { if acces { url.stopAccessingSecurityScopedResource() } }
        var r = try Sauvegarde.dechiffrer(try Data(contentsOf: url), phrase: phrase)
        r.source = .sauvegarde
        return r
    }

    /// Remplace la copie du trousseau, apres confirmation.
    func remplacerCopie(par r: ReseauMesh) throws {
        try trousseauCourant.ranger(r)
        rafraichirCopie()
        note("Copie du trousseau remplacée par la sauvegarde (empreintes \(r.empreinteReseau) \(r.empreinteApplication)).")
    }

    /// Efface les cles d'un reseau lu, au mieux.
    func effacer(_ r: inout ReseauMesh) {
        r.cleReseau.resetBytes(in: 0..<r.cleReseau.count)
        r.cleApplication.resetBytes(in: 0..<r.cleApplication.count)
    }
}

/// Erreur lisible des gestes des cles.
struct ErreurCles: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
