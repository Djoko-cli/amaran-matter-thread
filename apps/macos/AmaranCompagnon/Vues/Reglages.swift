// Fenetre Reglages (spec 3b, section 8) : General (langue, dossier d'amaran Desktop,
// sauvegarde, mises a jour, Thread Route), et « Acces reseau Thread » (comme Halo Compagnon,
// commit e114cd5 ; mises a jour et Thread Route : deploiement du 06/10).
import AmaranProtocole
import ServiceManagement
import SwiftUI

/// Onglets de la fenetre Reglages ; le choix est garde, et la carte « Thread et Matter »
/// du tableau de bord ouvre directement « Acces reseau Thread ».
enum OngletReglages: String {
    case general, accesReseau
    static let cle = "reglages.onglet"
}

struct FenetreReglages: View {
    @AppStorage(OngletReglages.cle) private var onglet: OngletReglages = .general

    var body: some View {
        TabView(selection: $onglet) {
            Tab("Général", systemImage: "gearshape", value: OngletReglages.general) {
                ReglagesGeneral()
            }
            Tab("Accès réseau Thread", systemImage: "point.3.connected.trianglepath.dotted",
                value: OngletReglages.accesReseau) {
                ReglagesAccesReseau()
            }
        }
    }
}

/// Onglet General : la langue de l'app, le dossier d'amaran Desktop autorise, la derniere sauvegarde,
/// les mises a jour, Thread Route.
struct ReglagesGeneral: View {
    @Environment(Pont.self) private var pont
    @Environment(MisesAJour.self) private var misesAJour
    @AppStorage(ReglageLangue.cle) private var choix: ChoixLangue = .systeme

    var body: some View {
        Form {
            Section {
                Picker("Langue", selection: Binding(get: { choix }, set: { nouveau in
                    choix = nouveau
                    // Dans la meme transaction : textes calcules et locale changent ensemble.
                    ReglageLangue.appliquer(nouveau)
                })) {
                    Text("Langue du système").tag(ChoixLangue.systeme)
                    Divider()
                    // Chaque langue sous son propre nom, quelle que soit la langue en vigueur.
                    Text(verbatim: "English").tag(ChoixLangue.anglais)
                    Text(verbatim: "Français").tag(ChoixLangue.francais)
                }
                .pickerStyle(.menu)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Le contenu des fenêtres change tout de suite. Les menus de macOS (Amaran Compagnon, Édition, Fenêtre…) et les boîtes du système suivent au prochain lancement. Les textes déjà consignés gardent leur langue jusqu'au suivant : lignes de la console, erreur de connexion, dernière ligne rejetée, erreur de saisie de la console.")
                    if ReglageLangue.relancePourLesMenus {
                        Label("Relancer l'app pour mettre aussi les menus dans cette langue.",
                              systemImage: "arrow.clockwise.circle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Section("amaran Desktop") {
                LabeledContent("Dossier autorisé") {
                    Text(verbatim: pont.dossierAmaran?.path(percentEncoded: false) ?? tr("aucun"))
                        .foregroundStyle(pont.dossierAmaran == nil ? .secondary : .primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Changer…") { ChoixFichiers.dossierAmaran(pont) }
                if let e = pont.erreurBase {
                    Text(verbatim: e).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                LabeledContent("Dernière exportée") {
                    Text(verbatim: pont.derniereSauvegarde.map {
                        $0.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: Localisation.partagee.locale))
                    } ?? tr("jamais"))
                }
            } header: {
                Text("Sauvegarde chiffrée")
            } footer: {
                Text("L'app lit la base d'amaran Desktop sans jamais y écrire. La copie des clés reste dans le trousseau de ce Mac ; une sauvegarde chiffrée la garde ailleurs (iCloud Drive), si ce Mac est perdu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Les mises a jour (Sparkle) : recherche et installation automatiques, cochees par defaut.
            Section("Mises à jour") {
                Toggle("Rechercher automatiquement",
                       isOn: Binding(get: { misesAJour.rechercheAuto }, set: { misesAJour.rechercheAuto = $0 }))
                Toggle("Installer automatiquement",
                       isOn: Binding(get: { misesAJour.installationAuto }, set: { misesAJour.installationAuto = $0 }))
                    .disabled(!misesAJour.rechercheAuto)
                Button("Rechercher les mises à jour…") { misesAJour.rechercher() }
                    .disabled(!misesAJour.peutRechercher)
            }
            SectionThreadRoute()
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Onglet General : Thread Route, le demon qui garde la route du Mac vers le reseau Thread. Son etat est
/// relu a chaque apparition de l'onglet et a chaque retour de l'app au premier plan : une installation ou une
/// approbation (Reglages Systeme) faites entre-temps s'y voient.
struct SectionThreadRoute: View {
    @State private var etat = EtatThreadRoute.lire()

    var body: some View {
        Section("Thread Route") {
            LabeledContent("État", value: etat.libelle)
            if let c = etat.consigne {
                Text(verbatim: c)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if etat == .aApprouver {
                Button("Ouvrir Réglages Système…") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        .onAppear { etat = EtatThreadRoute.lire() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            etat = EtatThreadRoute.lire()
        }
    }
}
