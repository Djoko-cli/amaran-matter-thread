// Repris de Halo Compagnon (commit e114cd5) : fenetre, menus, reglages ; francais seulement.
import AmaranProtocole
import SwiftUI

@main
struct AmaranCompagnonApp: App {
    @State private var pont = Self.creerPont()

    /// Les tests tournent dans l'app (TEST_HOST) : sous ce lanceur, ni le vrai trousseau,
    /// ni les vraies preferences (signet d'amaran Desktop, dernier pont) ne sont touches.
    private static let hoteDeTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private static func creerPont() -> Pont {
        guard hoteDeTests else { return Pont() }
        let suite = "fr.djoko.amaran.hote.tests"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(ReseauDemo.reseau),
                    trousseauPonts: TrousseauPontsMemoire(), trousseauPontsDemo: TrousseauPontsMemoire(),
                    preferences: UserDefaults(suiteName: suite)!)
    }

    /// `--args -ecran commandes` : ecran affiche au lancement.
    private static var ecranDemande: Ecran {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "-ecran"), i + 1 < a.count, let e = Ecran(rawValue: a[i + 1]) else { return .tableau }
        return e
    }

    var body: some Scene {
        WindowGroup("Amaran Compagnon", id: "principale") {
            ContenuPrincipal(ecranInitial: Self.ecranDemande)
                .environment(pont)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    // "Amaran Compagnon.app" --args -demo : demarre directement en mode demo.
                    if CommandLine.arguments.contains("-demo"), pont.source == nil { pont.connecter(.demo) }
                    // Dossier d'amaran Desktop deja autorise : la base est relue a chaque lancement.
                    if !Self.hoteDeTests, pont.dossierAmaran != nil { pont.relireBase() }
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Mode démo") { pont.connecter(.demo) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Rafraîchir l'état (json etat)") { pont.rafraichir() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(!pont.peutCommander)
                Divider()
                Button("Libérer le port") { pont.libererPort() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(pont.phase == .ferme || pont.estDemo)
            }
        }

        Settings {
            FenetreReglages()
                .environment(pont)
        }
    }
}
