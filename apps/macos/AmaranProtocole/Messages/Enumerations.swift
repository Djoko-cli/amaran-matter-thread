// Repris de Halo Compagnon (commit e114cd5) : EnumeTolerante ; les valeurs sont
// celles du pont amaran (docs/PROTOCOLE-JSON.md).
import Foundation

/// Enumeration du protocole qui range une valeur inconnue sous `inconnu`
/// sans echouer (section 8 : ajouts additifs dans une meme `v`).
public protocol EnumeTolerante: RawRepresentable, Codable, Sendable, Hashable, CaseIterable
where RawValue == String {
    static var inconnu: Self { get }
}

extension EnumeTolerante {
    public init(from decoder: any Decoder) throws {
        let conteneur = try decoder.singleValueContainer()
        let brut = try conteneur.decode(String.self)
        self = Self(rawValue: brut) ?? Self.inconnu
    }

    public func encode(to encoder: any Encoder) throws {
        var conteneur = encoder.singleValueContainer()
        try conteneur.encode(rawValue)
    }
}

/// Motif du voyant (7.4), repris du pont Halo.
public enum MotifLed: String, EnumeTolerante {
    case identification
    case desappairage
    case redemarrage
    case injoignable
    /// Ici : Bluetooth Mesh inoperant.
    case panneRadio = "panne_radio"
    case livree
    case nonAppaire = "non_appaire"
    case horsReseau = "hors_reseau"
    case operationnel
    case inconnu
}

/// `reponse.etape`.
public enum EtapeReponse: String, EnumeTolerante {
    case debut, fin, inconnu
}

/// `reponse.code` (6.3).
public enum CodeReponse: String, EnumeTolerante {
    case ok, accepte
    case enCours = "en_cours"
    case erreur, usage
    case commandeInconnue = "inconnue"
    case tropLong = "trop_long"
    case cadence
    /// A distance, commande hors de la liste blanche (10.5) : rien n'est execute.
    case interdite
    /// A distance, `id` plus ancien que les 8 dernieres reponses gardees : sa reponse est
    /// oubliee, aucune autre ne viendra (10.4). Le renvoi d'un `id` encore en cours, lui,
    /// est ignore en silence.
    case dejaTraite = "deja_traite"
    case inconnu
}

/// `reponse.suite`.
public enum SuiteReponse: String, EnumeTolerante {
    case ordre, aucune, inconnu
}

/// `fin.cause`.
public enum CauseFin: String, EnumeTolerante {
    case commande, bail, inconnu
}

/// `ordre.issue` (7.1).
public enum IssueOrdre: String, EnumeTolerante {
    case confirme, abandon, tenu, inconnu
}

/// `etat.lampe.consigne.phase`.
public enum PhaseOrdre: String, EnumeTolerante {
    case repos, trames, attente, inconnu
}

/// Cause probable d'un Bluetooth Mesh inoperant (`etat.pont.mesh.diag`, `alerte.diag`).
public enum DiagMesh: String, EnumeTolerante {
    case ok
    case clesAbsentes = "cles_absentes"
    case pasEntre = "pas_entre"
    case clesPerimees = "cles_perimees"
    case ivFaux = "iv_faux"
    case inconnu
}

/// `alerte.quoi` (7.2).
public enum QuoiAlerte: String, EnumeTolerante {
    case releves, mesh, inconnu
}

/// `lampe.quoi` (7.3).
public enum QuoiLampe: String, EnumeTolerante {
    case entree, masquee, remise, echec, inconnu
}

/// Capacites d'un modele (`config.catalogue`, `config.lampe`).
public enum Capacite: String, EnumeTolerante {
    case intensite, cct, couleur, inconnu
}

/// Type d'appareil Matter d'un modele.
public enum TypeAppareil: String, EnumeTolerante {
    case variable, temperature, couleur, inconnu
}

/// `log.niv`.
public enum NiveauLog: String, EnumeTolerante {
    case notice, alerte, inconnu
}

/// `hello.base.session.transport` (5.1).
public enum TransportSession: String, EnumeTolerante {
    case usb, udp, inconnu
}

/// `trame.sens` (7.6) : emise ou recue par le pont.
public enum SensTrame: String, EnumeTolerante {
    case tx, rx, inconnu
}

/// `trame.quoi` (7.6).
public enum QuoiTrame: String, EnumeTolerante {
    /// Marche ou intensite vers une lampe.
    case ordre
    /// Demande d'etat au groupe des lampes.
    case demande
    /// Etat renvoye par une lampe.
    case etat
    case inconnu
}

/// Type d'une adresse du bloc `reseau` `ip` (5.5).
public enum TypeAdresse: String, EnumeTolerante {
    /// Joignable du reseau local, par le routeur de bordure.
    case omr
    /// Interne au maillage Thread.
    case mlEid = "ml_eid"
    case autre
    case inconnu
}

/// Capacites annoncees par `hello` `identite` (`caps`, 5.1). L'app se regle sur
/// elles, pas sur la version du firmware ; une capacite inconnue est ignoree.
public enum CapPont: String, Sendable, CaseIterable {
    case matter, thread, mesh, catalogue, ordres, led, log
    /// Messages `trame` (7.6).
    case trames
    /// Canal par Thread (section 10).
    case udp
    /// `json cle` (10.2).
    case cle
    /// Texte des commandes a distance, en messages `texte` (10.4).
    case texte
}
