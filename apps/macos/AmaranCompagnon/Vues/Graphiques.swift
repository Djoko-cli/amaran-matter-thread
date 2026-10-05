// Ecran « Graphiques » (spec 3b, section 8) : les courbes du pont, calculees par
// differences de compteurs successifs (AmaranProtocole.Courbes) ou lues telles quelles
// (SeriesCourbes). Repris des Graphiques de Halo Compagnon (commit e114cd5) : fenetre
// de 10 s ou 1 min, duree affichee, segments (un redemarrage du pont ouvre un nouveau
// segment, jamais une ligne entre deux demarrages), bouton vider.
import AmaranProtocole
import Charts
import SwiftUI

/// Etiquettes de valeurs tracees : des symboles, sans traduction.
private enum Symbole {
    static let serie = "s"
    static let pourcent = "%"
    static let ms = "ms"
}

struct Graphiques: View {
    @Environment(Pont.self) private var pont
    @State private var fenetre: Double = 10
    @State private var duree: Double = 15 * 60

    /// Point trace : une valeur datee d'une serie, dans un segment de `boot`.
    private struct Point: Identifiable {
        let id: String
        let debut: Date
        let fin: Date
        let serie: String
        let segment: Int
        let valeur: Double
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { contexte in
            // L'axe finit au plus recent de l'horloge et du dernier point (lignes datees par
            // `ms`, l'ancre du hello, pas par leur arrivee).
            let c = pont.courbes
            let fin = [contexte.date, c.pont.last?.date, c.mesh.last?.date, c.tas.last?.date]
                .compactMap { $0 }.max() ?? contexte.date
            let debut = duree > 0 ? fin.addingTimeInterval(-duree) : .distantPast
            contenu(debut: debut, fin: fin)
        }
    }

    @ViewBuilder
    private func contenu(debut: Date, fin: Date) -> some View {
        let c = pont.courbes
        // Un trou dans les echantillons (app suspendue, lien perdu) ouvre un segment.
        let ecartMesh = Courbes.ecartMax(periodeMs: pont.reglages?.compteursMs)
        let ecartPont = Courbes.ecartMax(periodeMs: pont.reglages?.periodeMs)
        let dMesh = Courbes.differences(c.mesh, fenetre: fenetre, ecartMax: ecartMesh).filter { $0.fin >= debut }
        let dPont = Courbes.differences(c.pont, fenetre: fenetre, ecartMax: ecartPont).filter { $0.fin >= debut }
        let redemarrages = c.redemarrages.filter { $0 >= debut }
        let lampes = c.lampes
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                reglages
                if c.tas.isEmpty && c.pont.isEmpty && c.mesh.isEmpty && lampes.isEmpty {
                    ContentUnavailableView("Pas encore de courbes", systemImage: "chart.xyaxis.line",
                                           description: Text("Les courbes se tracent au fil des blocs que le pont envoie : connecter le pont, ou lancer la démo."))
                }
                // La meme phrase que la carte « Bluetooth Mesh » du tableau de bord.
                if let texte = pont.texteCompteursMesh {
                    avisCompteurs(texte, demander: pont.etatCompteursMesh == .nonReleves)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 460), spacing: 16, alignment: .top)], spacing: 16) {
                    Carte(titre: "Relectures répondues", icone: "arrow.triangle.2.circlepath") {
                        graphePart(lampes: lampes, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Part des relectures de chaque lampe qui ont reçu une réponse sur 10 min (jauge du pont, nulle tant qu'aucune relecture n'a eu lieu).")
                    }
                    Carte(titre: "Délais des ordres", icone: "timer") {
                        grapheDelais(lampes: lampes, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Délai de chaque ordre confirmé ; croix rouge : ordre abandonné (la lampe n'a pas répondu ; à 0 ms : Bluetooth Mesh pas prêt). Pointillé : au-delà d'une seconde, l'ordre est dit lent.")
                    }
                    Carte(titre: "Ordres du pont", icone: "list.number") {
                        grapheOrdres(dPont, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Ordres confirmés et abandonnés par fenêtre de \(Int(fenetre)) s (différences du bloc pont).")
                    }
                    Carte(titre: "Annonces Bluetooth Mesh", icone: "point.3.filled.connected.trianglepath.dotted") {
                        grapheAnnonces(dMesh, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Annonces reçues par fenêtre de \(Int(fenetre)) s, dont celles de notre réseau (nid reconnu).")
                    }
                    Carte(titre: "NetMIC faux", icone: "exclamationmark.shield") {
                        grapheLigne(dMesh.compactMap { d in Courbes.partNetmicFaux(d).map { (d, $0 * 100) } },
                                    serie: "NetMIC faux", unite: Symbole.pourcent, couleur: .orange,
                                    debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Part des annonces de notre réseau dont le NetMIC est faux : un IV Index faux la fait monter vers 100 %. Des clés périmées font tomber à zéro les annonces de notre réseau.")
                    }
                    Carte(titre: "Refus d'émission", icone: "paperplane.circle") {
                        grapheRefus(dMesh, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Émissions refusées par la pile Bluetooth, par fenêtre ; courbe : part des émissions refusées.")
                    }
                    Carte(titre: "Tas libre", icone: "memorychip") {
                        grapheTas(c, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Mémoire libre du pont (trait plein) et son plus bas depuis le démarrage (pointillé).")
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Reglages de l'ecran

    private var reglages: some View {
        HStack(spacing: 16) {
            Picker("Fenêtre", selection: $fenetre) {
                Text(verbatim: "10 s").tag(10.0)
                Text(verbatim: "1 min").tag(60.0)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Picker("Durée", selection: $duree) {
                Text(verbatim: "5 min").tag(300.0)
                Text(verbatim: "15 min").tag(900.0)
                Text(verbatim: "1 h").tag(3600.0)
                Text("Tout").tag(0.0)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
            Text("Un redémarrage du pont, une différence négative ou un trou ouvre un nouveau segment.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Vider les courbes") { pont.viderCourbes() }
                .help("Efface les courbes de l'app seulement : le pont ne change pas")
        }
    }

    /// A distance, le profil du pont coupe les compteurs Mesh : sans eux, trois courbes
    /// ne recoivent plus de point. Les redemander coute des datagrammes, donc seulement
    /// sur demande. `texte` : la phrase de la carte « Bluetooth Mesh » (CompteursMesh).
    private func avisCompteurs(_ texte: String, demander: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
            Text(verbatim: texte + (demander
                ? " : par le réseau, le pont ne les envoie que sur demande ; les courbes d'annonces, de NetMIC faux et de refus ne reçoivent plus de point."
                : "."))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if demander {
                Button("Demander les compteurs") { pont.activerCompteursMesh() }
                    .disabled(!pont.peutCommander)
                    .help("json compteurs \(CompteursMesh.periodeProposeeMs)")
            }
        }
        .font(.callout)
        .padding(10)
        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.blue)
    }

    private func legende(_ texte: String) -> some View {
        Text(verbatim: texte).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Donnees

    private func nom(_ lampe: Int) -> String {
        let n = pont.lampes.first { $0.numero == lampe }?.nom ?? "Lampe \(lampe)"
        return "\(lampe) · \(n)"
    }

    /// Axe du temps : la periode choisie, ramenee au premier point s'il est plus recent.
    private func echelle(_ debut: Date, _ fin: Date) -> ClosedRange<Date> {
        let c = pont.courbes
        let premiers = [c.pont.first?.date, c.mesh.first?.date, c.tas.first?.date,
                        c.parts.values.compactMap { $0.first?.date }.min(),
                        c.ordres.values.compactMap { $0.first?.date }.min()].compactMap { $0 }
        let premier = premiers.min() ?? fin.addingTimeInterval(-60)
        return min(max(debut, premier), fin.addingTimeInterval(-30))...fin
    }

    // MARK: - Graphes

    @ChartContentBuilder
    private func reperes(_ dates: [Date]) -> some ChartContent {
        ForEach(dates, id: \.self) { d in
            RuleMark(x: .value("Redémarrage", d))
                .foregroundStyle(.purple.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
    }

    private func graphePart(lampes: [Int], debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let c = pont.courbes
        let noms = lampes.map(nom)
        return Chart {
            ForEach(lampes, id: \.self) { l in
                ForEach(Array((c.parts[l] ?? []).enumerated()), id: \.offset) { _, p in
                    if p.date >= debut, let v = p.valeur {
                        LineMark(x: .value("Heure", p.date), y: .value(Symbole.pourcent, v),
                                 series: .value(Symbole.serie, "\(l)-\(p.segment)"))
                            .foregroundStyle(by: .value("Lampe", nom(l)))
                    }
                }
            }
            reperes(redemarrages)
        }
        .chartForegroundStyleScale(domain: noms, range: Self.palette(noms.count))
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYScale(domain: 0...100)
        .chartYAxisLabel(Symbole.pourcent)
        .frame(height: 170)
    }

    private func grapheDelais(lampes: [Int], debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let c = pont.courbes
        let noms = lampes.map(nom)
        let maxi = lampes.flatMap { c.ordres[$0] ?? [] }.filter { $0.date >= debut }.compactMap(\.delaiMs).max() ?? 0
        return Chart {
            ForEach(lampes, id: \.self) { l in
                ForEach(Array((c.ordres[l] ?? []).enumerated()), id: \.offset) { _, o in
                    if o.date >= debut, let d = o.delaiMs {
                        if o.issue == .confirme {
                            PointMark(x: .value("Heure", o.date), y: .value(Symbole.ms, d))
                                .foregroundStyle(by: .value("Lampe", nom(l)))
                                .symbolSize(28)
                        } else if o.issue == .abandon {
                            PointMark(x: .value("Heure", o.date), y: .value(Symbole.ms, d))
                                .symbol(.cross)
                                .symbolSize(70)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            if maxi > 250 {
                RuleMark(y: .value("Lent", 1000))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
            reperes(redemarrages)
        }
        .chartForegroundStyleScale(domain: noms, range: Self.palette(noms.count))
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYAxisLabel(Symbole.ms)
        .frame(height: 170)
    }

    private func grapheOrdres(_ d: [Difference], debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let confirmes = points(d, "confirmés") { $0[.confirmes].map(Double.init) }
        let abandons = points(d, "abandonnés") { $0[.abandons].map(Double.init) }
        return Chart {
            ForEach((confirmes + abandons).filter { $0.valeur > 0 }) { x in
                BarMark(xStart: .value("Début", x.debut), xEnd: .value("Fin", x.fin), y: .value("par fenêtre", x.valeur))
                    .foregroundStyle(by: .value("Issue", x.serie))
            }
            reperes(redemarrages)
        }
        .chartForegroundStyleScale(["confirmés": Color.green, "abandonnés": Color.red])
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYAxisLabel("par fenêtre")
        .frame(height: 130)
    }

    private func grapheAnnonces(_ d: [Difference], debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let toutes = points(d, "annonces") { $0[.annonces].map(Double.init) }
        let notres = points(d, "de notre réseau") { $0[.nidReconnu].map(Double.init) }
        return Chart {
            ForEach(toutes + notres) { p in
                LineMark(x: .value("Heure", p.fin), y: .value("par fenêtre", p.valeur),
                         series: .value(Symbole.serie, "\(p.serie)-\(p.segment)"))
                    .foregroundStyle(by: .value("Annonces", p.serie))
            }
            reperes(redemarrages)
        }
        .chartForegroundStyleScale(["annonces": Color.gray, "de notre réseau": Color.blue])
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYAxisLabel("par fenêtre")
        .frame(height: 130)
    }

    private func grapheLigne(_ valeurs: [(Difference, Double)], serie: String, unite: String, couleur: Color,
                             debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        Chart {
            ForEach(Array(valeurs.enumerated()), id: \.offset) { _, v in
                LineMark(x: .value("Heure", v.0.fin), y: .value(unite, v.1),
                         series: .value(Symbole.serie, "\(serie)-\(v.0.segment)"))
                    .foregroundStyle(couleur)
            }
            reperes(redemarrages)
        }
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYScale(domain: 0...100)
        .chartYAxisLabel(unite)
        .frame(height: 110)
    }

    private func grapheRefus(_ d: [Difference], debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let echecs = points(d, "refus") { $0[.echecsEmission].map(Double.init) }
        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(echecs.filter { $0.valeur > 0 }) { x in
                    BarMark(xStart: .value("Début", x.debut), xEnd: .value("Fin", x.fin), y: .value("par fenêtre", x.valeur))
                        .foregroundStyle(.red)
                }
                reperes(redemarrages)
            }
            .chartXScale(domain: echelle(debut, fin))
            .chartPlotStyle { $0.clipped() }
            .chartYAxisLabel("par fenêtre")
            .frame(height: 90)
            grapheLigne(d.compactMap { x in Courbes.partRefusEmission(x).map { (x, $0 * 100) } },
                        serie: "part des refus", unite: Symbole.pourcent, couleur: .red,
                        debut: debut, fin: fin, redemarrages: redemarrages)
        }
    }

    private func grapheTas(_ c: SeriesCourbes, debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let libre = c.tas.filter { $0.date >= debut }
        let plusBas = c.tasMin.filter { $0.date >= debut }
        return Chart {
            ForEach(Array(libre.enumerated()), id: \.offset) { _, p in
                if let v = p.valeur {
                    LineMark(x: .value("Heure", p.date), y: .value("Ko", v / 1024),
                             series: .value(Symbole.serie, "tas-\(p.segment)"))
                        .foregroundStyle(.blue)
                }
            }
            ForEach(Array(plusBas.enumerated()), id: \.offset) { _, p in
                if let v = p.valeur {
                    LineMark(x: .value("Heure", p.date), y: .value("Ko", v / 1024),
                             series: .value(Symbole.serie, "min-\(p.segment)"))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            reperes(redemarrages)
        }
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYAxisLabel("Ko")
        .frame(height: 140)
    }

    private func points(_ d: [Difference], _ serie: String, _ f: (Difference) -> Double?) -> [Point] {
        d.enumerated().compactMap { i, x in
            f(x).map { Point(id: "\(serie)-\(i)", debut: x.debut, fin: x.fin, serie: serie, segment: x.segment, valeur: $0) }
        }
    }

    /// Couleurs distinctes pour n lampes (16 au plus) : la teinte fait le tour du cercle.
    private static func palette(_ n: Int) -> [Color] {
        (0..<n).map { Color(hue: Double($0) / Double(max(n, 1)), saturation: 0.65, brightness: 0.85) }
    }
}
