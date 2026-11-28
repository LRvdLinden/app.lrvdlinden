import SwiftUI

/// Blok "Betalingen controleren" op de omzetpagina (zoals loadPaymentsCheck in web/admin.js, actie `payments_check`):
/// controleert of er betalingen zijn misgelopen (Apple en Stripe). Alleen aantallen, nooit persoonsgegevens.
struct PaymentsCheckCard: View {
    @Environment(Session.self) private var session
    @State private var data: PaymentsCheck?
    @State private var note: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                CardHeader(title: "Betalingen controleren", subtitle: "Zijn er betalingen misgelopen? Apple en Stripe tegen onze administratie")
                Spacer(minLength: 8)
                Button { Task { await run() } } label: {
                    if busy { ProgressView() } else { Label("Nu controleren", systemImage: "checkmark.shield") }
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
            if let d = data {
                HStack(spacing: 8) {
                    Chip(text: d.attention ? "Aandacht nodig" : "Alles in orde", tone: d.attention ? .warn : .good,
                         icon: d.attention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text("Gecontroleerd \(Fmt.dateTime(d.checkedAt))").font(.caption).foregroundStyle(Color.textSecondary)
                }
                if d.issues.isEmpty {
                    EmptyText(text: "Geen problemen gevonden.")
                } else {
                    ForEach(d.issues) { i in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: i.error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.tone(i.error ? .bad : .warn))
                            Text(i.text).font(.subheadline)
                        }
                    }
                }
                if !d.days.isEmpty { daysTable(d.days) }
                apple(d)
                stripe(d)
                if d.hasSandbox { sandbox(d) }
                if d.hasFunnel { funnel(d) }
            } else if let note {
                EmptyText(text: note)
            } else if busy {
                ProgressView()
            } else {
                EmptyText(text: "Tik op Nu controleren.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .task { await run() }
    }

    private func daysTable(_ days: [PaymentsCheck.Day]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apple per dag").font(.subheadline.weight(.semibold))
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Dag").gridColumnAlignment(.leading)
                    Text("Verkocht"); Text("Nieuwe abo's"); Text("Lifetime")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(Color.textDim)
                ForEach(days) { d in
                    GridRow {
                        Text(d.shortDate).gridColumnAlignment(.leading)
                        Text(Fmt.num(d.sold)); Text(Fmt.num(d.new)); Text(Fmt.num(d.lifetime))
                    }
                    .font(.caption).monospacedDigit()
                }
            }
            Text("Verkocht komt van App Store Connect (loopt een dag achter); nieuwe abonnementen en Lifetime uit onze administratie.")
                .font(.caption2).foregroundStyle(Color.textDim)
        }
    }

    private func apple(_ d: PaymentsCheck) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apple").font(.subheadline.weight(.semibold))
            LabeledContent("Laatste verkoopdag", value: d.lastSalesDate ?? "—")
            LabeledContent("Nog niet aan een account gekoppeld (7 dagen)", value: Fmt.num(d.unlinked7d))
            LabeledContent("Daarvan nog geen mail", value: Fmt.num(d.unlinkedNoMail))
            if !d.notifications3d.isEmpty {
                Text("Notificaties (3 dagen)").font(.caption).foregroundStyle(Color.textDim)
                ForEach(d.notifications3d) { n in
                    LabeledContent(PaymentsCheck.resultText(n.key), value: Fmt.num(n.count))
                }
            }
        }
        .font(.callout)
    }

    private func stripe(_ d: PaymentsCheck) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stripe").font(.subheadline.weight(.semibold))
            if d.stripeQueried {
                LabeledContent("Betaald in Stripe (7 dagen)", value: d.paidInStripe7d.map { Fmt.num($0) } ?? "—")
            } else {
                Text("Stripe is niet bevraagd (geen sleutel of Stripe niet bereikbaar); alleen onze administratie is gecontroleerd.")
                    .font(.caption).foregroundStyle(Color.textDim)
            }
            LabeledContent("Vastgelegd bij ons (7 dagen)", value: Fmt.num(d.recorded7d))
            LabeledContent("Wacht al langer dan 1 uur", value: Fmt.num(d.pendingOver1h))
            LabeledContent("Onvolledig langer dan 1 dag", value: Fmt.num(d.incompleteOver1d))
            LabeledContent("Betaling achterstallig", value: Fmt.num(d.pastDue))
            if d.missing.isEmpty {
                if d.stripeQueried { Text("Geen misgelopen betalingen.").font(.caption).foregroundStyle(Color.textDim) }
            } else {
                Text("Misgelopen betalingen").font(.caption.weight(.semibold)).foregroundStyle(Color.tone(.bad))
                ForEach(d.missing) { m in
                    HStack {
                        Chip(text: m.kindText, tone: .bad)
                        Text(m.shortID).font(.caption.monospaced()).foregroundStyle(Color.textSecondary).textSelection(.enabled)
                        Spacer(minLength: 8)
                        Text("\(Fmt.euro(m.amountCents)) · \(Fmt.dateTime(m.paidAt))").font(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .font(.callout)
    }

    /// Accounts met toegang via een Apple-sandboxaankoop (testaankoop, niet betaald); tik = de accountlijst met dat filter.
    private func sandbox(_ d: PaymentsCheck) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sandbox (testaankopen)").font(.subheadline.weight(.semibold))
            Button {
                session.usersFilter = "sandbox"
                session.section = .users
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "testtube.2").foregroundStyle(Color.tone(d.sandboxLifetime > 0 ? .warn : .good))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Fmt.num(d.sandboxLifetime)) accounts met Lifetime via sandbox").font(.callout.weight(.semibold))
                        Text("Bekijk deze accounts in Gebruikers").font(.caption).foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Color.textDim)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.surface2))
            }
            .buttonStyle(.plain)
            LabeledContent("Daarvan actief in 7 dagen", value: Fmt.num(d.sandboxActive7d))
            LabeledContent("Tijdelijke toegang (testaccounts)", value: Fmt.num(d.sandboxTemporary))
            Text("Een sandbox-aankoop is een testaankoop: er is niet voor betaald. Intrekken kan per account bij Abonnement.")
                .font(.caption2).foregroundStyle(Color.textDim)
        }
        .font(.callout)
    }

    /// Betaaltrechter per dag en groep: betaalscherm getoond, koop gestart, gelukt; daarnaast mislukt en geannuleerd.
    private func funnel(_ d: PaymentsCheck) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Betaaltrechter").font(.subheadline.weight(.semibold))
            if d.funnelDays.isEmpty {
                Text("Nog geen metingen. De apps melden dit vanaf de build met de trechter.").font(.caption).foregroundStyle(Color.textDim)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            Text("Dag").gridColumnAlignment(.leading)
                            Text("Groep").gridColumnAlignment(.leading)
                            Text("Getoond"); Text("Gestart"); Text("Gelukt"); Text("Mislukt"); Text("Geannuleerd")
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.textDim)
                        ForEach(d.funnelDays) { f in
                            GridRow {
                                Text(f.shortDate).gridColumnAlignment(.leading)
                                Text(f.groupText).gridColumnAlignment(.leading)
                                Text(Fmt.num(f.shown)); Text(Fmt.num(f.started))
                                Text(Fmt.num(f.ok)).foregroundStyle(Color.tone(f.ok > 0 ? .good : .neutral))
                                Text(Fmt.num(f.failed)).foregroundStyle(Color.tone(f.failed > 0 ? .bad : .neutral))
                                Text(Fmt.num(f.cancelled))
                            }
                            .font(.caption).monospacedDigit()
                        }
                    }
                }
                Text("Getoond = het betaalscherm is geopend; gestart = op kopen gedrukt; gelukt = de aankoop is toegekend.")
                    .font(.caption2).foregroundStyle(Color.textDim)
            }
            if !d.funnelErrors.isEmpty {
                Text("Meest voorkomende fouten").font(.caption).foregroundStyle(Color.textDim)
                ForEach(d.funnelErrors) { e in
                    LabeledContent(e.error, value: Fmt.num(e.count))
                }
            }
        }
        .font(.callout)
    }

    private func run() async {
        if busy { return }
        busy = true
        defer { busy = false }
        do {
            data = PaymentsCheck(try await session.call("payments_check"))
            note = nil
        } catch let e as APIError where e.code == "unknown_action" || e.code == "not_found" {
            note = "De server kent de betalingencontrole nog niet (functie admin in bingr-beheer)."
        } catch {
            if !(error is CancellationError) { note = (error as? APIError)?.errorDescription ?? APIError.text("server_error") }
        }
    }
}
