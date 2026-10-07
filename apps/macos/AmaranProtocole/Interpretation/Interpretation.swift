// Textes lisibles des messages du pont amaran, pour la console et les cartes : sur
// le modele d'Interpretation.swift de Halo Compagnon (commit e114cd5).
import Foundation

public enum Interpretation {
    /// Nombre a une decimale dans les formats de la langue en vigueur ("43,5", "43.5").
    static func decimal(_ v: Double, chiffres: Int) -> String {
        v.formatted(.number.precision(.fractionLength(chiffres)).locale(Localisation.partagee.locale))
    }

    /// `reponse` : « id=5 « mesh lampe 2 masquer » : ok (38 ms) ». La commande et le `msg`
    /// sont ceux du pont, tels quels (jamais traduits).
    public static func reponse(_ r: Reponse) -> String {
        var t = "id=\(r.id)"
        if let c = r.cmd, !c.isEmpty { t += tr(" « \(c) »") }
        switch r.etape {
        case .debut:
            return tr("\(t) : en cours")
        case .fin, .inconnu:
            var s = tr("\(t) : \(code(r.code))")
            if let m = r.msg, !m.isEmpty { s += " — " + m }
            if let d = r.dureeMs { s += " (\(d) ms)" }
            return s
        }
    }

    public static func code(_ c: CodeReponse) -> String {
        switch c {
        case .ok: tr("ok")
        case .accepte: tr("accepté")
        case .enCours: tr("en cours")
        case .erreur: tr("erreur (voir le texte)")
        case .usage: tr("arguments invalides")
        case .commandeInconnue: tr("commande inconnue")
        case .tropLong: tr("ligne trop longue")
        case .cadence: tr("trop de lignes par seconde")
        case .interdite: tr("interdite à distance")
        case .dejaTraite: tr("déjà traitée")
        case .inconnu: tr("code inconnu")
        }
    }

    /// Ligne « Logiciel » d'une lampe : « 1.4 (BLE 1.69) », « 1.4 » si le module Bluetooth
    /// est inconnu, sinon « inconnu » avec le geste qui peut y remedier : mettre a jour le
    /// firmware d'un pont qui ne prend pas les versions (sans la capacite `logiciel`),
    /// recharger le pont s'il les prend.
    public static func logiciel(_ c: ConfigLampe, pontPrendLesVersions: Bool) -> String {
        ReseauMesh.versionsTexte(logiciel: c.logiciel, ble: c.ble)
            ?? (pontPrendLesVersions ? tr("inconnu (recharger le pont)") : tr("inconnu (firmware du pont à mettre à jour)"))
    }

    /// `ordre` : « confirmé en 410 ms (essai 1) ».
    public static func ordre(_ o: EvenementOrdre) -> String {
        switch o.issue {
        case .confirme:
            // Durees en ms sans separateur de milliers (comme les ecrans), quelle que soit la langue.
            let ms = String(o.delaiMs ?? 0)
            return o.essai.map { tr("confirmé en \(ms) ms (essai \($0))") } ?? tr("confirmé en \(ms) ms")
        case .abandon:
            // Essai 0 : l'ordre n'est jamais parti, le Bluetooth Mesh n'etait pas pret.
            if o.essai == 0 { return tr("abandonné : Bluetooth Mesh pas prêt, rien n'est parti vers la lampe") }
            let essais = o.essai ?? 0, ms = String(o.delaiMs ?? 0)
            return tr("abandonné après \(essais) essai(s), \(ms) ms : la lampe ne répond pas")
        case .tenu:
            return tr("déjà tenu : rien n'est parti vers la lampe")
        case .inconnu, nil:
            return tr("issue inconnue")
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
        let qui = t.lampe.map { tr("lampe \($0)") } ?? tr("groupe")
        let quoi = switch t.quoi {
        case .ordre: tr("ordre")
        case .demande: tr("demande d'état")
        case .etat: tr("état")
        case .inconnu, nil: tr("trame inconnue")
        }
        var texte = tr("\(sens) \(qui) : \(quoi)")
        if t.marche != nil || t.intensite != nil {
            var champs: [String] = []
            if let m = t.marche { champs.append(marche(m)) }
            if let i = t.intensite { champs.append(intensite(i)) }
            texte += " " + champs.joined(separator: ", ")
        }
        if let e = t.essai, t.quoi == .ordre { texte += tr(" (essai \(e))") }
        if let s = t.sautes, s > 0 { texte += tr(" — \(s) trame(s) non émise(s) avant") }
        return texte
    }

    static func marche(_ m: Bool) -> String { m ? tr("allumée") : tr("éteinte") }

    /// Intensite au dixieme de pour cent : « 43 % », « 43,5 % » (« 43% », « 43.5% » en anglais).
    public static func intensite(_ v: Int) -> String {
        if v % 10 == 0 { return tr("\(v / 10) %") }
        let p = decimal(Double(v) / 10, chiffres: 1)
        return tr("\(p) %")
    }

    /// Etat lu : « allumée, 43 % », « éteinte (43 %) », « noire (0 %) ».
    public static func etat(_ e: EtatLu?) -> String {
        guard let e, let marche = e.marche else { return tr("jamais lue") }
        let i = e.intensite.map(intensite) ?? "?"
        if e.noire { return tr("noire : en marche à 0 %") }
        return marche ? tr("allumée, \(i)") : tr("éteinte (\(i))")
    }

    /// Place d'une lampe dans Maison (5.3).
    public static func maison(_ m: BlocLampe.Maison?) -> String {
        guard let m else { return tr("inconnue") }
        if let ep = m.endpoint { return tr("dans Maison (EP\(ep))") }
        if m.masquee == true { return tr("retirée de Maison") }
        if m.vue != true { return tr("jamais vue : entrera dans Maison à sa première réponse") }
        return tr("hors de Maison (endpoint non créé)")
    }

    /// Cause d'un Bluetooth Mesh inoperant, et le remede (spec du pont 7.3).
    public static func diag(_ d: DiagMesh?) -> String {
        switch d {
        case .ok, nil: tr("opérationnel")
        case .clesAbsentes: tr("clés absentes : charger le pont depuis l'onglet Clés")
        case .pasEntre: tr("pas encore entré dans le réseau des lampes")
        case .clesPerimees: tr("aucune annonce de notre réseau : réseau recréé dans amaran Desktop ? Recopier les clés, puis recharger le pont")
        case .ivFaux: tr("NetMIC faux, rien de déchiffré : IV Index faux (mesh iv cherche)")
        case .inconnu: tr("cause inconnue")
        }
    }
}
