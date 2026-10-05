// Tableau de bord (spec 3b, section 8) : une grille de cartes, une par lampe. La carte
// « Ajouter a Maison » et le QR code sont repris de Halo Compagnon (commit e114cd5).
import AmaranProtocole
import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct TableauDeBord: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        if pont.etat.helloBase == nil && pont.etat.lampes.isEmpty {
            // Les cles se copient, s'exportent et s'importent sans pont : leur carte reste la.
            ScrollView {
                VStack(spacing: 16) {
                    ContentUnavailableView {
                        Label("Aucun état reçu", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("Choisir le port du pont (VID 303A) ou le mode démo dans la barre latérale.")
                    } actions: {
                        Button("Lancer la démo") { pont.connecter(.demo) }
                    }
                    .frame(minHeight: 220)
                    CarteCles()
                        .frame(maxWidth: 560)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14, alignment: .top)],
                          alignment: .leading, spacing: 14) {
                    // Pont pas encore mis en service : l'appairage passe avant tout.
                    if pont.etat.enService == false { CarteAppairage() }
                    ForEach(pont.lampes) { CarteLampe(lampe: $0) }
                    CarteMesh()
                    CarteMatter()
                    CarteCles()
                    CarteVoyant()
                    CarteSysteme()
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Lampes

private struct CarteLampe: View {
    @Environment(Pont.self) private var pont
    let lampe: VueLampe

    var body: some View {
        let e = lampe.etat
        let joignable = e?.joignable ?? false
        Carte(titre: "\(lampe.numero) · \(lampe.nom)", icone: "lightbulb",
              accent: e?.alerte == true || (e?.entendue == true && !joignable) ? .orange : .secondary) {
            LigneInfo("Modèle", lampe.config.map { c in
                (c.catalogue == true ? c.modele : "non catalogué (code \(c.code ?? 0))") ?? "?"
            })
            LigneInfo("Maison", Interpretation.maison(e?.maison))
            LigneInfo("État lu", Interpretation.etat(e?.lue))
            LigneInfo("Joignable", e?.entendue == true ? Format.oui(joignable) : "jamais entendue",
                      couleur: e?.entendue == true && !joignable ? .orange : nil)
            LigneInfo("Relectures sur 10 min", e?.part10Min.map { "\($0) %" } ?? "–",
                      couleur: e?.alerte == true ? .orange : nil)
            if let c = e?.consigne {
                let quoi = [c.marche.map { $0 ? "marche" : "arrêt" }, c.intensite.map(Interpretation.intensite)]
                    .compactMap { $0 }.joined(separator: ", ")
                LigneInfo("Consigne en cours", "\(quoi) (essai \(c.essai ?? 1))", couleur: .blue)
            }
            if let o = lampe.dernierOrdre {
                LigneInfo("Dernier ordre", Interpretation.ordre(o), couleur: o.issue == .abandon ? .orange : nil)
            }
        }
    }
}

// MARK: - Bluetooth Mesh

private struct CarteMesh: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        let p = pont.etat.pont?.valeur
        let m = pont.etat.mesh?.valeur
        let c = pont.etat.compteurs?.valeur
        let pret = p?.mesh?.pret == true
        Carte(titre: "Bluetooth Mesh", icone: "point.3.filled.connected.trianglepath.dotted",
              accent: p?.mesh?.diag.map { $0 != .ok } == true ? .red : .secondary) {
            LigneInfo("Réseau des lampes", pret ? "prêt" : "pas prêt", couleur: pret ? .green : .orange)
            if let d = p?.mesh?.diag, d != .ok { LigneInfo("Diagnostic", Interpretation.diag(d), couleur: .red) }
            LigneInfo("Adresse du pont", m?.adresse.map { "0x\($0)" }, mono: true)
            LigneInfo("IV Index", c?.iv.map(String.init))
            LigneInfo("Relecture", m?.releveMs.map { "toutes les \($0 / 1000) s" })
            LigneInfo("Ordres", p?.ordres.map { o in
                "\(o.total ?? 0) : \(o.confirmes ?? 0) confirmé(s), \(o.abandons ?? 0) abandonné(s), \(o.tenus ?? 0) déjà tenu(s)"
            })
            LigneInfo("Délai moyen", p?.ordres?.delaiMoyenMs.map { "\($0) ms (max \(p?.ordres?.delaiMaxMs ?? 0) ms)" })
            LigneInfo("Annonces", c.map { "\($0.annonces ?? 0) (\($0.nidReconnu ?? 0) de notre réseau)" })
            LigneInfo("NetMIC faux", c?.netmicFaux.map(String.init), couleur: (c?.netmicFaux ?? 0) > 0 ? .orange : nil)
            LigneInfo("Émis, refus", c.map { "\($0.emis ?? 0), \($0.echecsEmission ?? 0)" })
        }
    }
}

// MARK: - Thread et Matter

private struct CarteMatter: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        let m = pont.etat.matter?.valeur
        let t = pont.etat.thread?.valeur
        Carte(titre: "Thread et Matter", icone: "homekit") {
            LigneInfo("Mise en service", m?.fabriques.map { $0 > 0 ? "faite (\($0) fabrique(s))" : "en attente" })
            LigneInfo("Thread", t.map { "\($0.role ?? "?")\($0.attache == true ? " (attaché)" : "")" })
            LigneInfo("Abonnements actifs", m?.abonnements?.actifs.map(String.init))
            LigneInfo("Annonce BLE", Format.oui(m?.ble))
            LigneInfo("Identification", Format.oui(m?.identifie))
        }
    }
}

// MARK: - Voyant

private struct CarteVoyant: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        Carte(titre: "Voyant", icone: "light.beacon.max") {
            HStack(spacing: 14) {
                VoyantLed(motif: pont.etat.motifLed, depuis: pont.etat.motifLedDepuis, taille: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: pont.etat.motifLed?.libelle ?? "inconnu")
                    if pont.etat.ledTest { Pastille(texte: "test en cours", couleur: .blue) }
                }
                Spacer()
                Button(pont.etat.ledTest ? "Arrêter" : "Tester") { pont.testerVoyant(!pont.etat.ledTest) }
                    .disabled(!pont.peutCommander)
            }
        }
    }
}

// MARK: - Systeme

private struct CarteSysteme: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        let h = pont.etat.helloBase?.valeur
        let s = pont.etat.sante?.valeur.sys
        Carte(titre: "Système", icone: "cpu") {
            LigneInfo("Firmware", h?.fw, mono: true)
            LigneInfo("ESP-IDF", h?.idf)
            LigneInfo("Démarrage", h?.reset)
            LigneInfo("En marche depuis", Format.duree(secondes: pont.etat.upS))
            LigneInfo("Tas libre", s.map { "\(Format.octets($0.heap)) (au plus bas \(Format.octets($0.heapMin)))" })
            if let piles = s?.piles {
                LigneInfo("Piles (au plus bas)", piles.sorted { $0.key < $1.key }
                    .map { "\($0.key) \($0.value.map(String.init) ?? "–")" }.joined(separator: ", "))
            }
            LigneInfo("Lignes perdues", "\(s?.jsonPerdus ?? 0) au pont, \(pont.statistiques.pertes) sur le fil",
                      couleur: (s?.jsonPerdus ?? 0) + pont.statistiques.pertes > 0 ? .orange : nil)
            LigneInfo("Lignes abîmées", String(pont.reception.lignesAbimees))
        }
    }
}

// MARK: - Appairage

private struct CarteAppairage: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        let m = pont.etat.matter?.valeur
        Carte(titre: "Ajouter à Maison", icone: "qrcode.viewfinder", accent: .blue) {
            if let code = m?.codeManuel {
                HStack(alignment: .top, spacing: 16) {
                    if let qr = m?.qr { ImageCodeQR(charge: qr, cote: 168) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Le pont attend d'être ajouté à Maison.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Dans Maison : + › Ajouter un accessoire, puis scanner ce code. Sans appareil photo : « Plus d'options » et le code à 11 chiffres.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        CodeManuel(code: code)
                        Text("L'iPhone près du pont : la mise en service passe par le Bluetooth.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.callout)
            } else {
                Text("Le pont n'est pas encore mis en service ; ses codes d'appairage arrivent avec le bloc réseau.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.callout)
            }
        }
    }
}

/// Code manuel groupe comme dans Maison, selectionnable, et un bouton pour le copier.
private struct CodeManuel: View {
    let code: String

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: CodeAppairage.lisible(code))
                .font(.title2.monospaced().weight(.semibold))
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            } label: {
                Label("Copier", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .help("Copie les chiffres du code manuel")
        }
    }
}

/// QR code Matter en noir sur blanc, avec sa marge de silence (lisible en mode sombre
/// aussi) ; rien si la charge n'est pas un `MT:...`.
private struct ImageCodeQR: View {
    let charge: String
    let cote: CGFloat

    var body: some View {
        if CodeAppairage.chargeValide(charge), let image = CodeQR.image(charge) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: cote, height: cote)
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.1)))
                .accessibilityLabel(Text("QR code Matter"))
                .help(Text(verbatim: charge))
        }
    }
}

enum CodeQR {
    static func image(_ texte: String) -> NSImage? {
        let filtre = CIFilter.qrCodeGenerator()
        filtre.message = Data(texte.utf8)
        filtre.correctionLevel = "M"
        guard let sortie = filtre.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: sortie)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
