# BizFlow — Billing, Udhaar & Credits

A mobile-first business app built from the attached BRD and FRD, narrowed to the three
accounts you asked for. Everything runs on **your local machine** — the database lives on
your own SQL Server instance (`DESKTOP-BV2BD6K`), not on a remote server.

```
Kittu Business/
├── API/                     ASP.NET Core 9 Web API + SQL Server scripts
│   ├── BizFlow.Api/         the API project
│   └── Database/            create-database + schema + verify scripts
├── Frontend/                Flutter mobile app (Android + iOS, no web)
└── README.md                this file
```

---

## 1. The three accounts

| Account | Who | What they can do |
|---|---|---|
| **Super Admin** | you, the platform owner | Every business, every account, all money, the WhatsApp outbox and the audit trail. Tap any shop owner to see their full shop profile, address and customer list; tap any customer to see their invoices, payments, credits and messages. Suspend a shop, deactivate a login, reset any password. |
| **User** (shop owner) | the business | Customers, products, billing, Udhaar collection, giving credit, approving credit claims, the customer-reputation lookup, dashboard and reports. Sees **only their own** business data. |
| **Customer** | the buyer | Four tabs only — a summary, their **invoices**, their **payments** and their **credits** (which they can claim). Nothing from the business side is reachable. |

**Every account is created on the contact number.** The 10-digit mobile is the login id and
the unique key for all three roles. A customer has **one** login even if five different shops
bill them — each shop keeps its own customer record, and all of them link back to that single
mobile number.

---

## 2. Sample accounts

All seeded automatically the first time the API starts.

| Role | Mobile (login) | Password | Notes |
|---|---|---|---|
| Super Admin | `9999900001` | `Admin@123` | Sees everything |
| Shop owner | `9999911111` | `User@123` | Sri Lakshmi Electricals, Hyderabad |
| Shop owner | `9999922222` | `User@123` | Kittu Kirana Store, Vijayawada |
| Customer | `9876500001` | `Cust@123` | Ramesh Kumar — buys from **both** shops |
| Customer | `9876500002` | `Cust@123` | Suresh Babu — has Udhaar |
| Customer | `9876500003` | `Cust@123` | Lakshmi Devi |

There is also **Anita Sharma (`9876500004`)** who exists as a customer record with *no* app
login — she shows what a walk-in customer looks like, and she is deliberately **not trusted**,
so the app refuses to give her Udhaar.

The login screen has a **tap-to-fill chip for each demo account**, so you never have to type these.

Seeded data: 2 shops, 10 products, 5 customer records, 5 bills, 3 credits and 1 credit
claim already waiting for approval.

---

## 3. Setup

### Step 1 — Database (already done on this machine)

```bash
cd "C:\Users\Lenovo\Desktop\Kittu Business\API\Database"; .\run-database-setup.ps1
```

This creates:

- Database **`BizFlowDb`** on `DESKTOP-BV2BD6K`
- A login **`bizflow_app`** / `BizFlow@2026#Sql` with `db_owner` on that database
- All 13 tables

> **Why a separate login instead of `sa`?** Your screenshot shows you connect as `sa` in SSMS.
> The API uses its own login so your `sa` password never has to be written into a config file.
> If you'd rather use `sa`, just change `ConnectionStrings:Default` in
> `API/BizFlow.Api/appsettings.json` — nothing else needs to change.

Verify any time:

```bash
sqlcmd -S DESKTOP-BV2BD6K -E -C -I -d BizFlowDb -i "C:\Users\Lenovo\Desktop\Kittu Business\API\Database\03_verify.sql"
```

### Step 2 — Start the API

```bash
cd "C:\Users\Lenovo\Desktop\Kittu Business\API\BizFlow.Api"; dotnet run
```

It listens on **`http://0.0.0.0:5000`** (bound to all interfaces so a phone on your Wi-Fi can
reach it). Swagger UI: <http://localhost:5000/swagger>. Health check: <http://localhost:5000/health>.

On first run it seeds the demo accounts; after that it leaves your data alone.

### Step 3 — Run the mobile app

```bash
cd "C:\Users\Lenovo\Desktop\Kittu Business\Frontend"; flutter run
```

**Pointing the app at the API** — the login screen has a **Server** button at the bottom:

| Running on | Address to use |
|---|---|
| Android emulator | `http://10.0.2.2:5000` (already the default) |
| Real Android/iOS phone on your Wi-Fi | `http://192.168.0.138:5000` |
| Windows desktop build | `http://localhost:5000` |

For a real phone, also allow port 5000 through the firewall once:

```bash
netsh advfirewall firewall add rule name="BizFlow API 5000" dir=in action=allow protocol=TCP localport=5000
```

---

## 4. How the money flows

### Billing → WhatsApp
The shop picks a customer, adds products, sets what was paid. On save the API, in one
transaction: numbers the bill, reduces stock, posts the ledger entries, updates the
customer's Udhaar, and queues a formatted WhatsApp bill.

### Udhaar (unpaid balance on a bill)
Only a **trusted** customer can walk out owing money, and only within their **credit limit**.
Bill an untrusted customer with an unpaid balance and the API refuses with a clear message.

### Credit (what you asked for: "give credits… generate amount… customer can claim it")

```
 Shop owner                        Customer                     Shop owner
     │                                 │                            │
 Give credit  ──WhatsApp──▶   Sees it in "My Credits"               │
 (trusted only,                        │                            │
  within limit)                    Tap "Claim"  ──WhatsApp──▶   Approve / Reject
     │                                 │                            │
     └── credit code CR-001-00001      └── claim goes Pending       └── on approve:
                                                                       • Udhaar goes down
                                                                       • credit balance goes down
                                                                       • ledger entry posted
                                                                       • customer told on WhatsApp
```

The customer can claim the whole credit or part of it. Partial claims leave the rest usable.

### Paying by UPI with a screenshot

```
 Customer                          Shop owner                      Customer
    │                                   │                              │
 Pays by UPI in their own app           │                              │
    │                                   │                              │
 Attaches the screenshot  ──WhatsApp──▶ Sees it in Customer payments   │
 + amount + reference                   │                              │
    │                                   ├── looks at the image         │
 Still Pending, nothing                 │                              │
 has moved in the books                 └── Approve  ──────WhatsApp──▶ UPDATED BILL
                                              │                        Total − Paid
                                              │                        = Remaining
                                              └── or Reject ──────────▶ told why
```

Approving does four things in one transaction: records a real payment with a receipt
number, reduces the bill and the customer's Udhaar, writes the ledger entry, and
**re-issues the bill** showing `Total − Paid = Remaining`.

The re-issue updates the original bill rather than creating a second invoice. Creating a
new sales invoice for the leftover would double-count revenue — the same goods would appear
twice in sales reports. The customer still gets exactly what was asked for: an updated bill
with the remaining amount.

Screenshots are served through an authenticated endpoint, not a public folder, because they
contain someone's payment details. Only the shop that received it, or Super Admin, can load
the image — another shop gets a 403.

### Running account when a customer buys again while owing

If a customer with unpaid dues buys again, the new bill goes out as an **account statement**
rather than a bare invoice: the new bill, then every earlier unpaid bill with its date, then
one combined total.

```
*NEW BILL*
21-Sept-2026  SLE-001-00005
  LED Bulb 9W x 3 = Rs.403.20
  Due        : Rs.403.20

*EARLIER UNPAID BILLS*
  19-Sept-2026  SLE-001-00002  due Rs.382.00
  21-Sept-2026  SLE-001-00004  due Rs.270.40
  Earlier due : Rs.652.40

*TOTAL AMOUNT DUE : Rs.1,055.60*
```

Both sides get the same view in-app: the owner from the customer screen, the customer from
their shop list. Bills over 30 days old are flagged. The owner can re-send the statement on
WhatsApp at any time.

### Sending a bill

New bill → pick customer → add products (or a **Quick item** typed at the counter) →
**Review & send**. A confirmation sheet lists the customer, every item and the totals with
two buttons: **Edit** (back to the bill, nothing lost) and **Confirm & send**. Only then is
the bill saved, WhatsApp opened, and the finished invoice shown with a sticky bar:
**WhatsApp** (asks "Send this bill?" first), **PDF** (share sheet: WhatsApp, Gmail, Drive…)
and **Print**. The PDF is a proper tax invoice with the shop's address and GSTIN.
Udhaar problems (untrusted customer, credit limit) are shown before saving, not after.

### Expenses

Owner → menu → **Expenses** (or the "This month" card on the dashboard). Record rent, stock
purchases, salary and so on; cancel a wrong entry with a long-press (kept for audit). This is
the "expenditure" side of every net figure.

### Super Admin analytics (in-app BI dashboard)

**Analytics** tab: a 7D / 30D / 90D / 12M / All slicer over gross sales, expenditure, net,
collections, Udhaar, GST, shops, shop owners and customers; a
sales-vs-collections-vs-expenditure trend; top shops (tap → that owner's full data,
their charts and their customers); collections by mode; expenditure by category; bills
by status; best-selling items.

**Customers** tab lists each **person once** (by mobile) with a "N shops" badge. Tap one to
see every shop they buy from, that shop's owner, and what they were billed, paid and owe there.

**Power BI Desktop:** Get Data → SQL Server → `DESKTOP-BV2BD6K` → `BizFlowDb`, then load
`vw_PowerBI_Sales`, `vw_PowerBI_Expenses`, `vw_PowerBI_Payments`, `vw_PowerBI_Customers`
and `vw_PowerBI_Shops` (created by `07_expenses_and_reporting.sql`).

### Customer reputation lookup

A shop owner taps the person-search icon, types a mobile number, and sees how that customer
behaves **across every shop on BizFlow** before deciding whether to give them Udhaar:

- **A 1–5 rating**, computed from payment behaviour — how much of what they were billed is
  settled, minus a penalty that grows the longer an unpaid bill sits (30/60/90 days). A
  number with no billing history shows as "New customer" rather than a flattering 5.
- **How many shops** they buy from, and how many bills in total.
- **A payment signal** — Good / Watch / Overdue — plus a flag if they have a bill over 30
  days unpaid at *another* shop.

**Privacy:** other shops' rupee amounts and names are never shown, only the score, the count
and the coarse signal. The requesting shop's own figures come back in full, because it
already owns that data. Super Admin does see everything, by name — that is the point of the
console.

### Light / dark mode and themes

Every role gets **Settings → Appearance**: System / Light / Dark, plus six palettes —
Classic Green, Royal Indigo, Deep Maroon, Ocean Teal, Saffron Gold and Midnight Slate. Each
is a Material 3 seed colour, so all six work in both light and dark.

The choice is cached on the device (so the app starts in the right theme without waiting for
the network) *and* saved to the account, so it follows the user to another phone.

### WhatsApp delivery

Out of the box the API runs in **`Log` mode**: it composes the real message, stores it in the
`WhatsAppMessages` outbox, and builds a **`wa.me` deep link**. The app opens that link so the
message goes out through your own WhatsApp — this works today with no paid account, which is
how most small Indian shops actually operate.

To send automatically through the **WhatsApp Business Cloud API**, fill in `appsettings.json`:

```json
"WhatsApp": {
  "Provider": "MetaCloud",
  "PhoneNumberId": "<your phone number id>",
  "AccessToken": "<your permanent token>"
}
```

No code change needed. Super Admin → WhatsApp tab shows every message, its status and its body.

---

## 5. What's in the database

14 tables on `BizFlowDb`, plus `PaymentProofs` for the UPI screenshots:

`Businesses` · `AppUsers` · `RefreshTokens` · `Customers` · `Products` · `Invoices` ·
`InvoiceItems` · `Payments` · `CreditGrants` · `CreditClaims` · `LedgerEntries` ·
`WhatsAppMessages` · `AuditLogs` · `Expenses`

Scripts run in order: `01_create_database` → `02_schema` → `04_preferences`
→ `05_payment_proofs` → `06_reconcile_balances` → `07_expenses_and_reporting` → `08_remove_subscriptions` (`03_verify` is the health check,
not a migration). All are additive and re-runnable.

`06_reconcile_balances` is a one-off repair worth knowing about. Approved credit claims and
payments not tied to a specific bill used to reduce the customer's outstanding without
touching the matching invoice balances, so a statement listed more unpaid than was actually
owed — Ramesh showed ₹1,152.40 due against ₹1,902.40 of listed bills. The app now allocates
such amounts to the oldest unpaid bills, and this script fixed the rows written before that.
Re-running it does nothing once the figures agree.

Screenshots are stored on disk under `API/BizFlow.Api/App_Data/uploads/`, not in the
database. Only the path, type and size are stored in `PaymentProofs`.

Ledger convention: **debit** increases what the customer owes, **credit** reduces it. Every
bill, payment and approved claim writes a row with a running balance, so a customer statement
always reconciles.

---

## 6. API reference (short version)

Everything returns the same envelope: `{ success, message, data, errors }`.

| Group | Endpoints |
|---|---|
| Auth (public) | `POST /api/auth/login`, `register-business`, `register-customer`, `refresh` |
| Auth (token) | `GET /api/auth/me`, `POST /api/auth/logout`, `change-password`, `PUT /api/auth/preferences` |
| Lookup | `GET /api/lookup/customer/{mobile}` |
| UPI proofs (owner) | `GET /api/payment-proofs`, `{id}/image`; `POST /api/payment-proofs/{id}/process` |
| UPI proofs (customer) | `POST /api/my/payment-proofs` (multipart), `GET /api/my/payment-proofs`, `POST /api/my/payment-proofs/{id}/cancel` |
| Statements | `GET /api/customers/{id}/statement`, `POST /api/customers/{id}/send-statement`, `GET /api/my/statement?businessId=` |
| Owner | `GET /api/dashboard`, `/api/dashboard/reports/summary` |
| Customers | `GET/POST /api/customers`, `PUT/DELETE /api/customers/{id}`, `POST /{id}/trust`, `GET /{id}/ledger` |
| Products | `GET/POST /api/products`, `PUT /{id}`, `POST /{id}/adjust-stock`, `GET /api/products/low-stock` |
| Billing | `GET/POST /api/invoices`, `GET /{id}`, `POST /{id}/cancel`, `POST /{id}/send-whatsapp` |
| Payments | `GET/POST /api/payments` |
| Credits | `GET /api/credits`, `POST /api/credits/issue`, `POST /{id}/cancel`, `GET /api/credits/claims`, `POST /api/credits/claims/{id}/process` |
| Customer app | `GET /api/my/dashboard`, `shops`, `bills`, `bills/{id}`, `payments`, `credits`, `claims`, `ledger`; `POST /api/my/credits/claim`, `claims/{id}/cancel` |
| Super Admin | `GET /api/admin/dashboard`, `businesses`, `users`, `users/{id}`, `customers`, `customers/{id}`, `whatsapp`, `audit`; `POST /api/admin/businesses/{id}/toggle-active`, `users/{id}/toggle-active`, `users/{id}/reset-password` |

---

## 7. Security notes

- Passwords are **BCrypt** hashed; plaintext is never stored or logged.
- JWT access token (8h) + refresh token (30d), both revoked on logout and on admin reset.
- **Tenant isolation is taken from the JWT, never from the request body.** A shop owner
  reading another shop's customer gets `403`; a customer hitting an owner endpoint gets `403`.
  Both cases are covered by the verification run below.
- Bills and credits are **cancelled, never deleted** — history stays auditable.
- Sensitive actions (login, billing, credit issue/approve, password reset, suspension) write
  to `AuditLogs`.

**Before this goes anywhere near real users**, change `Jwt:Key` and the `bizflow_app`
password, and put the API behind HTTPS. The current values are local-development defaults.

---

## 8. Verified end to end

Run against the live API on this machine:

| Check | Result |
|---|---|
| Shop owner login, dashboard, customer list | pass |
| Create bill (₹420 + ₹50.40 GST = ₹470.40, paid ₹200) → `PartiallyPaid`, ₹270.40 Udhaar | pass |
| Stock reduced, ledger posted, WhatsApp bill queued with `wa.me` link | pass |
| Issue ₹750 credit to a trusted customer | pass |
| Customer sees 3 credits across 2 shops | pass |
| Customer claims ₹750 → owner approves → Udhaar ₹2,902.40 → ₹2,152.40, credit ₹1,550 → ₹800 | pass |
| Shop A reading Shop B's customer | blocked, 403 |
| Customer calling the owner dashboard | blocked, 403 |
| Udhaar for an untrusted customer | rejected with a clear message |
| Credit beyond the customer's limit | rejected with a clear message |
| Billing more stock than exists | rejected with a clear message |
| Super Admin sees all 2 shops, 6 accounts, all money, WhatsApp outbox | pass |
| Lookup `9876500001` → 3.4 "Fair", 2 shops, 4 bills, Good signal | pass |
| Lookup an unknown number → "No shop has billed this number yet" | pass |
| Admin → shop owner → address, GST, stats and 3 customers | pass |
| Admin → customer → 3 bills, 3 payments, 2 credits, 2 claims, 7 ledger rows | pass |
| Customer blocked from `lookup` and `admin` endpoints | 403 each |
| Theme saved to the account and returned by `/api/auth/me` | pass |
| Dark mode + Deep Maroon applied live across the app | pass |
| Customer uploads a UPI screenshot → lands as Pending | pass |
| Second upload while one is pending → blocked | pass |
| Owner downloads the screenshot (3,803 bytes, byte-identical) | pass |
| A different shop requesting that screenshot | blocked, 403 |
| Approve → receipt RCP-001-00004, bill ₹2,632 − ₹2,250 paid = **₹382 remaining** | pass |
| Updated bill delivered on WhatsApp with the remaining amount | pass |
| New bill while dues exist → statement listing both earlier bills with dates | pass |
| Outstanding equals the sum of unpaid bills for every customer | pass |

---

## 9. Scope

Built, from the BRD/FRD: authentication and tenancy, customers and ledgers, products and
stock, billing, payments, Udhaar, credits with a claim workflow, WhatsApp notifications,
owner/customer/admin dashboards, the
cross-shop customer rating, per-account theming, audit logging and soft deletes.

Deliberately left out, because you scoped this to the two account types plus admin:
purchases and suppliers, employees and attendance, and multi-branch. The schema and tenancy
model leave room for all of them — `Businesses` is already a full tenant boundary, so adding
those modules does not require reworking anything here.
