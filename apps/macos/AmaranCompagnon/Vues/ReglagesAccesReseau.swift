// Reglages › Acces reseau Thread (spec 3b, section 8), repris de ReglagesAccesReseau de Halo
// Compagnon (commit e114cd5) : les ponts dont ce Mac a la cle, avec l'etat de leur
// session, et la cle du pont branche en USB (10.2 : la cle ne passe que par l'USB).
import AmaranProtocole
import SwiftUI

struct ReglagesAccesReseau: View {
    @Environment(Pont.self) private var pont
    @State private var aOublier: PontConnu?

    var body: some View {
        Form {
            Section {
                if pont.pontsConnus.isEmpty {
                    Text("Aucun pont : brancher un pont en USB, le connecter (menu Source), puis « Activer l'accès réseau… » ci-dessous (« Nouvelle clé… » si le pont a déjà une clé).")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(pont.pontsConnus) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: pont.titre(pont: p))
                            Text(verbatim: tr("\(p.hote) · clé \(p.empreinte)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            LigneSession(etat: pont.etatSession(pour: p.nom))
                        }
                        Spacer()
                        Button("Oublier…", role: .destructive) { aOublier = p }
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Ponts connus de ce Mac")
            } footer: {
                Text("Le pont garde sa clé : l'oublier ne la change pas, mais ce Mac ne peut plus ouvrir de session réseau avec lui.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                if pont.accesReseau == .inconnu {
                    // Pas de pont par l'USB, ou un pont connecte sans nom SRP (pas encore
                    // dans le reseau Thread) : les deux cas se disent differemment.
                    Text(verbatim: pont.texteSansAccesReseau)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    AccesReseau()
                }
            } header: {
                Text("Pont branché en USB")
            } footer: {
                Text("La clé ne passe que par l'USB. Elle est rangée dans le trousseau de ce Mac, sans jamais être affichée : seule son empreinte l'est. À la première session réseau, macOS demande l'accès au réseau local.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Oublier ce pont ?", isPresented: Binding(get: { aOublier != nil }, set: { if !$0 { aOublier = nil } }),
                            presenting: aOublier) { p in
            Button("Oublier \(p.hote)", role: .destructive) { pont.oublierPont(p.nom) }
        } message: { p in
            Text("La clé de \(p.hote) est retirée du trousseau de ce Mac ; le pont garde la sienne. Si ce pont est la source en cours, la session réseau se ferme. Pour revenir : brancher le pont en USB, puis « Nouvelle clé… » (« Activer l'accès réseau… » si le pont n'a pas de clé).")
        }
    }
}

/// Etat de la session d'un pont connu, avec sa couleur.
private struct LigneSession: View {
    let etat: EtatSessionPont

    var body: some View {
        Label {
            Text(verbatim: etat.libelle)
        } icon: {
            Image(systemName: icone)
        }
        .font(.caption)
        .foregroundStyle(couleur)
    }

    private var icone: String {
        switch etat {
        case .aucune: "circle"
        case .enCours: "circle.dotted"
        case .ouverte: "checkmark.circle.fill"
        case .refusee: "exclamationmark.triangle.fill"
        }
    }

    private var couleur: Color {
        switch etat {
        case .aucune: .secondary
        case .enCours: .orange
        case .ouverte: .green
        case .refusee: .red
        }
    }
}

/// Cle du transport reseau du pont branche en USB (10.2) : etat et creation.
struct AccesReseau: View {
    @Environment(Pont.self) private var pont
    @State private var confirmation = false

    var body: some View {
        HStack {
            switch pont.accesReseau {
            case .sansCle:
                Text("Accès réseau : aucune clé").foregroundStyle(.secondary)
                Spacer()
                Button("Activer l'accès réseau…") { confirmation = true }
            case .cleConnue(_, let e):
                Text("Clé \(e) connue de ce Mac").foregroundStyle(.secondary)
                Spacer()
                Button("Nouvelle clé…") { confirmation = true }
            case .cleInconnue(_, let e):
                Text("Clé \(e) inconnue de ce Mac").foregroundStyle(.orange)
                Spacer()
                Button("Nouvelle clé…") { confirmation = true }
            case .inconnu:
                EmptyView()
            }
        }
        .font(.callout)
        .controlSize(.small)
        .disabled(!pont.peutCommander || pont.aDistance || pont.creationCleEnCours)
        .confirmationDialog(titreConfirmation, isPresented: $confirmation) {
            Button(sansCle ? tr("Activer l'accès réseau") : tr("Créer la nouvelle clé")) { pont.creerCle() }
        } message: {
            Text(verbatim: Self.texteConfirmation(sansCle: sansCle))
        }
    }

    /// Le pont sans cle n'a ni port ouvert ni session : rien ne tombe. Avec une cle, il la
    /// remplace, et toute session en cours tombe (10.2).
    static func texteConfirmation(sansCle: Bool) -> String {
        sansCle
            ? tr("Le pont crée sa clé et ouvre le port 5480 ; la clé est rangée dans le trousseau de ce Mac.")
            : tr("Le pont remplace sa clé : les sessions réseau en cours tombent, y compris celles d'autres Mac ou de scripts, qui devront obtenir la nouvelle clé par l'USB. La nouvelle clé est rangée dans le trousseau de ce Mac.")
    }

    private var sansCle: Bool {
        if case .sansCle = pont.accesReseau { true } else { false }
    }

    private var titreConfirmation: String {
        sansCle ? tr("Activer l'accès réseau ?") : tr("Créer une nouvelle clé réseau ?")
    }
}
