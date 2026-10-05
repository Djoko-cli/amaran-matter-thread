// Fenetre Reglages (spec 3b, section 8) : l'onglet General (l'onglet « Acces reseau
// Thread » viendra au plan 3b-2, comme celui de Halo Compagnon).
import AmaranProtocole
import SwiftUI

struct FenetreReglages: View {
    var body: some View {
        TabView {
            Tab("Général", systemImage: "gearshape") {
                ReglagesGeneral()
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
