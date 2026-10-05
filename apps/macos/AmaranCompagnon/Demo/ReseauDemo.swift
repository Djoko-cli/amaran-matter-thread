// Le reseau du mode demo (spec 3b, section 8) : des cles et des MAC inventees,
// jamais celles de Djoko. Le trousseau de la demo en garde la copie ; le pont
// simule l'a chargee.
import AmaranProtocole
import Foundation

enum ReseauDemo {
    static let reseau = ReseauMesh(
        cleReseau: Data((0..<16).map { 0xA0 &+ UInt8($0) }),
        cleApplication: Data((0..<16).map { 0xC0 &+ UInt8($0) }),
        lampes: [
            LampeReseau(adresse: 0x0002, mac: "02:00:00:00:0D:01", nom: "Lampe bureau", code: 40065),
            LampeReseau(adresse: 0x0004, mac: "02:00:00:00:0D:02", nom: "Lumière fenêtre", code: 40065),
            LampeReseau(adresse: 0x0006, mac: "02:00:00:00:0D:03", nom: "Lampe du fond", code: 40065),
        ],
        source: .amaranDesktop,
        date: Date(timeIntervalSinceReferenceDate: 812_000_000))
}
