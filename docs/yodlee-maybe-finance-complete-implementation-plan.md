# Yodlee × Maybe Finance – Complete Integration Plan  
_A hands-on guide for Eduardo (July 2025)_

---

## 0 · Prerequisites & Overview
• Self-hosted Maybe Finance (Docker Compose) already running  
• Basic Ruby/Rails & shell familiarity  
• Public HTTPS domain (Cloudflare Tunnel/ngrok) for Yodlee webhooks (optional)  
• 1–2 days of focused work

Flow:

```
User → FastLink Widget → Yodlee → Maybe webhook
Maybe → Yodlee REST → fetch accounts & transactions → store
Maybe background job → map Yodlee categoryId → Maybe Category → UI
```

---

## 1 · Account Signup & Key Generation

1. Visit https://developer.yodlee.com and **Register**.  
2. Verify email → Dashboard opens.
3. Dashboard ▸ **API Keys**  
   • Copy **Cobrand Client ID** and **Secret**.  
4. Still in Dashboard ▸ **FastLink Configuration**  
   • Click “Create new configuration”  
   • Enter _Company Name_ and choose template **Aggregation**.  
   • Publish to **Development** environment.  
5. Navigate to **Tokens** ▸ “Get Access Token”  
   • Use “Client Credentials” → copy `accessToken` (good for 30 min – runtime only).

Keep in a password manager:

```
YODLEE_CLIENT_ID=
YODLEE_SECRET=
YODLEE_BASE=https://development.api.envestnet.com/ysl
YODLEE_FASTLINK_URL=https://development.fastlink.envestnet.com
```

---

## 2 · Development Environment Setup

### 2.1 Update `.env`

```
# Yodlee
YODLEE_CLIENT_ID=xxx
YODLEE_SECRET=yyy
YODLEE_BASE=https://development.api.envestnet.com/ysl
YODLEE_FASTLINK_URL=https://development.fastlink.envestnet.com
YODLEE_COBRAND_NAME=<your dev username>
ENABLE_YODLEE=true
```

### 2.2 Add Gems

```
# Gemfile
gem 'faraday', '~> 2.9'
gem 'yodlee_sdk', git: 'https://github.com/your-fork/yodlee_ruby_sdk'
```

`bundle install` inside the `web` container.

---

## 3 · FastLink Integration (Account Linking UI)

### 3.1 Rails Controller

```ruby
# app/controllers/yodlee_tokens_controller.rb
class YodleeTokensController < ApplicationController
  def create
    token = Yodlee::Auth.client_token
    render json: { token: token, fastlink: ENV['YODLEE_FASTLINK_URL'] }
  end
end
```

### 3.2 Route

```ruby
post '/yodlee/token', to: 'yodlee_tokens#create'
```

### 3.3 Front-end Button

```erb
<!-- app/views/accounts/index.html.erb -->
<button id="link-yodlee" class="ds-button">Connect via Yodlee</button>
<script src="<%= ENV['YODLEE_FASTLINK_URL'] %>/fastlink/v4/initialize.js"></script>
<script>
document.getElementById('link-yodlee').onclick = async () => {
  const r = await fetch('/yodlee/token', {method:'POST'});
  const {token, fastlink} = await r.json();

  window.fastlink.open({
    fastLinkURL: fastlink,
    accessToken: token,
    params: { configName: 'Aggregation' },
    onSuccess: data => fetch('/yodlee/enrollments', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify(data)
    }),
    onError: err => alert('Yodlee error '+err.errorCode)
  });
};
</script>
```

### 3.4 Enrollment Receiver

```ruby
# app/controllers/yodlee_enrollments_controller.rb
class YodleeEnrollmentsController < ApplicationController
  skip_before_action :verify_authenticity_token
  def create
    YodleeAccountLinkJob.perform_later(current_user.id, params.to_unsafe_h)
    head :ok
  end
end
```

---

## 4 · API Integration for Data Sync

### 4.1 Service Wrapper

```ruby
# app/services/yodlee/client.rb
module Yodlee
  class Client
    def initialize
      @conn = Faraday.new(url: ENV['YODLEE_BASE'])
      @cobrand_token = auth_cobrand
    end

    def auth_cobrand
      res = @conn.post('/cobrand/login', {
        cobrand: { cobrandLogin: ENV['YODLEE_CLIENT_ID'],
                   cobrandPassword: ENV['YODLEE_SECRET'] }
      }.to_json, json_headers)
      res.body.dig('session', 'cobSession')
    end

    def create_user(user)
      res = @conn.post('/user/register', { user: { loginName: "u#{user.id}",
        password: SecureRandom.hex(8), email: user.email } }.to_json,
        json_headers.merge('Cobrand-Name': ENV['YODLEE_COBRAND_NAME'],
                           'Authorization': "cobSession=#{@cobrand_token}"))
      res.body['user']['session']['userSession']
    end

    def accounts(user_session)
      @conn.get('/accounts', {}, headers(user_session)).body['account']
    end

    def transactions(user_session, from:, to:)
      @conn.get('/transactions', {
        fromDate: from, toDate: to
      }, headers(user_session)).body['transaction']
    end

    private
    def json_headers = { 'Content-Type': 'application/json' }
    def headers(user_session) = json_headers
      .merge('Authorization': "cobSession=#{@cobrand_token},userSession=#{user_session}")
  end
end
```

### 4.2 Importer Job

```ruby
class YodleeAccountLinkJob < ApplicationJob
  queue_as :default
  def perform(user_id, enrollment)
    user = User.find(user_id)
    client = Yodlee::Client.new
    session = client.create_user(user)

    # Store session as Credential model
    cred = user.credentials.create!(provider: 'yodlee', token: session)

    ImportYodleeDataJob.perform_later(cred.id)
  end
end

class ImportYodleeDataJob < ApplicationJob
  def perform(cred_id)
    cred   = Credential.find(cred_id)
    client = Yodlee::Client.new
    accounts = client.accounts(cred.token)

    accounts.each do |acc|
      maybe_account = Account.find_or_create_by!(
        external_id: acc['id'], provider: 'yodlee') do |a|
        a.name = acc['providerName']
        a.account_type = acc['CONTAINER']
      end
      txs = client.transactions(cred.token, from: 1.month.ago.to_date, to: Date.today)
      txs.each { |t| Maybe::YodleeTxMapper.call(maybe_account, t) }
    end
  end
end
```

---

## 5 · Category Mapping

Yodlee supplies `categoryId` (0-999). Maybe uses text slug categories.

Create mapping file:

```yaml
# config/yodlee_categories.yml
101: groceries
102: restaurants
103: shopping
201: salary
298: transfer
```

Mapper helper:

```ruby
module Maybe
  class YodleeTxMapper
    MAP = YAML.load_file(Rails.root.join('config/yodlee_categories.yml'))

    def self.call(account, tx)
      category = MAP[tx['categoryId']] || 'uncategorized'
      account.transactions.create!(
        external_id: tx['id'],
        date: tx['date'],
        amount_cents: (tx['amount']['amount'].to_d * 100).to_i,
        payee: tx['description']['simple'],
        category_slug: category,
        raw: tx
      )
    end
  end
end
```

Users retain Maybe’s rule engine for further refinements.

---

## 6 · Testing & Deployment

1. **Local sandbox**: Use Yodlee dummy creds inside FastLink; ensure transactions appear.  
2. **RSpec**: Stub `Faraday` responses with recorded fixtures.  
3. **CI**: Add `ENABLE_YODLEE=false` to test env to skip live calls.  
4. **Production**: Generate new Client ID/Secret (Dashboard ▸ Keys ▸ Production).  
5. **Webhooks** (optional): Configure `/webhooks/yodlee` endpoint to handle transaction refresh events; expose via HTTPS tunnel.

---

## 7 · Cost Management & Monitoring

| Action | Where |
|--------|-------|
| Check activity usage | Yodlee Dashboard ▸ Usage |
| Set daily cron limit | Schedule ImportYodleeDataJob once nightly |
| Remove idle accounts | `cred.destroy` to stop refresh charges |
| Alert on overage | Add Prometheus exporter reading `/usage` API |

Tips:
• 100 activities/mo free → one daily refresh for 3–4 accounts stays free.  
• Each **/transactions** call counts 1 activity per account.  
• After trial, cost ≈ $0.15 – $0.35 per activity; budget in `.env MAX_DAILY_ACTIVITIES`.

---

## 8 · Timeline & Effort

| Task | Est. hrs |
|------|----------|
| Signup & keys | 0.5 |
| Gem & env setup | 1 |
| FastLink UI | 2 |
| Auth wrapper & jobs | 4 |
| Category mapping | 2 |
| Tests & cron | 2 |
| Docs & deploy | 1 |
| **Total** | **12 hrs (~1.5 days)** |

---

## 9 · Next Steps Checklist

1. [ ] Register at developer.yodlee.com and note keys  
2. [ ] Add env vars & gems, rebuild Docker images  
3. [ ] Implement controller, routes, and jobs above  
4. [ ] Create `config/yodlee_categories.yml` (start with sample)  
5. [ ] Run local FastLink flow → connect sandbox accounts  
6. [ ] Verify transactions auto-categorized in Maybe UI  
7. [ ] Move keys to production, schedule nightly sync  
8. [ ] Monitor dashboard usage after first month

You’re now equipped to get **fully automated, categorized data** into your self-hosted Maybe Finance without Plaid’s red tape. Happy hacking!
