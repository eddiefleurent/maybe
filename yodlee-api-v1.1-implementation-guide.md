# Yodlee API v1.1 ‑ Implementation Guide  
_Maybe Finance – July 2025_

---

## 1. Background Job Requirements

| Concern | Plaid (current) | **Yodlee v1.1 (target)** | Action |
|---------|-----------------|--------------------------|--------|
| **Initial item link** | `PlaidAccountLinkJob` – stores item, schedules import | `YodleeAccountLinkJob` already present | ✅  No change |
| **Account & txn import** | `ImportPlaidDataJob` (accounts → transactions → valuations) | `ImportYodleeDataJob` already present; ensure it respects new token flow | 🔄  Verify headers / error handling |
| **Recurring sync** | `SyncJob` (daily), `SyncCleanerJob` | Yodlee items inherit `Syncable`, so jobs fire automatically | ✅  No new job |
| **Webhook processor** | `/webhooks/plaid` route handled by `WebhooksController` → schedules item sync | `/webhooks/yodlee` route handled → schedules item sync | ✅  Works as-is |
| **Edge/background jobs missing?** | n/a | _Historical balance_ back-fill (optional) | ➕  **Optional**: implement `ImportYodleeHistoricalBalancesJob` if net-worth history is required |

**Conclusion** – Yodlee already has parity with Plaid. Only verify existing jobs after provider refactor.  

---

## 2. Code Changes (complete snippets)

> All paths are relative to the Rails root.

### 2.1 `app/models/provider/yodlee.rb` (replace file)

```ruby
class Provider::Yodlee
  attr_reader :client_id, :secret, :base_url, :fastlink_url

  API_VERSION = "1.1".freeze

  def initialize(config)
    @client_id    = config[:client_id]
    @secret       = config[:secret]
    @base_url     = config[:base_url]
    @fastlink_url = config[:fastlink_url]

    @conn = Faraday.new(url: @base_url) do |f|
      f.request  :url_encoded        # for /auth/token
      f.request  :json               # all other calls
      f.response :json, content_type: /\bjson$/
      f.adapter  Faraday.default_adapter
    end
  end

  # ------------------------------------------------------------------
  # Authentication
  # ------------------------------------------------------------------
  #
  # v1.1 uses *Client Credential* OAuth-style tokens.
  # Optional `login_name` creates a **user token**; otherwise cobrand-level.
  #
  def generate_access_token(login_name: nil)
    body = {
      "clientId" => client_id,
      "secret"   => secret
    }
    body["loginName"] = login_name if login_name

    resp = @conn.post("/auth/token", body) do |r|
      r.headers["Content-Type"] = "application/x-www-form-urlencoded"
      r.headers["Api-Version"]  = API_VERSION
    end
    ok?(resp) ? resp.body.dig("token", "accessToken") : nil
  end

  # PUBLIC HELPERS ----------------------------------------------------
  def client_token
    generate_access_token          # cobrand-level
  end

  def create_user(user)
    # One-shot: POST /user/register with cobrand token, then return user token
    cobrand_token = client_token
    return unless cobrand_token

    resp = @conn.post("/user/register",
      { user: { loginName: "mf_user_#{user.id}", email: user.email, password: SecureRandom.hex(12) } },
      headers(cobrand_token)
    )
    return unless ok?(resp)

    generate_access_token(login_name: "mf_user_#{user.id}")
  end

  def get_accounts(user_token)
    get("/accounts", token: user_token).dig("account") || []
  end

  def get_transactions(user_token, from:, to:)
    get("/transactions",
        token: user_token,
        params: { fromDate: from.to_s, toDate: to.to_s }
    ).dig("transaction") || []
  end

  def get_institution(provider_id)
    get("/providers/#{provider_id}", token: client_token).dig("provider")
  end

  # FastLink token bundle used by UI
  FastLinkToken = Struct.new(:user_token, :fastlink_url, keyword_init: true)

  def fastlink_bundle(user_token)
    FastLinkToken.new(user_token:, fastlink_url:)
  end

  # ------------------------------------------------------------------
  private

  def get(path, token:, params: {})
    resp = @conn.get(path, params, headers(token))
    ok?(resp) ? resp.body : {}
  end

  def headers(token)
    {
      "Api-Version"  => API_VERSION,
      "Authorization"=> "Bearer #{token}"
    }
  end

  def ok?(resp)
    resp.status.between?(200,299)
  rescue => e
    Rails.logger.error("Yodlee API error #{e.message}")
    false
  end
end
```

### 2.2 `config/initializers/yodlee.rb`

```ruby
Rails.application.configure do
  config.yodlee = {
    client_id:    ENV.fetch("YODLEE_CLIENT_ID", nil),
    secret:       ENV.fetch("YODLEE_SECRET", nil),
    base_url:     ENV.fetch("YODLEE_BASE", "https://sandbox.api.yodlee.com/ysl"),
    fastlink_url: ENV.fetch("YODLEE_FASTLINK_URL", "https://fl4.sandbox.yodlee.com/authenticate/restserver/fastlink")
  }

  config.enable_yodlee = ENV["ENABLE_YODLEE"] == "true"
end
```

### 2.3 `app/models/family/yodlee_connectable.rb`
Replace `get_fastlink_token` call with:

```ruby
token_bundle = yodlee_provider.fastlink_bundle(user_session)
```

(And adjust usages: `.user_token`, `.fastlink_url`.)

### 2.4 `app/models/yodlee_item/importer.rb`
Update account fetch call:

```ruby
accounts = yodlee_provider.get_accounts(yodlee_item.user_session)
```

### 2.5 Optional Job (historical balances)

`app/jobs/import_yodlee_historical_balances_job.rb`

```ruby
class ImportYodleeHistoricalBalancesJob < ApplicationJob
  queue_as :low_priority

  def perform(yodlee_item_id, from_date, to_date)
    item    = YodleeItem.find(yodlee_item_id)
    token   = item.user_session
    prov    = Provider::Registry.get_provider(:yodlee)

    balances = prov.get("/accounts/historicalBalances",
                        token: token,
                        params: { fromDate: from_date, toDate: to_date }
               ).dig("accountHistoricalBalances") || []

    # Persist balances per account…
  end
end
```

_Add schedule in `config/sidekiq.yml` or Cron._

### 2.6 `config/yodlee_categories.yml`
We improved the file (full content committed earlier). Ensure it’s loaded via:

```ruby
CATEGORY_MAP = YAML.load_file(Rails.root.join("config/yodlee_categories.yml"))
```

### 2.7 **No new DB migrations**  
Schema already contains `yodlee_items` + `yodlee_accounts`. Only run:

```bash
bundle exec rails db:migrate
```

---

## 3. Step-by-Step Implementation

1. **Pull latest code**  
   `git checkout yodlee && git pull`

2. **Apply code patches above**  
   (Or cherry-pick commit `feat/yodlee-v1.1`).

3. **Bundle & migrate**  
   ```bash
   bundle install
   bundle exec rails db:migrate
   ```

4. **Set env vars** (`.env` or production secrets)  
   ```
   YODLEE_CLIENT_ID=xxxxxxxx
   YODLEE_SECRET=yyyyyyyy
   ENABLE_YODLEE=true
   ```

5. **Restart workers / web**  
   `docker compose restart web sidekiq`  

---

## 4. Testing & Verification

| Scenario | Steps | Expected |
|----------|-------|----------|
| **Token generation** | `rails c` → `Provider::Registry.get_provider(:yodlee).client_token` | 30-char JWT string |
| **User token flow** | Call `create_user(current_user)` | distinct JWT |
| **Link account (UI)** | Accounts → “Add via Yodlee” → FastLink | Widget opens, success callback hits `/yodlee_items` |
| **Background import** | Sidekiq jobs `YodleeAccountLinkJob` & `ImportYodleeDataJob` | Accounts/txns appear |
| **Sync webhook** | Hit `/webhooks/yodlee` with sample payload | Item queued for sync |
| **Historical balances** (optional) | Enqueue `ImportYodleeHistoricalBalancesJob` | Daily balance rows |

---

## 5. Migration / Roll-out Considerations

1. **Zero-downtime** – new provider code co-exists; old tokens keep working until re-connected.
2. **Secrets rotation** – rotate `YODLEE_SECRET` in production with maintenance window.
3. **Back-fill data** – first import may take minutes; stagger jobs to avoid API limits.
4. **Rate limits** – `ImportYodleeDataJob` already sleeps `0.5s`; tweak if hitting 429.
5. **Plaid parity** – families can link both Plaid & Yodlee items; ensure UI clarifies source.

---

## Appendix – File Checklist

```
app/models/provider/yodlee.rb
app/models/family/yodlee_connectable.rb
app/models/yodlee_item/importer.rb
app/jobs/import_yodlee_historical_balances_job.rb  (optional)
config/initializers/yodlee.rb
config/yodlee_categories.yml
```

_All changes are backward-compatible with existing Yodlee sandbox data._  
Happy Aggregating! 🚀
