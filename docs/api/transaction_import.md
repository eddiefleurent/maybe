# Maybe Finance – Transaction Import Capabilities  
_Comprehensive Research Report_  

## 1. Executive Summary  
Maybe Finance already ships with a first-class Plaid integration that can automatically pull accounts, balances, and transactions (including investments & liabilities) for U.S. and EU users.  You **cannot** literally “just paste a single Plaid API key” and watch data appear—the minimum required is a Plaid **Client ID**, **Secret**, environment selection, and completion of the Plaid **Link** flow so the end-user authorises access to their institution.  Once configured, the app schedules background syncs and listens to Plaid webhooks for real-time updates.  

If you prefer full control or want to import from another data source, Maybe Finance exposes a documented REST API (OAuth 2.0 or API-Key) that lets you create and manage accounts and transactions programmatically.  

---

## 2. Option 1 – Built-in Plaid Integration  

### 2.1 What “out-of-the-box” really means  
• No extra code is required – Plaid models, controllers, jobs, webhooks, and UI screens already exist.  
• You *do* need to:  
  1. Obtain Plaid credentials (Client ID & Secret) and decide on the environment (`sandbox`, `development`, `production`).  
  2. Provide public URLs for webhooks (ngrok works in dev).  
  3. Run the Link flow in the UI (or via the API) so users connect their bank.  

### 2.2 Architecture & Data Flow  
```text
User ↔ Plaid Link (frontend) ──▶ Plaid API
          │ public_token
          ▼
Maybe backend exchanges token → PlaidItem (access_token saved, encrypted)
          │
          ├─ Initial sync: /accounts, /transactions/sync, investments/liabilities
          │
          └─ Webhook endpoint /webhooks/plaid
                • TRANSACTIONS:SYNC_UPDATES_AVAILABLE → schedule sync
                • HOLDINGS/INVESTMENTS updates → sync
```

Key objects:  
*PlaidItem* (one per connection) → *PlaidAccount* (one per financial account) → *Account*, *Entry*, *Transaction* etc.

### 2.3 Supported Products  
| Product | Status | Notes |
|---------|--------|-------|
| Transactions | ✅ | Up to 2 years history, incremental sync via cursor |
| Investments  | ✅ | Holdings, trades |  
| Liabilities  | ✅ | Credit cards, mortgages, student loans |  

### 2.4 Configuration Checklist  
Add to `.env` (or self-hosting settings):  
```
PLAID_CLIENT_ID=xxx
PLAID_SECRET=xxx
PLAID_ENV=sandbox           # or development / production
# EU keys (optional)
PLAID_EU_CLIENT_ID=
PLAID_EU_SECRET=
```
If you encrypt Rails credentials, Active Record encryption keys must also be present.

Webhooks in dev:  
```
DEV_WEBHOOKS_URL=https://<your-ngrok-id>.ngrok.io
```

### 2.5 Step-by-Step Setup  
1. **Get Plaid keys** in the Plaid dashboard.  
2. **Set env vars** and restart the Rails server.  
3. **Expose webhook URL** (`/webhooks/plaid`) publicly; in dev:  
   ```
   ngrok http 3000
   export DEV_WEBHOOKS_URL=https://<sub>.ngrok.app
   ```  
4. **Launch Link** – Navigate to Accounts → “Connect account” (or POST `/plaid_items` via API).  
5. **Complete bank login**; Maybe exchanges `public_token` → `access_token`, creates `PlaidItem`, schedules a sync.  
6. **Verify data** – Transactions appear after the first sync.  Webhooks keep them fresh automatically.  

### 2.6 Code references  
* `app/models/plaid_item.rb` – core model & sync triggers  
* `app/controllers/webhooks_controller.rb` – webhook validation  
* `config/initializers/plaid.rb` – credential wiring  

---

## 3. Option 2 – Custom API Integration  

Maybe Finance’s `/api/v1` exposes CRUD endpoints secured by OAuth 2.0 (Doorkeeper) or simple API keys.

### 3.1 Authentication  
```
Authorization: Bearer <oauth-access-token>
# or
X-Api-Key: <your-generated-key>
```
API keys are created in the Settings → Integrations → API Keys screen, with **read** or **read_write** scopes and rate-limit plan.

### 3.2 Key Endpoints  
| Method | Path | Purpose |
|--------|------|---------|
| GET    | /api/v1/accounts           | List user accounts |
| POST   | /api/v1/transactions       | Create a transaction |
| GET    | /api/v1/transactions/:id   | Retrieve |
| PATCH  | /api/v1/transactions/:id   | Update |
| DELETE | /api/v1/transactions/:id   | Delete |

### 3.3 Example – Importing a CSV row  
```bash
curl -X POST https://app.example.com/api/v1/transactions \
  -H "X-Api-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "transaction": {
      "account_id": 42,
      "date": "2025-07-01",
      "amount": 58.73,
      "nature": "expense",
      "name": "Coffee Shop"
    }
}'
```

### 3.4 Bulk Imports  
The API is per-transaction; for large backfills, loop through rows or spin up a small worker that respects rate-limits (default 600 req/min but check headers).

---

## 4. Implementation Guides  

### 4.1 Plaid (Option 1)  
1. Prepare the `.env` variables.  
2. Seed or create a user account.  
3. Start Sidekiq so background jobs can process syncs.  
4. Visit `/plaid_items/new` (or call the link-token endpoint if you build a custom front-end).  
5. Confirm transactions appear in `/transactions`.  

### 4.2 Custom API (Option 2)  
1. Generate an **API key** in Settings, choose `read_write` scope.  
2. Write an importer script (Node, Ruby, Python) to:  
   a. Create Accounts (if they don’t exist).  
   b. POST each transaction.  
   c. Optional: Tag, categorise, attach merchants.  
3. Monitor rate-limit headers:  
   ```
   X-RateLimit-Limit: 600
   X-RateLimit-Remaining: 597
   X-RateLimit-Reset: 54
   ```  
4. On success, Schedule `/sync` for each affected account (API currently internal; alternatively rely on nightly sync cascade).  

---

## 5. Comparison & Recommendations  

| Criteria | Plaid (built-in) | Custom API |
|----------|------------------|------------|
| Effort   | Low (configure & click) | Medium-High (write importer) |
| Real-time updates | Yes (webhooks) | Only if your source pushes |
| Data quality | Categorised, enriched by Plaid & Maybe AI | Whatever you supply |
| Cost      | Plaid fees apply | Free unless your source charges |
| Flexibility | Plaid-supported institutions only | Any source you control |

**Recommendation**: Use Plaid when possible; fall back to API if institution not supported or you already have your own aggregation pipeline.

---

## 6. Technical Requirements  

| Component | Requirement |
|-----------|-------------|
| Ruby      | `ruby 3.3.x` (see `.ruby-version`) |
| DB        | PostgreSQL ≥ 9.6 |
| Background | Sidekiq + Redis |
| Plaid     | Client ID, Secret, webhook URL reachable by Plaid |
| Web server| Port 3000 default (override `PORT`) |

---

## 7. Limitations & Considerations  

1. **Plaid Region** – EU users need separate keys; not every EU bank is supported.  
2. **Historical Window** – In dev mode the sync window is capped to 90 days (`Provider::Plaid::MAX_HISTORY_DAYS`).  
3. **Rate Limits** – API keys rate-limited; excessive writes will be throttled.  
4. **Data Mutability** – Transactions edited in the UI may lock certain attributes; subsequent Plaid updates will not overwrite locked fields.  
5. **Security** – Access tokens encrypted (requires Active Record encryption keys).  
6. **Maintenance** – The upstream repo is archived; community forks may diverge.

---

## 8. Sources  

Internal code review:  
* `app/models/plaid_item.rb`, `plaid_account.rb`, `plaid_item/importer.rb`  
* `app/controllers/plaid_items_controller.rb`, `webhooks_controller.rb`  
* `config/initializers/plaid.rb`, `.env.example`  
* `app/controllers/api/v1/transactions_controller.rb`, `base_controller.rb`

External documentation:  
* Plaid Docs – Transactions `/transactions/sync` and Webhooks – <https://plaid.com/docs/transactions/>  
* Plaid Docs – Investments – <https://plaid.com/docs/investments/>  
* Plaid Docs – Liabilities – <https://plaid.com/docs/liabilities/>  
