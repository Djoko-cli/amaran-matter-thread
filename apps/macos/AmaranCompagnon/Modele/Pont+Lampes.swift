// Gestes des lampes (docs/PROTOCOLE-JSON.md 6.4) : marche, arret, niveau, relecture,
// retrait de Maison et retour, periode de relecture, voyant.
import AmaranProtocole
import Foundation

/// Ce que l'ecran montre d'une lampe : sa config (identite) et son etat.
struct VueLampe: Identifiable, Equatable {
    let numero: Int
    let config: ConfigLampe?
    let etat: BlocLampe?
    let dernierOrdre: EvenementOrdre?
    var id: Int { numero }

    var nom: String { config?.nom ?? "Lampe \(numero)" }
    var dansMaison: Bool { etat?.maison?.endpoint != nil }
}

extension Pont {
    /// Les lampes de la liste du pont, dans l'ordre.
    var lampes: [VueLampe] {
        etat.numerosLampes.map { n in
            VueLampe(numero: n, config: etat.configLampes[n]?.valeur, etat: etat.lampes[n]?.valeur,
                     dernierOrdre: etat.derniersOrdres[n]?.valeur)
        }
    }

    func allumer(lampe n: Int, _ marche: Bool) {
        envoyer("lampe \(n) \(marche ? "on" : "off")")
    }

    /// Niveau en pour cent (le pont garde le pour cent entier) : 0 a 1000 sur le fil.
    func niveau(lampe n: Int, pourCent: Int, fini: Bool) {
        curseur("lampe \(n) niveau \(max(0, min(100, pourCent)) * 10)", cle: "niveau\(n)", fini: fini)
    }

    func relire(lampe n: Int) {
        envoyer("lampe \(n) releve")
    }

    /// Retirer de Maison (apres la confirmation de l'ecran), ou remettre.
    func exposer(lampe n: Int, dansMaison: Bool) {
        envoyer("mesh lampe \(n) \(dansMaison ? "afficher" : "masquer")")
    }

    /// Periode de relecture des lampes, en secondes (1 a 60).
    func reglerReleve(secondes: Int) {
        envoyer("mesh releve \(max(1, min(60, secondes)))")
    }

    func testerVoyant(_ oui: Bool) {
        envoyer(oui ? "led test" : "led stop")
    }

    /// Texte de la confirmation de « Retirer de Maison » (spec 3b, decision 7 ; banc 2
    /// du plan 3a).
    static let avertissementRetrait = """
        Maison retire la tuile de la lampe. Remise, elle reviendra comme un nouvel accessoire : \
        son nom dans Maison, sa pièce si elle diffère de celle du pont, ses scènes et ses \
        automatisations seront perdus.
        """
}
