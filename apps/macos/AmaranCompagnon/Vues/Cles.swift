// Panneau « Cles » (spec 3b, section 5) : trois colonnes d'empreintes (amaran Desktop,
// ce Mac, le pont), l'ecart et le geste qui convient, la sauvegarde chiffree. Aucune
// cle n'est jamais affichee.
import AmaranProtocole
import AppKit
import SwiftUI

struct CarteCles: View {
    @Environment(Pont.self) private var pont
    @State private var confirmerChargement: SourceCles?
    @State private var exporter = false
    @State private var importer = false

    var body: some View {
        Carte(titre: "Clés", icone: "key", accent: pont.ecartsCles.isEmpty ? .secondary : .orange) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Réseau").foregroundStyle(.secondary)
                    Text("Application").foregroundStyle(.secondary)
                    Text("Lampes").foregroundStyle(.secondary)
                }
                ligne("amaran Desktop", pont.base, absent: pont.erreurBase ?? (pont.dossierAmaran == nil ? "dossier non autorisé" : "non lue"))
                ligne("Ce Mac", pont.copie, absent: "aucune copie")
                ligne("Le pont", pont.apercuPont, absent: pont.etat.mesh == nil ? "–" : "sans clés")
            }
            .font(.callout)
            ForEach(pont.ecartsCles, id: \.texte) { e in
                Label(e.texte, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(pont.modelesACataloguer, id: \.texte) { m in
                Label(m.texte, systemImage: "questionmark.diamond")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .echec(let raison) = pont.chargement {
                Label(raison, systemImage: "xmark.octagon").foregroundStyle(.red).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .reussi(let d) = pont.chargement {
                Label("Pont chargé \(d.formatted(.relative(presentation: .named))).", systemImage: "checkmark.seal")
                    .foregroundStyle(.green).font(.callout)
            }
            HStack {
                if pont.dossierAmaran == nil && !pont.estDemo {
                    Button("Autoriser le dossier d'amaran Desktop…") { ChoixFichiers.dossierAmaran(pont) }
                } else {
                    Button("Copier depuis amaran Desktop") { pont.copierDepuisAmaranDesktop() }
                    Button("Relire") { pont.relireBase() }
                }
                Menu("Charger le pont") {
                    Button("Depuis amaran Desktop") { confirmerChargement = .amaranDesktop }
                        .disabled(pont.dossierAmaran == nil && !pont.estDemo)
                    Button("Depuis la copie de ce Mac") { confirmerChargement = .trousseau }
                        .disabled(pont.copie == nil)
                }
                .disabled(!pont.peutCommander || pont.aDistance || pont.chargement.actif)
                .help(pont.aDistance ? "Le chargement des clés passe par l'USB : le pont le refuse par le réseau." : "")
                .fixedSize()
            }
            .controlSize(.small)
            HStack {
                Button("Exporter une sauvegarde…") { exporter = true }
                    .disabled(pont.copie == nil)
                Button("Importer une sauvegarde…") { importer = true }
                if let d = pont.derniereSauvegarde {
                    Text("dernière : \(d.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
        }
        .confirmationDialog("Charger le pont ?", isPresented: Binding(get: { confirmerChargement != nil },
                                                                      set: { if !$0 { confirmerChargement = nil } }),
                            presenting: confirmerChargement) { s in
            Button("Charger et redémarrer le pont") { pont.chargerPont(depuis: s) }
        } message: { _ in
            Text("Le pont reçoit les clés et la liste des lampes par l'USB, les vérifie, puis redémarre. Maison garde les lampes déjà connues (même MAC).")
        }
        .sheet(isPresented: $exporter) { FeuilleExport() }
        .sheet(isPresented: $importer) { FeuilleImport() }
    }

    @ViewBuilder
    private func ligne(_ titre: String, _ a: ApercuReseau?, absent: String) -> some View {
        GridRow {
            Text(verbatim: titre)
            if let a {
                Text(verbatim: a.empreinteReseau).monospaced()
                Text(verbatim: a.empreinteApplication).monospaced()
                Text(verbatim: "\(a.lampes.count)")
            } else {
                Text(verbatim: absent).foregroundStyle(.secondary).gridCellColumns(3)
            }
        }
    }
}

/// Panneaux du systeme : le dossier d'amaran Desktop (signet), les sauvegardes.
@MainActor
enum ChoixFichiers {
    static func dossierAmaran(_ pont: Pont) {
        let p = NSOpenPanel()
        p.message = "Choisir le dossier « amaran Desktop » (Bibliothèque › Containers › amaran Desktop › Data › Library › Application Support) : l'app le lira, sans jamais y écrire."
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.showsHiddenFiles = true
        p.directoryURL = BaseAmaranDesktop.dossierHabituel
        if p.runModal() == .OK, let url = p.url { pont.autoriserDossier(url) }
    }

    static func enregistrerSauvegarde() -> URL? {
        let p = NSSavePanel()
        p.message = "Où ranger la sauvegarde chiffrée ? iCloud Drive la garde même si ce Mac est perdu."
        p.nameFieldStringValue = "Réseau amaran.sauvegarde"
        return p.runModal() == .OK ? p.url : nil
    }

    static func ouvrirSauvegarde() -> URL? {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        return p.runModal() == .OK ? p.url : nil
    }
}

/// « Exporter une sauvegarde » : la phrase de passe deux fois, jamais gardee.
private struct FeuilleExport: View {
    @Environment(Pont.self) private var pont
    @Environment(\.dismiss) private var fermer
    @State private var phrase = ""
    @State private var confirmation = ""
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Exporter une sauvegarde chiffrée", systemImage: "lock.doc").font(.title3.weight(.semibold))
            Text("La copie des clés de ce Mac, chiffrée par une phrase de passe (12 caractères au moins). Sans elle, la sauvegarde est perdue : rien ne permet de la retrouver.")
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Phrase de passe", text: $phrase)
            SecureField("La même, une seconde fois", text: $confirmation)
            if let erreur { Text(verbatim: erreur).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { fermer() }
                Button("Exporter…") {
                    do {
                        try Sauvegarde.verifierPhrase(phrase, confirmation: confirmation)
                        guard let url = ChoixFichiers.enregistrerSauvegarde() else { return }
                        try pont.exporterSauvegarde(vers: url, phrase: phrase, confirmation: confirmation)
                        phrase = ""
                        confirmation = ""
                        fermer()
                    } catch {
                        erreur = String(describing: error)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// « Importer une sauvegarde » : fichier, phrase, empreintes, puis remplacer la copie.
private struct FeuilleImport: View {
    @Environment(Pont.self) private var pont
    @Environment(\.dismiss) private var fermer
    @State private var fichier: URL?
    @State private var phrase = ""
    @State private var lue: ReseauMesh?
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Importer une sauvegarde chiffrée", systemImage: "lock.open").font(.title3.weight(.semibold))
            HStack {
                Text(verbatim: fichier?.lastPathComponent ?? "Aucun fichier choisi").foregroundStyle(.secondary)
                Spacer()
                Button("Choisir…") { fichier = ChoixFichiers.ouvrirSauvegarde() }
            }
            SecureField("Phrase de passe", text: $phrase)
            if let lue {
                let a = lue.apercu
                Text(verbatim: "Empreintes \(a.empreinteReseau) \(a.empreinteApplication), \(a.lampes.count) lampe(s) : \(a.lampes.map(\.nom).joined(separator: ", ")).")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let erreur { Text(verbatim: erreur).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) {
                    lue = nil
                    fermer()
                }
                if let lue {
                    Button("Remplacer la copie de ce Mac") {
                        do {
                            try pont.remplacerCopie(par: lue)
                            self.lue = nil
                            fermer()
                        } catch {
                            erreur = String(describing: error)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Ouvrir") {
                        guard let fichier else { return }
                        do {
                            lue = try pont.lireSauvegarde(fichier, phrase: phrase)
                            phrase = ""
                            erreur = nil
                        } catch {
                            erreur = String(describing: error)
                        }
                    }
                    .disabled(fichier == nil || phrase.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        // Meilleur effort : Swift ne garantit pas l'effacement, on lache au moins la reference.
        .onDisappear { lue = nil }
    }
}
