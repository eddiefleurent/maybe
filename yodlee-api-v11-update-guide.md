# Updating Maybe Finance Yodlee Integration to API v1.1

_Last revised: {{DATE}}_

---

## 1. Current Status

| Area | State | Notes |
|------|-------|-------|
| Provider class | **Uses v1.0 cobrand/user sessions** | Fails against modern sandbox |
| Models / DB | ✅ Already in place (`yodlee_items`, `yodlee_accounts`) | No changes needed |
| Background jobs | ✅ Jobs mirror Plaid (`ImportYodleeDataJob`, `YodleeAccountLinkJob`) | still valid |
| FastLink UI | ✅ Uses FastLink 4 widget | Only token generation changes |
| Webhooks | ✅ Endpoint exists | signature verification still not offered by Yodlee |

**Must-change surfaces**

1. Authentication → client-credential `/auth/token` (Bearer)  
2. HTTP headers → `Authorization: Bearer <token>` + `Api-Version: 1.1`  
3. Endpoint paths (e.g. `/accounts` same, but no cobSession query params)  
4. Error parsing (`YodleeError`) structure  
5. Optional: prune unused cobrand helpers & specs

---

## 2. Background Job Analysis vs Plaid

| Concern                          | Plaid                                | Yodlee (after update)               |
|----------------------------------|--------------------------------------|-------------------------------------|
| Link workflow job                | `PlaidItemLinkJob`                   | `YodleeAccountLinkJob` (✅)         |
| Import/sync job                  | `ImportPlaidDataJob`                 | `ImportYodleeDataJob` (✅)          |
| Syncable concern & `SyncJob`     | shared                               | shared                              |
| Rate limiting / retries          | handled in job                       | handled (`RATE_LIMIT_DELAY = 0.5`)  |
| Webhook refresh trigger          | Plaid `UPDATED_TRANSACTIONS` event   | Yodlee `REFRESHDATA_UPDATES` etc.   |

_No new jobs required._  Any additional workflows (e.g. consent renewal) can be piggy-backed onto existing jobs.

---

## 3. File-by-File Changes

### `app/models/provider/yodlee.rb` **(replace)**

```ruby
class Provider::Yodlee
  API_VERSION = "1.1".freeze

  def initialize(config)
    @client_id   = config[:client_id]
    @secret      = config[:secret]
    @base_url    = config[:base_url]
    @fastlink    = config[:fastlink_url]
    @conn = Faraday.new(url: @base_url) do |f|
      f.request  :url_encoded             # for /auth/token
      f.request  :json                    # JSON for everything else
      f.response :json, content_type: /\bjson$/
      f.adapter  Faraday.default_adapter
    end
  end

  # ------------------------------------------------------------------
  # Authentication
  # ------------------------------------------------------------------
  #
  #   POST /auth/token
  #   Body: clientId, secret, loginName? (creates implicit user)
  #
  def access_token(login_name: nil)
    resp = @conn.post("/auth/token",
                      { clientId: @client_id, secret: @secret, loginName: login_name }.compact) do |r|
      r.headers["Content-Type"] = "application/x-www-form-urlencoded"
      r.headers["Api-Version"]  = API_VERSION
    end
    parse(resp) { |json| json.dig("token", "accessToken") }
  end

  # FastLink token = user access token
  FastLink = Struct.new(:user_token, :fastlink_url, keyword_init: true)

  def fastlink_token(login_name:)
    FastLink.new(user_token: access_token(login_name:), fastlink_url: @fastlink)
  end

  # ------------------------------------------------------------------
  # User helpers
  # ------------------------------------------------------------------
  def get_user(user_token)
    get("/user", token: user_token).dig("user")
  end

  # ------------------------------------------------------------------
  # Accounts & Transactions
  # ------------------------------------------------------------------
  def accounts(user_token)
    get("/accounts", token: user_token).dig("account") || []
  end

  def transactions(user_token, from:, to:)
    params = { fromDate: from.to_s, toDate: to.to_s }
    get("/transactions", params:, token: user_token).dig("transaction") || []
  end

  # ------------------------------------------------------------------
  # Providers (institutions)
  # ------------------------------------------------------------------
  def provider(provider_id)
    get("/providers/#{provider_id}", token: access_token).dig("provider")
  end

  def providers
    get("/providers", token: access_token).dig("provider") || []
  end

  # ------------------------------------------------------------------
  private

  def get(path, params: {}, token:)
    parse @conn.get(path, params, headers(token))
  end

  def headers(token)
    { "Api-Version" => API_VERSION, "Authorization" => "Bearer #{token}" }
  end

  def parse(response)
    if response.success?
      block_given? ? yield(response.body) : response.body
    else
      handle_error(response)
    end
  end

  def handle_error(resp)
    detail = resp.body.is_a?(Hash) ? resp.body : {}
    msg = detail["errorMessage"] || "HTTP #{resp.status}"
    raise StandardError, "Yodlee API Error (#{resp.status}): #{msg}"
  end
end
```

### `family/yodlee_connectable.rb`

* Replace calls to `auth_cobrand` with new `access_token`.
* When creating a new user: `user_token = yodlee_provider.access_token(login_name: "maybe_user_#{user.id}")`.

### `yodlee_account.rb` / `import_yodlee_data_job.rb`

* Replace `provider.get_transactions(yodlee_item.user_session, …)` with `provider.transactions(yodlee_item.user_session, …)`
* Remove cobrand token params.

### Category map  
`config/yodlee_categories.yml` already present – ensure IDs cover new data set.

---

## 4. Authentication Flow (v1.1)

1. **Client-credential token** – always available for admin tasks  
   ```ruby
   admin_token = yodlee_provider.access_token          # no loginName
   ```

2. **User token** – pass a unique `loginName` (your own user id).  
   Yodlee auto-creates the user if not found.
   ```ruby
   user_token  = yodlee_provider.access_token(login_name: "maybe_user_#{user.id}")
   ```

3. **FastLink** – pass `user_token` to JS SDK:
   ```js
   window.fastlink.open({
     accessToken: { tokenType: "AccessToken", token: { value: "<%= token %>" } }
   })
   ```

4. **Headers** – every call after that:  
   ```
   Authorization: Bearer <token>
   Api-Version: 1.1
   ```

---

## 5. Endpoint Updates

| Old (v0.5)               | New (v1.1)                 | Notes |
|--------------------------|----------------------------|-------|
| POST `/cobrand/login`    | _removed_                  | use `/auth/token` |
| POST `/user/login`       | _removed_                  | implicit via loginName |
| GET `/accounts`          | unchanged                  | header update |
| GET `/transactions`      | unchanged                  | header update |
| GET `/institutions`      | now `/providers`           | and `/providers/{id}` |
| Webhook event names      | same                       | `REFRESHDATA_UPDATES`, etc. |

---

## 6. Error Handling

New error object:

```json
{
  "errorCode": "Y800",
  "errorMessage": "Invalid value for accountId"
}
```

Pattern:

```ruby
def handle_error(resp)
  data = resp.body rescue {}
  raise StandardError, "#{data['errorMessage']} (#{data['errorCode']})"
end
```

Jobs will retry automatically via ActiveJob when error is raised.

---

## 7. Testing Instructions

1. **Console smoke-test**
   ```bash
   user  = User.first
   prov  = Provider::Registry.get_provider(:yodlee)
   token = prov.access_token(login_name: "test_#{user.id}")
   prov.accounts(token)        # => should return array
   ```

2. **FastLink UI**
   * Navigate to `/yodlee_items/new`
   * Link sandbox institution (`Bank of Test - Sandbox`)
   * Confirm item appears and background sync job enqueued.

3. **Jobs**
   ```bash
   bundle exec sidekiq
   # watch ImportYodleeDataJob log output
   ```

4. **Webhooks**
   * Expose `/webhooks/yodlee` with ngrok.
   * In Yodlee dashboard, set callback URL, subscribe to `REFRESHDATA_UPDATES`.
   * Trigger refresh; verify job runs.

---

## 8. Environment Variables

| Variable | Required | Example |
|----------|----------|---------|
| `YODLEE_CLIENT_ID` | ✅ | `ab12cd34e5` |
| `YODLEE_SECRET` | ✅ | `s3cr3t` |
| `YODLEE_BASE` | ✅ | `https://sandbox.api.yodlee.com/ysl` |
| `YODLEE_FASTLINK_URL` | ✅ | `https://fl4.sandbox.yodlee.com/authenticate/restserver/fastlink` |
| `YODLEE_COBRAND_NAME` | ❌ (legacy) | can be removed |
| `ENABLE_YODLEE` | ✅ | `true` |

---

## 9. Migration & Roll-out Steps

1. **Create feature branch**  
   `git checkout -b chore/yodlee-v11`
2. **Gem updates**  
   Ensure `faraday` ≥ 2.x and `faraday-multipart` in Gemfile.
3. **Code changes** – commit files above.
4. **Bundle & migrate**  
   ```bash
   bundle install
   rails db:migrate
   ```
5. **Staging deploy** – set new ENV vars, disable old cobrand endpoints.
6. **Run smoke tests (section 7)**.
7. **Production flag**  
   Set `ENABLE_YODLEE=true`, deploy, monitor jobs & logs.

---

## 10. Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `401 Unauthorized` | Using cobrand token in header | Use `Bearer <accessToken>` |
| `Y016 : Api-Version header missing` | Header typo | Add `Api-Version: 1.1` to every call |
| FastLink opens then closes | Wrong token object | Ensure `tokenType: "AccessToken"` |
| Accounts import empty | Sandbox institution has no data | Use `Bank of Test` / ensure date range ≤ 2 y |
| `Y800 : Invalid value for ...` | Bad query param type | Check params (e.g. string IDs comma-sep) |
| Webhooks never fire | Callback URL not https / port blocked | Use ngrok or public https |

---

### Done!

Following the steps above will upgrade Maybe Finance to Yodlee API v1.1 without breaking existing workflows. Reach out on Slack `#fin-integrations` if you hit edge-cases not covered here.
