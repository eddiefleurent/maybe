class Provider::Yodlee
  attr_reader :client_id, :secret, :base_url, :fastlink_url, :cobrand_name

  def initialize(config)
    @client_id = config[:client_id]
    @secret = config[:secret]
    @base_url = config[:base_url]
    @fastlink_url = config[:fastlink_url]
    @cobrand_name = config[:cobrand_name]
    @conn = Faraday.new(url: @base_url) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  # Authentication methods
  def auth_cobrand
    response = @conn.post('/cobrand/login', {
      cobrand: {
        cobrandLogin: client_id,
        cobrandPassword: secret
      }
    })
    
    handle_response(response) do |data|
      data.dig('session', 'cobSession')
    end
  end

  def client_token
    cobrand_token = auth_cobrand
    return nil unless cobrand_token

    # Return just the cobrand token for FastLink initialization
    cobrand_token
  end

  def create_user(user)
    cobrand_token = auth_cobrand
    return nil unless cobrand_token

    response = @conn.post('/user/register', {
      user: {
        loginName: "maybe_user_#{user.id}",
        password: SecureRandom.hex(8),
        email: user.email
      }
    }, headers(cobrand_token))
    
    handle_response(response) do |data|
      data.dig('user', 'session', 'userSession')
    end
  end

  def get_user(user_session, cobrand_token = nil)
    cobrand_token ||= auth_cobrand
    return nil unless cobrand_token && user_session

    response = @conn.get('/user', {}, user_headers(cobrand_token, user_session))
    
    handle_response(response) do |data|
      data['user']
    end
  end

  # Account methods
  def get_accounts(user_session, cobrand_token = nil)
    cobrand_token ||= auth_cobrand
    return nil unless cobrand_token && user_session

    response = @conn.get('/accounts', {}, user_headers(cobrand_token, user_session))
    
    handle_response(response) do |data|
      data['account']
    end
  end

  def get_account_details(user_session, account_id, cobrand_token = nil)
    cobrand_token ||= auth_cobrand
    return nil unless cobrand_token && user_session

    response = @conn.get("/accounts/#{account_id}", {}, user_headers(cobrand_token, user_session))
    
    handle_response(response) do |data|
      data['account']
    end
  end

  # Transaction methods
  def get_transactions(user_session, from:, to:, cobrand_token: nil)
    cobrand_token ||= auth_cobrand
    return nil unless cobrand_token && user_session

    params = {
      fromDate: from.to_s,
      toDate: to.to_s
    }

    response = @conn.get('/transactions', params, user_headers(cobrand_token, user_session))
    
    handle_response(response) do |data|
      data['transaction']
    end
  end

  def get_transaction_categories(user_session, cobrand_token = nil)
    cobrand_token ||= auth_cobrand
    return nil unless cobrand_token && user_session

    response = @conn.get('/transactions/categories', {}, user_headers(cobrand_token, user_session))
    
    handle_response(response) do |data|
      data['transactionCategory']
    end
  end

  # Institution methods
  def get_institution(institution_id, cobrand_token = nil)
    cobrand_token ||= auth_cobrand
    return nil unless cobrand_token

    response = @conn.get("/institutions/#{institution_id}", {}, headers(cobrand_token))
    
    handle_response(response) do |data|
      data['institution']
    end
  end

  def get_institutions(cobrand_token = nil)
    cobrand_token ||= auth_cobrand
    return nil unless cobrand_token

    response = @conn.get('/institutions', {}, headers(cobrand_token))
    
    handle_response(response) do |data|
      data['institution']
    end
  end

  # FastLink methods
  def get_fastlink_token(user_session, cobrand_token = nil)
    cobrand_token ||= auth_cobrand
    return nil unless cobrand_token && user_session

    # For FastLink, we need to return both tokens
    FastLinkTokenResponse.new(
      cobrand_token: cobrand_token,
      user_token: user_session,
      fastlink_url: fastlink_url
    )
  end

  private
    # Response structs
    FastLinkTokenResponse = Struct.new(:cobrand_token, :user_token, :fastlink_url, keyword_init: true)
    
    def headers(cobrand_token)
      {
        'Content-Type' => 'application/json',
        'Cobrand-Name' => cobrand_name,
        'Authorization' => "cobSession=#{cobrand_token}"
      }
    end

    def user_headers(cobrand_token, user_session)
      headers(cobrand_token).merge({
        'Authorization' => "cobSession=#{cobrand_token},userSession=#{user_session}"
      })
    end

    def handle_response(response)
      if response.status >= 200 && response.status < 300
        if block_given?
          yield response.body
        else
          response.body
        end
      else
        handle_error(response)
        nil
      end
    end

    def handle_error(response)
      error_data = response.body.is_a?(Hash) ? response.body : {}
      
      error_message = if error_data['errorMessage'].present?
        "Yodlee API Error: #{error_data['errorMessage']} (Code: #{error_data['errorCode']})"
      else
        "Yodlee API Error: HTTP #{response.status}"
      end

      Rails.logger.error(error_message)
      
      # Report to Sentry if available
      if defined?(Sentry)
        Sentry.capture_exception(
          StandardError.new(error_message),
          level: :error,
          extra: { response_body: error_data }
        )
      end
      
      nil
    end
end
