// Chargement du pont par l'USB (spec 3b, section 5) : les quatre controles
// d'outils/cles_amaran.py, lus dans les reponses du pont (docs/PROTOCOLE-JSON.md 6.4).
import Foundation

public enum ErreurChargement: Error, Sendable, Equatable, CustomStringConvertible {
    case pasLePont
    case commande(String, String)
    case empreintes(rendues: String, attendues: String)
    case listeNonEnregistree
    case pasRedemarre
    case apresRedemarrage(String)

    public var description: String {
        switch self {
        case .pasLePont:
            "Ce port n'est pas un pont amaran en mode machine : rien n'a été envoyé."
        case .commande(let c, let raison):
            "« \(PolitiqueCommandes.masquerCle(c)) » : \(raison). Le pont n'est pas redémarré : relancer le chargement."
        case .empreintes(let r, let a):
            "Le pont a enregistré d'autres clés (empreintes \(r), attendues \(a)) : ne pas le redémarrer, relancer le chargement."
        case .listeNonEnregistree:
            "Le pont n'a pas enregistré la liste des lampes : ne pas le redémarrer, relancer le chargement."
        case .pasRedemarre:
            "Le pont n'a pas redémarré : vérifier l'onglet Clés après un redémarrage."
        case .apresRedemarrage(let ecart):
            "Après le redémarrage, le pont ne montre pas ce qui a été chargé : \(ecart)."
        }
    }
}

public enum VerificationChargement {
    /// `ok cles <EMPREINTE RESEAU> <EMPREINTE APPLICATION> (...)` : les empreintes rendues.
    public static func empreintesRendues(_ texte: [String]) -> (reseau: String, application: String)? {
        for l in texte {
            if let m = l.firstMatch(of: /ok cles ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{8})(?:\s|$)/) {
                return (String(m.output.1).uppercased(), String(m.output.2).uppercased())
            }
        }
        return nil
    }

    /// Reponse a la derniere `mesh lampe` : `... ; liste de <N> lampe(s) enregistree (...)`.
    public static func listeEnregistree(_ texte: [String]) -> Int? {
        for l in texte {
            if let m = l.firstMatch(of: /; liste de (\d+) lampe\(s\) enregistree/) { return Int(m.output.1) }
        }
        return nil
    }

    /// Ce que le pont montre apres son redemarrage (`config`, blocs `mesh` et
    /// `lampe`), compare a ce qui a ete charge : nil s'il est identique.
    public static func ecart(_ attendu: ApercuReseau, mesh: ConfigMesh?, lampes: [Int: ConfigLampe]) -> String? {
        guard let pont = ApercuReseau.dePont(mesh: mesh, lampes: lampes) else { return "pas de clés" }
        guard pont.memesCles(que: attendu) else {
            return "empreintes \(pont.empreinteReseau) \(pont.empreinteApplication), attendues "
                + "\(attendu.empreinteReseau) \(attendu.empreinteApplication)"
        }
        guard pont.lampes.count == attendu.lampes.count else {
            return "\(pont.lampes.count) lampe(s), \(attendu.lampes.count) attendue(s)"
        }
        for (i, (p, a)) in zip(pont.lampes, attendu.lampes).enumerated()
        where ApercuReseau.identites([p]) != ApercuReseau.identites([a]) {
            return "lampe \(i + 1) différente"
        }
        return nil
    }
}
