// Ecran « Commandes et console » (spec 3b, section 8) : une lampe choisie a gauche, la
// console brute de Halo Compagnon (commit e114cd5) a droite.
import AmaranProtocole
import SwiftUI

struct CommandesEtConsole: View {
    var body: some View {
        HSplitView {
            PanneauCommandes()
                .frame(minWidth: 380, idealWidth: 440, maxWidth: 540)
            ConsoleBrute()
                .frame(minWidth: 420)
        }
    }
}

// MARK: - Commandes

private struct PanneauCommandes: View {
    @Environment(Pont.self) private var pont
    @State private var choisie = 1
    @State private var niveau: Double = 50
    @State private var glisse = false
    @State private var confirmerRetrait = false
    @State private var releve = 2

    var body: some View {
        let lampes = pont.lampes
        let lampe = lampes.first { $0.numero == choisie }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Lampe", selection: $choisie) {
                    ForEach(lampes) { l in Text(verbatim: "\(l.numero) · \(l.nom)").tag(l.numero) }
                }
                if let lampe {
                    Carte(titre: lampe.nom, icone: "lightbulb") {
                        LigneInfo("État lu", Interpretation.etat(lampe.etat?.lue))
                        LigneInfo("Maison", Interpretation.maison(lampe.etat?.maison))
                        HStack {
                            Button("Allumer") { pont.allumer(lampe: lampe.numero, true) }
                            Button("Éteindre") { pont.allumer(lampe: lampe.numero, false) }
                            Button("Relire") { pont.relire(lampe: lampe.numero) }
                        }
                        HStack {
                            Text("Niveau").foregroundStyle(.secondary)
                            Slider(value: $niveau, in: 0...100, step: 1) { en in
                                glisse = en
                                pont.niveau(lampe: lampe.numero, pourCent: Int(niveau), fini: !en)
                            }
                            .onChange(of: niveau) { _, v in
                                if glisse { pont.niveau(lampe: lampe.numero, pourCent: Int(v), fini: false) }
                            }
                            Text(verbatim: "\(Int(niveau)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                        if lampe.dansMaison {
                            Button("Retirer de Maison…") { confirmerRetrait = true }
                        } else {
                            Button("Remettre dans Maison") { pont.exposer(lampe: lampe.numero, dansMaison: true) }
                        }
                    }
                    .confirmationDialog("Retirer « \(lampe.nom) » de Maison ?", isPresented: $confirmerRetrait) {
                        Button("Retirer de Maison", role: .destructive) { pont.exposer(lampe: lampe.numero, dansMaison: false) }
                    } message: {
                        Text(verbatim: Pont.avertissementRetrait)
                    }
                }
                Carte(titre: "Relecture des lampes", icone: "arrow.triangle.2.circlepath") {
                    Stepper(value: $releve, in: 1...60) {
                        Text(verbatim: "Toutes les \(releve) s")
                    }
                    Button("Appliquer") { pont.reglerReleve(secondes: releve) }
                        .disabled(pont.etat.mesh?.valeur.releveMs == releve * 1000)
                }
                Carte(titre: "Commandes récentes", icone: "list.bullet.rectangle") {
                    let recents = pont.suivis.filter { $0.origine != .session }.suffix(12).reversed()
                    if recents.isEmpty {
                        Text("Aucune commande envoyée.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(recents)) { s in LigneSuivi(suivi: s) }
                }
            }
            .padding(14)
            .disabled(!pont.peutCommander)
        }
        .onAppear { recopier() }
        .onChange(of: pont.etat.lampes[choisie]?.valeur.lue) { _, _ in recopier() }
        .onChange(of: choisie) { _, _ in recopier() }
    }

    /// Le curseur suit l'etat lu, sauf pendant le glissement et tant que sa valeur
    /// finale n'est pas partie.
    private func recopier() {
        if let m = pont.etat.mesh?.valeur.releveMs { releve = m / 1000 }
        guard !glisse, !pont.suivis.contains(where: { $0.fusion == "niveau\(choisie)" && !$0.etat.estFinal }),
              let i = pont.etat.lampes[choisie]?.valeur.lue?.intensite else { return }
        niveau = Double(i / 10)
    }
}

private struct LigneSuivi: View {
    let suivi: SuiviCommande

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: suivi.numero.map { "id=\($0)" } ?? "–").font(.caption.monospaced()).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(verbatim: suivi.commande).font(.callout.monospaced()).lineLimit(1)
            Spacer()
            Pastille(texte: libelle, couleur: couleur)
        }
        .help(aide)
    }

    private var libelle: String {
        if suivi.etat == .terminee, let f = suivi.fin, !f.ok { return Interpretation.code(f.code) }
        return suivi.etat.libelle
    }

    private var couleur: Color {
        switch suivi.etat {
        case .confirmee, .tenue: .green
        case .terminee: suivi.fin?.ok == false ? .red : .green
        case .abandonnee, .sansReponse, .perdue, .ordrePerdu: .red
        case .attenteOrdre, .envoyee, .enCours: .orange
        case .remplacee, .finPerdue: .secondary
        case .enFile: .blue
        }
    }

    private var aide: String {
        var s = suivi.commande
        if let f = suivi.fin { s += "\n" + Interpretation.reponse(f) }
        if let o = suivi.ordre { s += "\n" + Interpretation.ordre(o) }
        return s
    }
}

extension EtatCommande {
    var libelle: String {
        switch self {
        case .enFile: "en file"
        case .envoyee: "envoyée"
        case .enCours: "en cours"
        case .terminee: "ok"
        case .attenteOrdre: "ordre en cours"
        case .confirmee: "confirmée"
        case .abandonnee: "abandonnée"
        case .tenue: "déjà tenue"
        case .ordrePerdu: "issue perdue"
        case .sansReponse: "sans réponse"
        case .finPerdue: "fin perdue"
        case .remplacee: "remplacée"
        case .perdue: "perdue"
        }
    }
}

// MARK: - Console

private struct ConsoleBrute: View {
    @Environment(Pont.self) private var pont
    @State private var saisie = ""
    @State private var erreur: String?
    @State private var aConfirmer: (ligne: String, raison: String)?
    @State private var historique: [String] = []
    @State private var positionHistorique: Int?
    @State private var logsSysteme = true
    @State private var session = false
    @State private var defilement = true
    @FocusState private var focus: Bool

    var body: some View {
        let lignes = pont.console.elements.filter(visible).suffix(2000)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Console").font(.headline)
                Spacer()
                Toggle("Journaux d'ESP-IDF", isOn: $logsSysteme)
                Toggle("Session (ping, json 1)", isOn: $session)
                Toggle("Défilement", isOn: $defilement)
                Button("Vider") { pont.viderConsole() }
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(lignes) { l in
                            LigneConsoleVue(ligne: l).id(l.id)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: pont.console.elements.last?.id) { _, id in
                    if defilement, let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            saisieVue
        }
        .alert("Confirmer la commande", isPresented: Binding(get: { aConfirmer != nil }, set: { if !$0 { aConfirmer = nil } }),
               presenting: aConfirmer) { c in
            Button("Envoyer « \(PolitiqueCommandes.masquerCle(c.ligne)) »", role: .destructive) {
                traiter(pont.console(c.ligne, confirme: true), ligne: c.ligne)
            }
            Button("Annuler", role: .cancel) {}
        } message: { c in
            Text(verbatim: c.raison)
        }
    }

    private var saisieVue: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: pont.consoleAvecId ? "id=…" : "brut").font(.caption.monospaced()).foregroundStyle(.secondary)
                TextField("commande de la console (ex. mesh, lampes, help)", text: $saisie)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($focus)
                    .onSubmit(soumettre)
                    .onKeyPress(.upArrow) { naviguer(-1) }
                    .onKeyPress(.downArrow) { naviguer(1) }
                Button("Envoyer", action: soumettre)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saisie.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                if let erreur {
                    Text(verbatim: erreur).foregroundStyle(.red)
                } else if !pont.consoleAvecId, pont.phase != .ferme {
                    Text(verbatim: "Console seule (\(pont.phase.libelle)) : lignes envoyées sans id, sans corrélation.")
                        .foregroundStyle(.orange)
                } else {
                    Text("Chaque ligne part avec un id : le texte reçu entre réponse début et fin lui est rattaché.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Prefixe "id=<n> " : 13 octets au plus (n <= 999999999).
                let octets = saisie.utf8.count + (pont.consoleAvecId ? 13 : 0)
                Text(verbatim: "\(octets) / \(LigneCommande.octetsMax) octets")
                    .foregroundStyle(octets > LigneCommande.octetsMax ? .red : .secondary)
                    .monospacedDigit()
            }
            .font(.caption)
        }
        .padding(10)
    }

    private func visible(_ l: LigneConsole) -> Bool {
        switch l.genre {
        case .texte(let c): return logsSysteme || !c.estLogSysteme
        case .fragment: return logsSysteme
        case .envoi(let o): return session || o != .session
        case .retour(_, let s): return session || !s
        default: return true
        }
    }

    private func soumettre() {
        let ligne = saisie.trimmingCharacters(in: .whitespaces)
        guard !ligne.isEmpty else { return }
        traiter(pont.console(ligne), ligne: ligne)
    }

    private func traiter(_ r: Pont.ResultatConsole, ligne: String) {
        switch r {
        case .envoyee:
            erreur = nil
            // Jamais de cle dans l'historique de saisie.
            if PolitiqueCommandes.masquerCle(ligne) == ligne, historique.last != ligne { historique.append(ligne) }
            positionHistorique = nil
            saisie = ""
        case .confirmation(let raison):
            aConfirmer = (ligne, raison)
        case .refusee(let raison):
            erreur = raison
        }
    }

    private func naviguer(_ sens: Int) -> KeyPress.Result {
        guard !historique.isEmpty else { return .ignored }
        let p = (positionHistorique ?? historique.count) + sens
        if p >= historique.count {
            positionHistorique = nil
            saisie = ""
        } else {
            positionHistorique = max(0, p)
            saisie = historique[max(0, p)]
        }
        return .handled
    }
}

private struct LigneConsoleVue: View {
    let ligne: LigneConsole

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: Format.heure(ligne.date))
                .foregroundStyle(.tertiary)
            Text(verbatim: ligne.texte)
                .foregroundStyle(couleur)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .padding(.leading, ligne.numero != nil && estTexte ? 14 : 0)
    }

    private var estTexte: Bool {
        if case .texte = ligne.genre { return true }
        return false
    }

    private var couleur: Color {
        switch ligne.genre {
        case .envoi(let o): o == .session ? .secondary : .accentColor
        case .texte(let c):
            switch c {
            case .logIDF: .secondary
            case .annonce: .purple
            case .demarrage: .orange
            default: .primary
            }
        case .fragment: .gray
        case .retour(let ok, let s): s ? .secondary : (ok ? .green : .red)
        case .log: .purple
        case .note(let grave): grave ? .red : .teal
        }
    }
}
