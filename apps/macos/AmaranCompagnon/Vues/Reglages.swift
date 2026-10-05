// Fenetre Reglages (spec 3b, section 8) : General, et « Acces reseau Thread » (comme
// Halo Compagnon, commit e114cd5).
import AmaranProtocole
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

/// Onglet General : le dossier d'amaran Desktop autorise, la derniere sauvegarde.
struct ReglagesGeneral: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        Form {
            Section("amaran Desktop") {
                LabeledContent("Dossier autorisé") {
                    Text(verbatim: pont.dossierAmaran?.path(percentEncoded: false) ?? "aucun")
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
                    Text(verbatim: pont.derniereSauvegarde?.formatted(date: .long, time: .shortened) ?? "jamais")
                }
            } header: {
                Text("Sauvegarde chiffrée")
            } footer: {
                Text("L'app lit la base d'amaran Desktop sans jamais y écrire. La copie des clés reste dans le trousseau de ce Mac ; une sauvegarde chiffrée la garde ailleurs (iCloud Drive), si ce Mac est perdu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
