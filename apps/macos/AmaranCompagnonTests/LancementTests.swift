// Provisoire (plan 3b-1, Task 5) : une cible de tests sans fichier ne se genere pas.
// La Task 8 le remplace par les tests de bout en bout du mode demo.
import Foundation
import Testing

@Test func lAppHebergeLesTests() {
    #expect(Bundle.main.bundleIdentifier == "fr.djoko.amaran.compagnon")
}
