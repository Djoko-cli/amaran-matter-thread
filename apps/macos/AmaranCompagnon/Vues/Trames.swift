// Ecran « Trames » (spec 3b, section 8) : le trafic Bluetooth Mesh que le pont decode
// (`trame`, 7.6), en tableau filtrable. Repris de TramesEnDirect de Halo Compagnon (commit
// e114cd5) pour le tableau, les filtres et « Figer » ; l'interrupteur du flux est propre a
// amaran : le pont n'emet les trames que sur `json trames 1`, et les coupe seul au bout
// de 60 s a distance (sans le dire : l'app le deduit de l'horloge).
import AmaranProtocole
import SwiftUI

struct Trames: View {
    @Environment(Pont.self) private var pont
    @State private var filtre = FiltreTrames()
    @State private var figees: [TrameRecue]?
    @State private var selection: TrameRecue.ID?

    var body: some View {
        let source = figees ?? pont.trames.elements
        let lignes = filtre.appliquer(source)
        let noms = Dictionary(uniqueKeysWithValues: pont.lampes.map { ($0.numero, $0.nom) })
        VStack(spacing: 0) {
            BarreFlux()
            Divider()
            barreFiltres
            Divider()
            ZStack {
                Table(lignes, selection: $selection) {
                    TableColumn("Heure") { t in
                        Text(verbatim: Format.heure(t.date)).monospacedDigit()
                    }
                    .width(min: 90, ideal: 100, max: 110)
                    TableColumn("Sens") { t in
                        Text(verbatim: "\(t.trame.sens?.fleche ?? "?") \(t.trame.sens?.libelle.lowercased() ?? "")")
                            .foregroundStyle(t.trame.sens == .tx ? Color.teal : Color.blue)
                    }
                    .width(min: 70, ideal: 80, max: 100)
                    TableColumn("Nature") { t in
                        Pastille(texte: t.trame.quoi?.libelle ?? "?", couleur: couleur(t.trame))
                    }
                    .width(min: 100, ideal: 120, max: 150)
                    TableColumn("Lampe") { t in
                        Text(verbatim: FiltreTrames.libelleCible(t.trame, noms: noms))
                            .foregroundStyle(t.trame.lampe == nil ? .secondary : .primary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 160)
                    TableColumn("Marche") { t in
                        Text(verbatim: t.trame.marche.map { $0 ? tr("allumée") : tr("éteinte") } ?? "–")
                    }
                    .width(min: 60, ideal: 70, max: 90)
                    TableColumn("Intensité") { t in
                        Text(verbatim: t.trame.intensite.map(Interpretation.intensite) ?? "–").monospacedDigit()
                    }
                    .width(min: 60, ideal: 70, max: 90)
                    TableColumn("Essai") { t in
                        Text(verbatim: t.trame.essai.map(String.init) ?? "–").monospacedDigit()
                    }
                    .width(min: 40, ideal: 50, max: 60)
                    TableColumn("Sautées") { t in
                        Text(verbatim: t.trame.sautes.map(String.init) ?? "–")
                            .monospacedDigit()
                            .foregroundStyle((t.trame.sautes ?? 0) > 0 ? Color.orange : .secondary)
                            .help("Trames non émises par le pont depuis la précédente (plafond de débit)")
                    }
                    .width(min: 55, ideal: 65, max: 80)
                }
                if source.isEmpty {
                    ContentUnavailableView("Aucune trame", systemImage: "dot.radiowaves.left.and.right",
                                           description: Text("Activer « Trames du pont » : le pont décode alors les messages Bluetooth Mesh de ses lampes (ordres et demandes d'état émis, états reçus)."))
                        .background(.background)
                }
            }
            Divider()
            HStack {
                Text("\(lignes.count) affichées sur \(source.count)")
                if figees != nil { Pastille("affichage figé", couleur: .orange) }
                Spacer()
                Text("Au plus 50 trames par seconde par l'USB, 10 à distance : « Sautées » compte les absentes.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var barreFiltres: some View {
        HStack(spacing: 10) {
            Picker("Sens", selection: $filtre.sens) {
                Text("Tous").tag(SensTrame?.none)
                Text("→ émises").tag(SensTrame?.some(.tx))
                Text("← reçues").tag(SensTrame?.some(.rx))
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Picker("Lampe", selection: $filtre.cible) {
                Text("Toutes les lampes").tag(FiltreTrames.Cible.toutes)
                Text("Groupe").tag(FiltreTrames.Cible.groupe)
                Divider()
                ForEach(pont.lampes) { l in
                    Text(verbatim: "\(l.numero) · \(l.nom)").tag(FiltreTrames.Cible.lampe(l.numero))
                }
            }
            .fixedSize()
            Menu {
                ForEach([QuoiTrame.ordre, .demande, .etat], id: \.self) { q in
                    Toggle(q.libelle, isOn: Binding(
                        get: { filtre.quoi.contains(q) },
                        set: { if $0 { filtre.quoi.insert(q) } else { filtre.quoi.remove(q) } }))
                }
                Divider()
                Button("Toutes") { filtre.quoi = [.ordre, .demande, .etat] }
            } label: {
                Label("Nature (\(filtre.quoi.count))", systemImage: "line.3.horizontal.decrease.circle")
            }
            .fixedSize()
            if !filtre.estNeutre {
                Button("Effacer les filtres") { filtre = FiltreTrames() }
                    .controlSize(.small)
            }
            Spacer()
            Button {
                figees = figees == nil ? pont.trames.elements : nil
            } label: {
                Label(figees == nil ? tr("Figer") : tr("Reprendre"), systemImage: figees == nil ? "pause" : "play")
            }
            .help("Figer l'affichage sans rien demander au pont : les trames continuent d'être gardées")
            Button("Vider") {
                pont.viderTrames()
                figees = nil
                selection = nil
            }
            .disabled(pont.trames.elements.isEmpty && figees == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func couleur(_ t: Trame) -> Color {
        switch t.quoi {
        case .ordre: .teal
        case .demande: .gray
        case .etat: .blue
        case .inconnu, nil: .secondary
        }
    }
}

/// Interrupteur du flux : `json trames 1|0`. A distance, le pont coupe le flux 60 s apres
/// la demande sans le dire ; la barre le deduit de l'horloge et propose de relancer.
private struct BarreFlux: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { contexte in
            let coupe = pont.tramesCoupeesParLePont(a: contexte.date)
            let reste = pont.secondesAvantCoupureDesTrames(a: contexte.date)
            let capable = pont.etat.a(.trames)
            HStack(spacing: 10) {
                Toggle("Trames du pont", isOn: Binding(
                    get: { pont.tramesActives && !coupe },
                    set: { pont.activerTrames($0) }))
                    .toggleStyle(.switch)
                    .disabled(!pont.peutEnvoyer("json trames 1") || !capable)
                    .help("json trames 1 ou 0 : le trafic Bluetooth Mesh en messages « trame »")
                if coupe {
                    Pastille("coupé par le pont après 60 s", couleur: .orange)
                    Button("Relancer") { pont.activerTrames(true) }
                        .controlSize(.small)
                        .disabled(!pont.peutEnvoyer("json trames 1"))
                } else if let reste {
                    Pastille("coupure dans \(reste) s", couleur: .blue)
                    Button("Prolonger") { pont.activerTrames(true) }
                        .controlSize(.small)
                        .help("Renvoie json trames 1 : le pont repart pour 60 s")
                } else if pont.tramesActives {
                    Pastille("flux actif", couleur: .green)
                } else if pont.peutCommander && !capable {
                    Pastille("ce pont n'annonce pas les trames", couleur: .secondary)
                } else {
                    Pastille("flux coupé", couleur: .secondary)
                }
                Spacer()
                if let t = pont.derniereTrame {
                    Text("Dernière trame \(Format.heure(t))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Menu {
                    let actif = pont.tramesActives && !coupe
                    Button(actif ? tr("Couper les trames (json trames 0)") : tr("Reprendre les trames (json trames 1)")) {
                        pont.activerTrames(!actif)
                    }
                    .disabled(!pont.peutEnvoyer("json trames 1") || !pont.etat.a(.trames))
                    Divider()
                    Button("Annonces en messages log (json log 1)") { pont.envoyer("json log 1") }
                        .disabled(!pont.peutEnvoyer("json log 1") || !pont.etat.a(.log) || pont.reglages?.log == true)
                    Button("Annonces en texte (json log 0)") { pont.envoyer("json log 0") }
                        .disabled(!pont.peutEnvoyer("json log 0") || !pont.etat.a(.log) || pont.reglages?.log == false)
                } label: {
                    Label("Flux", systemImage: "antenna.radiowaves.left.and.right")
                }
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
