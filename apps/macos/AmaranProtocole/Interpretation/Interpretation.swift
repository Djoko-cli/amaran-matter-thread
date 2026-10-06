// Textes lisibles des messages du pont amaran, pour la console et les cartes : sur
// le modele d'Interpretation.swift de Halo Compagnon (commit e114cd5).
import Foundation

public enum Interpretation {
    /// `reponse` : « id=5 « mesh lampe 2 masquer » : ok (38 ms) ».
    public static func reponse(_ r: Reponse) -> String {
        var t = "id=\(r.id)"
        if let c = r.cmd, !c.isEmpty { t += " « \(c) »" }
        switch r.etape {
        case .debut:
            return t + " : en cours"
        case .fin, .inconnu:
            t += " : " + code(r.code)
            if let m = r.msg, !m.isEmpty { t += " — " + m }
            if let d = r.dureeMs { t += " (\(d) ms)" }
            return t
        }
    }

    public static func code(_ c: CodeReponse) -> String {
        switch c {
        case .ok: "ok"
        case .accepte: "accepté"
        case .enCours: "en cours"
        case .erreur: "erreur (voir le texte)"
        case .usage: "arguments invalides"
        case .commandeInconnue: "commande inconnue"
        case .tropLong: "ligne trop longue"
        case .cadence: "trop de lignes par seconde"
        case .interdite: "interdite à distance"
        case .dejaTraite: "déjà traitée"
        case .inconnu: "code inconnu"
        }
    }

    /// Ligne « Logiciel » d'une lampe : « 1.4 (BLE 1.69) », « 1.4 » si le module Bluetooth
    /// est inconnu, sinon « inconnu » avec le geste qui peut y remedier : mettre a jour le
    /// firmware d'un pont qui ne prend pas les versions (sans la capacite `logiciel`),
    /// recharger le pont s'il les prend.
    public static func logiciel(_ c: ConfigLampe, pontPrendLesVersions: Bool) -> String {
        ReseauMesh.versionsTexte(logiciel: c.logiciel, ble: c.ble)
            ?? (pontPrendLesVersions ? "inconnu (recharger le pont)" : "inconnu (firmware du pont à mettre à jour)")
    }

    /// `ordre` : « confirmé en 410 ms (essai 1) ».
    public static func ordre(_ o: EvenementOrdre) -> String {
        switch o.issue {
        case .confirme:
            let essai = o.essai.map { " (essai \($0))" } ?? ""
            return "confirmé en \(o.delaiMs ?? 0) ms" + essai
        case .abandon:
            // Essai 0 : l'ordre n'est jamais parti, le Bluetooth Mesh n'etait pas pret.
            if o.essai == 0 { return "abandonné : Bluetooth Mesh pas prêt, rien n'est parti vers la lampe" }
            return "abandonné après \(o.essai ?? 0) essai(s), \(o.delaiMs ?? 0) ms : la lampe ne répond pas"
        case .tenu:
            return "déjà tenu : rien n'est parti vers la lampe"
        case .inconnu, nil:
            return "issue inconnue"
        }
    }

    /// `trame` (7.6) : « → lampe 1 : ordre allumée, 50 % (essai 1) », « → groupe : demande
    /// d'état », « ← lampe 1 : état allumée, 50 % ».
    public static func trame(_ t: Trame) -> String {
        let sens = switch t.sens {
        case .tx: "→"
        case .rx: "←"
        case .inconnu, nil: "?"
        }
        let qui = t.lampe.map { "lampe \($0)" } ?? "groupe"
        var texte = "\(sens) \(qui) : "
        switch t.quoi {
        case .ordre: texte += "ordre"
        case .demande: texte += "demande d'état"
        case .etat: texte += "état"
        case .inconnu, nil: texte += "trame inconnue"
        }
        if t.marche != nil || t.intensite != nil {
            var champs: [String] = []
            if let m = t.marche { champs.append(m ? "allumée" : "éteinte") }
            if let i = t.intensite { champs.append(intensite(i)) }
            texte += " " + champs.joined(separator: ", ")
        }
        if let e = t.essai, t.quoi == .ordre { texte += " (essai \(e))" }
        if let s = t.sautes, s > 0 { texte += " — \(s) trame(s) non émise(s) avant" }
        return texte
    }

    /// Intensite au dixieme de pour cent : « 43 % », « 43,5 % ».
    public static func intensite(_ v: Int) -> String {
        v % 10 == 0 ? "\(v / 10) %" : "\(v / 10),\(v % 10) %"
    }

    /// Etat lu : « allumée, 43 % », « éteinte (43 %) », « noire (0 %) ».
    public static func etat(_ e: EtatLu?) -> String {
        guard let e, let marche = e.marche else { return "jamais lue" }
        let i = e.intensite.map(intensite) ?? "?"
        if e.noire { return "noire : en marche à 0 %" }
        return marche ? "allumée, \(i)" : "éteinte (\(i))"
    }

    /// Place d'une lampe dans Maison (5.3).
    public static func maison(_ m: BlocLampe.Maison?) -> String {
        guard let m else { return "inconnue" }
        if let ep = m.endpoint { return "dans Maison (EP\(ep))" }
        if m.masquee == true { return "retirée de Maison" }
        if m.vue != true { return "jamais vue : entrera dans Maison à sa première réponse" }
        return "hors de Maison (endpoint non créé)"
    }

    /// Cause d'un Bluetooth Mesh inoperant, et le remede (spec du pont 7.3).
    public static func diag(_ d: DiagMesh?) -> String {
        switch d {
        case .ok, nil: "opérationnel"
        case .clesAbsentes: "clés absentes : charger le pont depuis l'onglet Clés"
        case .pasEntre: "pas encore entré dans le réseau des lampes"
        case .clesPerimees: "aucune annonce de notre réseau : réseau recréé dans amaran Desktop ? Recopier les clés, puis recharger le pont"
        case .ivFaux: "NetMIC faux, rien de déchiffré : IV Index faux (mesh iv cherche)"
        case .inconnu: "cause inconnue"
        }
    }
}
