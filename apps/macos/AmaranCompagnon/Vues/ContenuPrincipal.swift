// Repris de Halo Compagnon (commit e114cd5) : fenetre, bandeaux, panneau de connexion.
// Deux ecrans en 3b-1 (les graphiques et les trames viendront au plan 3b-2).
import AmaranProtocole
import SwiftUI

enum Ecran: String, CaseIterable, Identifiable {
    case tableau, commandes

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .tableau: "Tableau de bord"
        case .commandes: "Commandes et console"
        }
    }

    var icone: String {
        switch self {
        case .tableau: "gauge.with.dots.needle.33percent"
        case .commandes: "slider.horizontal.3"
        }
    }
}

struct ContenuPrincipal: View {
    @Environment(Pont.self) private var pont
    @State private var ecran: Ecran
    @State private var confirmerLiberation = false

    init(ecranInitial: Ecran = .tableau) {
        _ecran = State(initialValue: ecranInitial)
    }

    var body: some View {
        @Bindable var pont = pont
        NavigationSplitView {
            List(selection: $ecran) {
                Section("Supervision") {
                    ForEach(Ecran.allCases) { e in
                        Label(e.titre, systemImage: e.icone).tag(e)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                PanneauConnexion()
                    .padding(12)
            }
        } detail: {
            VStack(spacing: 0) {
                if let alerte = pont.alerte {
                    Bandeau(texte: alerte.texte, couleur: .red, icone: "exclamationmark.octagon.fill")
                }
                if pont.estDemo {
                    Bandeau(texte: "Mode démo : un pont simulé à trois lampes ; ses clés et ses MAC sont inventées, et le trousseau de la démo est à part.",
                            couleur: .purple, icone: "play.rectangle.fill")
                }
                if let banc = pont.commandeDeBanc {
                    Bandeau(texte: "Commande en cours : « \(PolitiqueCommandes.masquerCle(banc.commande)) ». La console du pont ne lit plus rien jusqu'à la fin.",
                            couleur: .orange, icone: "hourglass")
                }
                if case .enCours(let etape) = pont.chargement {
                    Bandeau(texte: "Chargement du pont : \(etape)…", couleur: .blue, icone: "key")
                } else if pont.chargement == .attenteRedemarrage {
                    Bandeau(texte: "Chargement du pont : redémarrage, puis vérification…", couleur: .blue, icone: "key")
                }
                Group {
                    switch ecran {
                    case .tableau: TableauDeBord()
                    case .commandes: CommandesEtConsole()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Largeur ideale fixee : sans elle, un long texte donne sa largeur ideale
            // sur une ligne a la colonne de detail, et la barre laterale s'efface.
            .frame(minWidth: 560, idealWidth: 960, maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(ecran.titre)
            .toolbar { barreOutils }
        }
        .alert("Commande de plus de 20 minutes", isPresented: $pont.propositionFermeture) {
            Button("Fermer le port", role: .destructive) { pont.deconnecter() }
            Button("Attendre", role: .cancel) {}
        } message: {
            Text("La console du pont ne lit plus rien : fermer le port n'arrête pas la commande, mais libère l'app.")
        }
        .confirmationDialog("Libérer le port ?", isPresented: $confirmerLiberation) {
            Button("Libérer le port") { pont.libererPort() }
        } message: {
            Text("L'app envoie json 0 et ferme le port (DTR et RTS restent à 0) : idf.py flash pourra flasher. Rien ne se rouvre avant « Reconnecter ».")
        }
    }

    @ToolbarContentBuilder
    private var barreOutils: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                VoyantLed(motif: pont.etat.motifLed, depuis: pont.etat.motifLedDepuis, taille: 14)
                Pastille(texte: pont.phase.libelle, couleur: pont.phase.couleur)
            }
            .padding(.horizontal, 8)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                pont.rafraichir()
            } label: {
                Label("Rafraîchir", systemImage: "arrow.clockwise")
            }
            .help("Instantané complet (json etat)")
            .disabled(!pont.peutCommander)

            Button {
                confirmerLiberation = true
            } label: {
                Label("Libérer le port", systemImage: "eject")
            }
            .help("json 0 puis fermeture du port, pour flasher")
            .disabled(pont.phase == .ferme || pont.estDemo)
        }
    }
}

struct Bandeau: View {
    let texte: String
    let couleur: Color
    let icone: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icone)
            Text(verbatim: texte)
                .fixedSize(horizontal: false, vertical: true)
                .frame(idealWidth: 400, maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(couleur)
        .background(couleur.opacity(0.12))
    }
}

/// Choix de la source (port USB ou demo) et etat du transport. Aucun port ne
/// s'ouvre sans un clic.
struct PanneauConnexion: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                Section("Ports série") {
                    if pont.ports.isEmpty { Text("Aucun pont branché en USB") }
                    ForEach(pont.ports) { p in
                        Button {
                            pont.connecter(.serie(chemin: p.chemin, serie: p.serie))
                        } label: {
                            Label {
                                Text(verbatim: pont.titre(port: p))
                                Text(verbatim: p.chemin.replacingOccurrences(of: "/dev/cu.", with: ""))
                            } icon: {
                                Image(systemName: "cpu")
                            }
                        }
                    }
                }
                Section {
                    Button {
                        pont.connecter(.demo)
                    } label: {
                        Label("Mode démo (sans matériel)", systemImage: "play.rectangle")
                    }
                }
            } label: {
                Label(libelleSource, systemImage: pont.estDemo ? "play.rectangle" : "cable.connector")
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)

            Text(verbatim: libelleTransport)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                switch pont.etatTransport {
                case .ferme, .erreur, .libere:
                    Button(pont.source == nil ? "Connecter" : "Reconnecter") {
                        if pont.source == nil {
                            if let s = pont.sourceParDefaut { pont.connecter(s) }
                        } else {
                            pont.reconnecter()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pont.source == nil && pont.sourceParDefaut == nil)
                    .help(pont.source == nil ? "Choisir le pont dans le menu ci-dessus" : "")
                default:
                    Button("Déconnecter") { pont.deconnecter() }
                }
                if pont.phase == .ancienFirmware || pont.phase == .sansReponse {
                    Button("Réessayer json 1") { pont.reessayer() }
                }
            }
            .controlSize(.small)
        }
    }

    private var libelleSource: String {
        switch pont.source {
        case .demo: "Démo"
        case .serie(let chemin, let serie): pont.titre(serie: serie, chemin: chemin)
        case .reseau(let nom): pont.titre(reseau: nom)
        case nil: "Choisir une source…"
        }
    }

    private var libelleTransport: String {
        switch pont.etatTransport {
        case .ferme: "Port fermé"
        case .ouverture: "Ouverture…"
        case .ouvert: "Ouvert · \(pont.phase.libelle)"
        case .attente(let prochain, let raison):
            "\(raison)\nRéouverture \(prochain.formatted(.relative(presentation: .numeric)))"
        case .libere: "Port libéré (json 0) : flasher est possible"
        case .erreur(let e): "Erreur : \(e)"
        }
    }
}
