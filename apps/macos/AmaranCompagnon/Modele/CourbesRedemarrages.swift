// Repere des graphiques : les dates ou le pont a redemarre (nouveau `boot`, donc nouveau
// segment des series). Code pur, sans vue.
import AmaranProtocole
import Foundation

extension SeriesCourbes {
    /// Dates des changements de segment : le tas est publie a chaque periode, c'est la
    /// serie la plus fournie.
    var redemarrages: [Date] {
        var sortie: [Date] = []
        var precedent: Int?
        for p in tas {
            if let q = precedent, q != p.segment { sortie.append(p.date) }
            precedent = p.segment
        }
        return sortie
    }
}
