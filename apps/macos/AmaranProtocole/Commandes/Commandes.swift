// Repris de Halo Compagnon (commit e114cd5) : regles et commandes du pont amaran.
import Foundation

/// Genre de transport.
public enum GenreTransport: String, Sendable, Equatable {
    case usb
    /// UDP sur Thread (`TransportUDP`, port 5480).
    case udp
    /// Pont simule (mode demo) : se comporte comme l'USB.
    case demo
}

/// Erreur de construction d'une ligne vers le pont (section 2.5).
public enum ErreurLigne: Error, Sendable, Equatable, CustomStringConvertible {
    case vide
    case tropLongue(octets: Int, max: Int)
    case caractereInterdit
    case prefixeId
    case json

    public var description: String {
        switch self {
        case .vide: tr("Ligne vide.")
        case .tropLongue(let o, let m): tr("Ligne trop longue : \(o) octets, \(m) au plus avec le préfixe id=.")
        case .caractereInterdit: tr("Aucun caractère de contrôle n'est permis.")
        case .prefixeId: tr("L'app ajoute elle-même le préfixe id=<n>.")
        case .json: tr("Jamais de JSON ni d'octet RS vers le pont.")
        }
    }
}

/// Lignes app -> pont : texte de la console prefixe par `id=<n> ` (6.1).
public enum LigneCommande {
    /// 127 octets au plus, prefixe compris (2.5).
    public static let octetsMax = 127
    public static let idMax = 999_999_999

    /// Octets envoyes a l'ouverture : Ctrl-U puis LF (3.2).
    public static let effacement = Data([Octets.ctrlU, Octets.lf])

    /// Normalise une commande (espaces de bord) et verifie les regles de 2.5 : les
    /// noms des lampes peuvent porter des accents (UTF-8), jamais un caractere de controle.
    public static func valider(_ commande: String, id: Int?) -> Result<String, ErreurLigne> {
        let c = commande.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return .failure(.vide) }
        guard c.unicodeScalars.allSatisfy({ $0.value >= 0x20 && !(0x7F...0x9F).contains($0.value) }) else {
            return .failure(c.unicodeScalars.contains { $0.value == 0x1E } ? .json : .caractereInterdit)
        }
        if c.hasPrefix("{") { return .failure(.json) }
        if c.lowercased().hasPrefix("id=") { return .failure(.prefixeId) }
        let ligne = id.map { "id=\($0) \(c)" } ?? c
        guard ligne.utf8.count <= octetsMax else {
            return .failure(.tropLongue(octets: ligne.utf8.count, max: octetsMax))
        }
        return .success(ligne)
    }

    /// Ligne complete, terminee par LF.
    public static func octets(_ commande: String, id: Int?) -> Result<Data, ErreurLigne> {
        valider(commande, id: id).map { Data(($0 + "\n").utf8) }
    }

    /// Numero suivant : 1..999999999, repart a 1.
    public static func suivant(_ id: Int) -> Int {
        id >= idMax ? 1 : id + 1
    }

    /// Mots d'une commande, en minuscules. Un guillemet coupe le mot, comme dans la
    /// console du pont (esp_console_split_argv) : `"redemarre"` est `redemarre`, et
    /// `"mesh"cles` est `mesh cles`.
    public static func mots(_ commande: String) -> [String] {
        commande.lowercased().replacingOccurrences(of: "\"", with: " ").split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }
    /// Arguments d'une commande, decoupes exactement comme `esp_console_split_argv`
    /// d'ESP-IDF (components/console/split_argv.c) les decoupe dans le pont : separes
    /// par des espaces (la tabulation fait partie du mot), guillemets doubles, barre
    /// oblique inverse devant `\`, `"` ou une espace (devant un autre octet, les deux
    /// sont oublies), un guillemet fermant finit le mot ; au plus `maxArguments`
    /// (le pont passe 8 places : 7 arguments), un octet nul arrete tout. Sensible a la
    /// casse, comme la console. Sert a juger la liste blanche comme le pont (10.5).
    public static func argv(_ commande: String, maxArguments: Int = 7) -> [String] {
        // Les premiers arguments ne dependent pas de la suite de la ligne : couper apres
        // `maxArguments` revient a s'arreter la, comme le pont.
        arguments(Array(commande.utf8)).prefix(max(maxArguments, 0)).map { String(decoding: $0.valeur, as: UTF8.self) }
    }

    /// Tous les arguments d'une ligne, decoupes comme `argv` (meme automate, sans limite de
    /// nombre), avec leur place dans la ligne : octets `debut..<fin`, guillemets et barres
    /// obliques compris. Sert a masquer les cles la ou elles sont ecrites.
    static func arguments(_ octets: [UInt8]) -> [(valeur: [UInt8], debut: Int, fin: Int)] {
        enum Etat { case espace, mot, guillemets, motEchappe, guillemetsEchappe }
        let espace = UInt8(ascii: " "), guillemet = UInt8(ascii: "\""), barre = UInt8(ascii: "\\")
        var args: [(valeur: [UInt8], debut: Int, fin: Int)] = []
        var courant: [UInt8] = []
        var debut = 0
        var fin = octets.count
        var etat = Etat.espace
        for (i, b) in octets.enumerated() {
            if b == 0 {
                fin = i
                break
            }
            switch etat {
            case .espace:
                if b == espace { continue }
                courant = []
                debut = i
                if b == guillemet {
                    etat = .guillemets
                } else if b == barre {
                    etat = .motEchappe
                } else {
                    courant.append(b)
                    etat = .mot
                }
            case .guillemets:
                if b == guillemet {
                    args.append((courant, debut, i + 1))
                    etat = .espace
                } else if b == barre {
                    etat = .guillemetsEchappe
                } else {
                    courant.append(b)
                }
            case .motEchappe, .guillemetsEchappe:
                if b == barre || b == guillemet || b == espace { courant.append(b) }
                etat = etat == .motEchappe ? .mot : .guillemets
            case .mot:
                if b == espace {
                    args.append((courant, debut, i))
                    etat = .espace
                } else if b == barre {
                    etat = .motEchappe
                } else {
                    courant.append(b)
                }
            }
        }
        if etat != .espace { args.append((courant, debut, fin)) }
        return args
    }
}

/// Ce que la console fait d'une ligne tapee (6.4).
public enum VerdictConsole: Sendable, Equatable {
    case autorisee
    /// Demander confirmation avant d'envoyer.
    case confirmation(String)
    case interdite(String)
}

public enum PolitiqueCommandes {
    /// Commandes qui demandent confirmation (6.4) ; a distance, la liste blanche (10.5)
    /// d'abord. Toutes ces regles jugent la ligne decoupee comme la console du pont la
    /// decoupe (`LigneCommande.argv`, sensible a la casse) : guillemets et echappements
    /// ne les contournent pas (`re\xdemarre` est `redemarre` pour le pont, et demande la
    /// meme confirmation).
    public static func verdictConsole(_ commande: String, transport: GenreTransport = .usb) -> VerdictConsole {
        // Longueur jugee avec le plus long id possible : la ligne partira quel que soit son numero.
        if case .failure(let e) = LigneCommande.valider(commande, id: LigneCommande.idMax) {
            return .interdite(e.description)
        }
        if transport == .udp, let raison = autoriseeADistance(commande) {
            return .interdite(tr("Commande non envoyée : \(refusDistant(raison))."))
        }
        let a = LigneCommande.argv(commande.trimmingCharacters(in: .whitespaces))
        func est(_ i: Int, _ mot: String) -> Bool { i < a.count && a[i] == mot }
        if a.count == 2, est(0, "json"), est(1, "0") {
            return .interdite(tr("Utiliser « Libérer le port » : l'app enverra json 0 et fermera le port."))
        }
        // Le pont changerait de cle, mais la cle rendue ne serait rangee nulle part :
        // seul le geste de l'app la range dans le trousseau (10.2).
        if est(0, "json"), est(1, "cle"), est(2, "nouvelle") {
            return .interdite(tr("Utiliser « Nouvelle clé… » : la clé rendue doit être rangée dans le trousseau."))
        }
        if est(0, "json"), est(1, "cle"), est(2, "efface") {
            return .confirmation(tr("Efface la clé du réseau Thread : les sessions par le réseau tombent et le port 5480 se ferme."))
        }
        if est(0, "redemarre") {
            return .confirmation(tr("Redémarre le pont (le port USB va se ré-énumérer)."))
        }
        if est(0, "decommission") {
            return .confirmation(tr("Retire le pont de Maison et de tout autre contrôleur Matter (clés du Mesh et lampes gardées ; la clé de l'accès par Thread est effacée)."))
        }
        if est(0, "mesh") {
            if est(1, "cles") {
                return .confirmation(tr("Remplace les clés du réseau des lampes dans le pont (effet au redémarrage). « Charger le pont » vérifie en plus les empreintes."))
            }
            if est(1, "oublie") {
                return .confirmation(tr("Efface les clés du réseau des lampes dans le pont."))
            }
            if est(1, "adresse") {
                return .confirmation(tr("Change l'adresse Bluetooth Mesh du pont."))
            }
            if est(1, "iv") {
                return .confirmation(est(2, "cherche")
                    ? tr("Cherche l'IV Index : la console du pont reste occupée pendant la recherche.")
                    : tr("Change l'IV Index du réseau des lampes."))
            }
            if est(1, "lampes") {
                return .confirmation(tr("Ouvre une nouvelle liste de lampes (effet au redémarrage, une fois complète)."))
            }
            if a.count == 4, est(1, "lampe"), est(3, "masquer") {
                return .confirmation(tr("Retire la lampe de Maison : remise, elle y reviendra comme un nouvel accessoire, sans son nom, ses scènes ni ses automatisations."))
            }
        }
        return .autorisee
    }

    /// Refus de la liste blanche, en francais : la raison du pont (celle que rend
    /// `autoriseeADistance`, mot pour mot le `msg` de sa reponse `interdite`) n'est citee
    /// qu'une fois, entre guillemets, telle quelle. « la » : la commande refusee.
    public static func refusDistant(_ raison: String) -> String {
        tr("la liste blanche du pont la refuse (« \(raison) »)")
    }

    /// `json 1`, `json etat`, `json hello` : la `fin` part apres la derniere ligne de
    /// l'instantane (6.2), et non aussitot. Jugee sur la ligne decoupee comme le pont la
    /// decoupe (`json 1 bail 60` compris).
    public static func repondApresInstantane(_ commande: String) -> Bool {
        let a = LigneCommande.argv(commande.trimmingCharacters(in: .whitespaces))
        guard a.count >= 2, a[0] == "json" else { return false }
        return a[1] == "1" || (a.count == 2 && (a[1] == "etat" || a[1] == "hello"))
    }

    /// Apres ces commandes, l'app attend la re-enumeration de l'USB (3.1) ; jugees,
    /// comme `verdictConsole`, sur la ligne decoupee comme la console du pont la decoupe.
    public static func attendReenumeration(_ commande: String) -> Bool {
        let premier = LigneCommande.argv(commande.trimmingCharacters(in: .whitespaces)).first
        return premier == "redemarre" || premier == "decommission"
    }

    /// Liste blanche a distance (10.5) : miroir exact de `refusDistant`
    /// (components/protocole/json_amaran.cpp), juge sur les arguments decoupes comme le
    /// pont les decoupe (`LigneCommande.argv`) : guillemets et echappements ne la
    /// contournent pas (`json "1" "bail" 0` est refusee). `ligne` : la commande sans
    /// le prefixe `id=`. Rend nil si la commande est permise, sinon la raison, telle
    /// que le pont la donnerait dans le `msg` de sa reponse `interdite`.
    public static func autoriseeADistance(_ ligne: String) -> String? {
        let interdite = "interdite a distance : USB seulement"
        // La ligne part sans ses espaces de bord (LigneCommande.valider).
        let a = LigneCommande.argv(ligne.trimmingCharacters(in: .whitespaces))
        func est(_ i: Int, _ k: String) -> Bool { i < a.count && a[i] == k }
        // Entier decimal : chiffres seulement, 9 au plus (`nombre` du pont).
        func nombre(_ i: Int) -> Int? {
            guard i < a.count else { return nil }
            let u = Array(a[i].utf8)
            guard !u.isEmpty, u.count <= 9, u.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
            return Int(a[i])
        }
        guard !a.isEmpty else { return interdite }
        if est(0, "json") {
            if a.count == 2, est(1, "0") || est(1, "etat") || est(1, "hello") || est(1, "ping") { return nil }
            if est(1, "1") {
                // Jamais de bail 0 a distance : le pont emettrait pour un hote parti.
                if a.count == 2 { return nil }
                if a.count == 4, est(2, "bail"), let v = nombre(3), (10...120).contains(v) { return nil }
                return "json 1 : bail de 10 a 120 s a distance"
            }
            if a.count == 3, est(1, "trames") || est(1, "log"), est(2, "0") || est(2, "1") { return nil }
            for (k, min) in bornesDistantes where est(1, k) {
                if a.count == 3, let v = nombre(2), v == 0 || (v >= min && v <= 60_000) { return nil }
                return "json \(k) : 0 ou \(min)..60000 ms a distance"
            }
            return interdite  // 'json' seul, 'json cle ...'
        }
        if est(0, "lampe") {
            if a.count >= 2, nombre(1) == nil { return interdite }
            if a.count == 2 { return nil }  // detail
            if a.count == 3, est(2, "on") || est(2, "off") || est(2, "releve") { return nil }
            if a.count == 4, est(2, "niveau"), nombre(3) != nil { return nil }
            return interdite
        }
        if est(0, "mesh") {
            if a.count == 1 { return nil }  // lecture
            if a.count == 4, est(1, "lampe"), nombre(2) != nil, est(3, "masquer") || est(3, "afficher") { return nil }
            return interdite
        }
        if a.count == 2, est(0, "led"), est(1, "test") || est(1, "stop") { return nil }
        if a.count == 1, est(0, "lampes") || est(0, "matter") || est(0, "taches") || est(0, "cause") { return nil }
        return interdite
    }

    /// Cadences permises a distance, hors 0 (10.5) : `json <k> <ms>`, minimum, jusqu'a 60 000.
    public static let bornesDistantes: [(String, Int)] = [
        ("periode", 2_000), ("lampes", 10_000), ("compteurs", 5_000), ("reseau", 10_000),
    ]

    /// Masque les cles d'une ligne affichee : la commande `mesh cles <reseau>
    /// <application>` (casse, espaces et guillemets quelconques, comme la console les lit),
    /// l'alea de `json cle nouvelle <64 hexa>`, le champ `"cle":"..."` d'une reponse
    /// (la cle UDP, 10.2), et toute suite de 32 chiffres hexa ou plus (une cle tapee
    /// ailleurs). Les empreintes (8 hexa) et le nom SRP (16 hexa) restent visibles.
    /// Les deux commandes sont aussi jugees sur la ligne decoupee comme la console du pont
    /// la decoupe (`masquerArgumentsSecrets`) : guillemets et echappements ne cachent
    /// aucune cle au masque. Sert partout ou une commande ou un texte du pont s'affiche
    /// ou se garde : console, journal des envois, citations, suivis, historique de saisie.
    public static func masquerCle(_ texte: String) -> String {
        // Une barre oblique inverse peut couper « cle » (`c\xle`) : le pont l'oublie.
        guard texte.utf8.count >= 32 || texte.range(of: "cle", options: .caseInsensitive) != nil
              || texte.contains("\\") else { return texte }
        var s = masquerArgumentsSecrets(texte)
        s.replace(/(?i)("?mesh"?[ \t]+"?cles"?)([ \t]+"?[0-9a-f]+"?)+/) { m in m.output.1 + " " + masque + " " + masque }
        s.replace(/(?i)("?json"?[ \t]+"?cle"?[ \t]+"?nouvelle"?[ \t]+)[0-9a-f\\"]+/) { m in m.output.1 + masque }
        s.replace(/("cle"[ ]*:[ ]*")[^"]*"/) { m in m.output.1 + masque + "\"" }
        s.replace(/[0-9A-Fa-f]{32,}/) { _ in masque }
        return s
    }

    /// Masque plus strict, pour une ligne abimee, un fragment ou un debordement : un
    /// journal d'ESP-IDF qui coupe la reponse a `json cle nouvelle` y laisse une part
    /// de la cle, sans guillemet fermant ni 32 hexa d'un bloc. En plus de `masquerCle` :
    /// le champ `"cle":"<hexa>` meme sans guillemet fermant, toute suite d'au moins 2
    /// hexa suivie d'un guillemet (la fin d'une cle coupee, ou reprise apres un journal
    /// intercale ; les empreintes aussi, tant pis), et toute suite de 16 hexa ou plus.
    /// Jamais sur une ligne de console ordinaire : le nom SRP fait 16 hexa.
    public static func masquerCleStricte(_ texte: String) -> String {
        var s = masquerCle(texte)
        s.replace(/("cle"\s*:\s*")[0-9A-Fa-f]+/) { m in m.output.1 + masque }
        s.replace(/[0-9A-Fa-f]{2,}(?=")/) { _ in masque }
        s.replace(/[0-9A-Fa-f]{16,}/) { _ in masque }
        return s
    }

    /// Masque juge sur la ligne decoupee comme la console du pont la decoupe
    /// (`LigneCommande.arguments`) : apres `mesh cles` ou `json cle nouvelle` (casse
    /// quelconque), tout ce qui suit est masque, quelle que soit sa forme (guillemets,
    /// echappements comme `4041\x42` que le pont retire) : un masque par mot ; les mots de
    /// la commande restent tels qu'ecrits. La commande commence la ligne, ou suit
    /// l'invite `amaran>` (echo de la console en mode texte), `›`, `«` ou `id=<n>`
    /// (journal des envois, citations de l'app) ; une citation (commande qui suit `«`) finit
    /// a `»` ; sinon, tout jusqu'au bout du texte est masque (un `»` tape n'arrete rien). Ailleurs, rien :
    /// le texte d'usage du pont (`erreur : mesh cles <reseau 32 hexa> ...`) reste lisible.
    /// Sans rien a masquer, le texte est rendu tel quel.
    static func masquerArgumentsSecrets(_ texte: String) -> String {
        let octets = Array(texte.utf8)
        let args = LigneCommande.arguments(octets)
        // Mots de chaque argument : entre guillemets, ou avec `\ `, un argument en porte plusieurs.
        var mots: [(valeur: [UInt8], arg: Int, premier: Bool)] = []
        for (j, a) in args.enumerated() {
            for (k, m) in a.valeur.split(whereSeparator: { $0 == 0x20 || $0 == 0x09 }).enumerated() {
                mots.append((Array(m), j, k == 0))
            }
        }
        func est(_ i: Int, _ mot: [UInt8]) -> Bool {
            i < mots.count && mots[i].valeur.map { (0x41...0x5A).contains($0) ? $0 + 0x20 : $0 } == mot
        }
        func apresUnPrefixe(_ i: Int) -> Bool {
            guard mots[i].premier else { return false }
            guard mots[i].arg > 0 else { return true }
            let avant = args[mots[i].arg - 1].valeur
            if prefixesDeCommande.contains(avant) { return true }
            return avant.count > 3 && avant.starts(with: Array("id=".utf8)) && avant.dropFirst(3).allSatisfy { (0x30...0x39).contains($0) }
        }
        var sortie: [UInt8] = []
        var copie = 0
        var aMasque = false
        var i = 0
        while i < mots.count {
            let longueur = est(i, Array("mesh".utf8)) && est(i + 1, Array("cles".utf8)) ? 2
                : est(i, Array("json".utf8)) && est(i + 1, Array("cle".utf8)) && est(i + 2, Array("nouvelle".utf8)) ? 3 : 0
            guard longueur > 0, apresUnPrefixe(i) else {
                i += 1
                continue
            }
            // Seule une citation de l'app (la commande suit `«`) finit a `»` : la commande y est
            // deja masquee seule avant d'etre citee. Un `»` tape dans une commande n'arrete rien.
            let cite = mots[i].arg > 0 && args[mots[i].arg - 1].valeur == debutDeCitation
            var fin = i + longueur
            while fin < mots.count, !(cite && mots[fin].premier && args[mots[fin].arg].valeur == finDeCitation) { fin += 1 }
            let caches = fin - i - longueur
            guard caches > 0 else {
                i = fin
                continue
            }
            // Les mots de la commande restent tels qu'ecrits (guillemets, casse, espaces) ;
            // si la suite partage leur argument (`"mesh cles <cle>"`), ils sont recrits.
            let dernier = i + longueur - 1
            if dernier + 1 < mots.count, mots[dernier + 1].arg == mots[dernier].arg {
                sortie += octets[copie..<args[mots[i].arg].debut]
                sortie += Array(mots[i...dernier].map { $0.valeur }.joined(separator: [0x20]))
            } else {
                sortie += octets[copie..<args[mots[dernier].arg].fin]
            }
            for _ in 0..<caches { sortie += [0x20] + Array(masque.utf8) }
            if fin < mots.count {
                sortie.append(0x20)
                copie = args[mots[fin].arg].debut
            } else {
                copie = octets.count
            }
            aMasque = true
            i = fin
        }
        guard aMasque else { return texte }
        sortie += octets[copie...]
        return String(decoding: sortie, as: UTF8.self)
    }

    /// Ce qui precede une commande dans un texte : l'invite de la console, le journal des
    /// envois (`›`, `id=<n>`), une citation (`«`).
    private static let prefixesDeCommande: [[UInt8]] = ["amaran>", "›", "«"].map { Array($0.utf8) }
    private static let debutDeCitation = Array("«".utf8)
    private static let finDeCitation = Array("»".utf8)

    private static let masque = String(repeating: "•", count: 8)
}

extension ElementRecu {
    /// L'element tel qu'il peut entrer dans un journal, une console ou un affichage :
    /// sans cle (Mesh ou UDP). Ligne machine : `LigneMachine.sansCle`. Ligne abimee,
    /// fragment, debordement : masque strict (une cle coupee n'a plus ses 32 hexa
    /// d'un bloc). Texte : masque ordinaire, strict s'il finit par `}` (la fin d'une
    /// ligne machine dont le debut s'est perdu).
    public var sansCle: ElementRecu {
        switch self {
        case .machine(let l):
            return .machine(l.sansCle)
        case .texte(var t):
            t.texte = t.texte.hasSuffix("}") ? PolitiqueCommandes.masquerCleStricte(t.texte)
                                              : PolitiqueCommandes.masquerCle(t.texte)
            return .texte(t)
        case .fragment(let s):
            return .fragment(PolitiqueCommandes.masquerCleStricte(s))
        case .abimee(let raison, let brut):
            return .abimee(raison: raison, brut: PolitiqueCommandes.masquerCleStricte(brut))
        case .debordement(let s):
            return .debordement(PolitiqueCommandes.masquerCleStricte(s))
        case .versionInconnue, .invalide:
            return self
        }
    }
}
