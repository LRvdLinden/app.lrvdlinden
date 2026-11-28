import Foundation

/// Betalingen controleren (actie `payments_check` van de functie admin): controle op misgelopen betalingen, Apple en Stripe.
/// Alleen aantallen en korte kenmerken, nooit e-mailadressen of account-id's. Tolerant: ontbrekende velden zijn 0 of leeg.
struct PaymentsCheck {
    struct Issue: Identifiable, Hashable {
        let id: Int
        let error: Bool
        let key: String
        let nl: String
        let en: String
        init(_ j: JSON, _ i: Int) {
            id = i
            error = (j["level"].text ?? "warn") == "error"
            key = j["key"].text ?? ""
            nl = j["nl"].text ?? ""
            en = j["en"].text ?? ""
        }
        var text: String { nl.isEmpty ? (en.isEmpty ? key : en) : nl }
    }

    struct Day: Identifiable, Hashable {
        let date: String
        let sold: Int
        let new: Int
        let lifetime: Int
        var id: String { date }
        init(_ j: JSON) {
            date = j["date"].text ?? ""
            sold = j["apple_sold"].int ?? 0
            new = j["apple_new"].int ?? 0
            lifetime = j["apple_lifetime"].int ?? 0
        }
        /// "26 nov" uit "2026-11-26".
        var shortDate: String {
            let p = date.split(separator: "-")
            guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m) else { return date }
            let names = ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
            return "\(d) \(names[m - 1])"
        }
    }

    struct Missing: Identifiable, Hashable {
        let id: Int
        let kind: String
        let shortID: String
        let amountCents: Int
        let paidAt: Date?
        init(_ j: JSON, _ i: Int) {
            id = i
            kind = j["kind"].text ?? "checkout"
            shortID = j["short_id"].text ?? ""
            amountCents = j["amount_cents"].int ?? 0
            paidAt = j["paid_at"].date
        }
        var kindText: String { kind == "invoice" ? "Abonnementsbetaling" : "Lifetime" }
    }

    /// Betaaltrechter per dag en groep (`funnel.days`): betaalscherm getoond, koop gestart, gelukt, mislukt, geannuleerd.
    struct FunnelDay: Identifiable, Hashable {
        let date: String
        let group: String
        let shown: Int
        let started: Int
        let ok: Int
        let failed: Int
        let cancelled: Int
        var id: String { "\(date)|\(group)" }
        init(_ j: JSON) {
            date = j["date"].text ?? ""
            group = j["group"].text ?? ""
            shown = j["shown"].int ?? 0
            started = j["started"].int ?? 0
            ok = j["ok"].int ?? 0
            failed = j["failed"].int ?? 0
            cancelled = j["cancelled"].int ?? 0
        }
        var groupText: String { ["apple": "Apple", "android": "Android", "web": "Web"][group] ?? (group.isEmpty ? "—" : group) }
        /// "26 nov" uit "2026-11-26".
        var shortDate: String {
            let p = date.split(separator: "-")
            guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m) else { return date }
            let names = ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
            return "\(d) \(names[m - 1])"
        }
    }

    /// Meest voorkomende foutcode in de trechter (`funnel.top_errors`).
    struct FunnelError: Identifiable, Hashable {
        let error: String
        let count: Int
        var id: String { error }
    }

    struct Notif: Identifiable, Hashable {
        let key: String
        let count: Int
        var id: String { key }
    }

    let checkedAt: Date?
    let attention: Bool
    let issues: [Issue]
    let days: [Day]
    // Apple
    let lastSalesDate: String?
    let unlinked7d: Int
    let unlinkedNoMail: Int
    let notifications3d: [Notif]
    // Stripe
    let stripeQueried: Bool
    let paidInStripe7d: Int?
    let recorded7d: Int
    let missing: [Missing]
    let pendingOver1h: Int
    let incompleteOver1d: Int
    let pastDue: Int
    // Sandbox (testaankopen): nil = de server stuurt het blok nog niet
    let hasSandbox: Bool
    let sandboxLifetime: Int
    let sandboxActive7d: Int
    let sandboxTemporary: Int
    // Betaaltrechter: leeg = nog niet gemeten of de server stuurt hem nog niet
    let hasFunnel: Bool
    let funnelDays: [FunnelDay]
    let funnelErrors: [FunnelError]

    init(_ j: JSON) {
        let sb = j["sandbox"]
        hasSandbox = sb.object != nil
        sandboxLifetime = sb["lifetime_accounts"].int ?? 0
        sandboxActive7d = sb["active_7d"].int ?? 0
        sandboxTemporary = sb["temporary"].int ?? 0
        let f = j["funnel"]
        hasFunnel = f.object != nil
        funnelDays = f["days"].array.map(FunnelDay.init).sorted { $0.date != $1.date ? $0.date > $1.date : $0.group < $1.group }
        funnelErrors = f["top_errors"].array.compactMap { (e: JSON) -> FunnelError? in
            guard let name = e["error"].text, !name.isEmpty else { return nil }
            return FunnelError(error: name, count: e["n"].int ?? 0)
        }
        checkedAt = j["checked_at"].date
        attention = (j["verdict"].text ?? "ok") != "ok"
        issues = j["issues"].array.enumerated().map { Issue($1, $0) }
        days = j["days"].array.map(Day.init)
        let a = j["apple"]
        lastSalesDate = a["last_sales_date"].text
        unlinked7d = a["unlinked_7d"].int ?? 0
        unlinkedNoMail = a["unlinked_no_mail"].int ?? 0
        var notifs: [Notif] = []
        for (k, v) in a["notifications_3d"].object ?? [:] { notifs.append(Notif(key: k, count: v.int ?? 0)) }
        notifications3d = notifs.sorted { $0.count != $1.count ? $0.count > $1.count : $0.key < $1.key }
        let s = j["stripe"]
        stripeQueried = s["queried"].bool ?? false
        paidInStripe7d = s["paid_in_stripe_7d"].int
        recorded7d = s["recorded_7d"].int ?? 0
        missing = s["missing"].array.enumerated().map { Missing($1, $0) }
        pendingOver1h = s["pending_over_1h"].int ?? 0
        incompleteOver1d = s["incomplete_over_1d"].int ?? 0
        pastDue = s["past_due"].int ?? 0
    }

    /// Leesbare naam van een Apple-notificatieresultaat (onbekende blijven zoals ze zijn).
    static func resultText(_ k: String) -> String {
        ["premium_trialing_unlinked": "Proefperiode, nog niet gekoppeld", "premium_canceled_unlinked": "Opgezegd, nog niet gekoppeld",
         "premium_trialing_upsert": "Proefperiode bijgewerkt", "duplicate": "Al verwerkt", "test": "Test",
         "unknown_purchase": "Onbekende aankoop"][k] ?? k
    }
}
