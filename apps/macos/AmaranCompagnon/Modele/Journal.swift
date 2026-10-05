// Repris de Halo Compagnon (commit e114cd5) : la console et les rejets (les trames et
// les courbes viendront au plan 3b-2).
import AmaranProtocole
import Foundation

/// Ligne de la console.
struct LigneConsole: Identifiable, Sendable {
    enum Genre: Equatable, Sendable {
        /// Ligne envoyee par l'app.
        case envoi(OrigineCommande)
        /// Texte recu, classe (2.4).
        case texte(ClasseTexte)
        case fragment
        /// `reponse` ou `ordre` rendu lisible.
        case retour(ok: Bool, session: Bool)
        /// Message `log` (mode `json log 1`).
        case log
        /// Annonce de l'app elle-meme.
        case note(grave: Bool)
    }

    let id: Int
    let date: Date
    let genre: Genre
    let texte: String
    /// `id` de la commande a laquelle la ligne se rattache.
    let numero: Int?
}

/// Ligne machine rejetee (diagnostic du tableau de bord).
struct Rejet: Identifiable, Sendable {
    let id: Int
    let date: Date
    let raison: String
    let brut: String
}

/// Tableau borne : les plus anciens sortent.
struct Borne<Element> {
    private(set) var elements: [Element] = []
    let capacite: Int

    init(capacite: Int) { self.capacite = capacite }

    mutating func ajouter(_ e: Element) {
        elements.append(e)
        if elements.count > capacite + capacite / 10 { elements.removeFirst(elements.count - capacite) }
    }

    mutating func vider() { elements.removeAll() }
}

extension Borne: Sendable where Element: Sendable {}
