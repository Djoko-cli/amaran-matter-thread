// Repris de Halo Compagnon (commit e114cd5) : fenetre, menus, reglages ; francais et anglais.
import AmaranProtocole
import SwiftUI

@main
struct AmaranCompagnonApp: App {
    @State private var pont = Self.creerPont()
    /// Lu dans `body` : un changement de langue reconstruit aussi les menus.
    @AppStorage(ReglageLangue.cle) private var choixLangue: ChoixLangue = .systeme

    init() {
        // Avant la premiere vue : les textes calcules partent dans la bonne langue. Pas sous
        // les tests (hote de tests) : les vraies preferences de l'app ne sont pas touchees.
        if !Self.hoteDeTests { ReglageLangue.appliquerAuLancement() }
    }

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
        let _ = choixLangue
        WindowGroup("Amaran Compagnon", id: "principale") {
            ContenuPrincipal(ecranInitial: Self.ecranDemande)
                .environment(pont)
                .langueDeLInterface()
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
            // Titres calcules (tr) et non `LocalizedStringKey` : les menus ne
            // recoivent pas la locale de l'environnement des fenetres.
            CommandGroup(after: .newItem) {
                Button(tr("Mode démo")) { pont.connecter(.demo) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button(tr("Rafraîchir l'état (json etat)")) { pont.rafraichir() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(!pont.peutCommander)
                Divider()
                Button(tr("Libérer le port")) { pont.libererPort() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(pont.phase == .ferme || pont.estDemo)
            }
        }

        Settings {
            FenetreReglages()
                .environment(pont)
                .langueDeLInterface()
        }
    }
}

extension View {
    /// Locale de l'environnement : celle de la langue choisie. `Text("...")`
    /// y cherche sa traduction et les formats (dates, nombres) la suivent.
    func langueDeLInterface() -> some View {
        modifier(LangueDeLInterface())
    }
}

private struct LangueDeLInterface: ViewModifier {
    func body(content: Content) -> some View {
        // Lire la locale ici fait dependre la vue de la langue (Observation).
        content.environment(\.locale, Localisation.partagee.locale)
    }
}
