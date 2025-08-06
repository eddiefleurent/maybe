class Provider::Yodlee
  attr_reader :client_id, :secret, :base_url, :fastlink_url

  API_VERSION = "1.1".freeze

  def initialize(config)
    @client_id = config[:client_id]
    @secret = config[:secret]
    @base_url = config[:base_url]
    @fastlink_url = config[:fastlink_url]

    @conn = Faraday.new(url: @base_url) do |f|
      f.response :json, content_type: /\bjson$/
      f.adapter  Faraday.default_adapter
    end
  end

  # ------------------------------------------------------------------
  # Authentication (v1.1)
  # ------------------------------------------------------------------
  #
  # v1.1 uses Client Credential OAuth-style tokens.
  # Optional `login_name` creates a user token; otherwise client-level.
  #
  def generate_access_token(login_name: nil)
    # Use direct HTTP approach that we know works
    require 'net/http'
    require 'uri'
    
    uri = URI("#{@base_url}/auth/token")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request['Api-Version'] = API_VERSION
    request['loginName'] = login_name if login_name

    params = {
      'clientId' => client_id,
      'secret' => secret
    }
    request.body = URI.encode_www_form(params)

    response = http.request(request)
    
    if response.code.to_i >= 200 && response.code.to_i < 300
      data = JSON.parse(response.body)
      data.dig("token", "accessToken")
    else
      error_data = JSON.parse(response.body) rescue {}
      error_message = error_data["errorMessage"] || "HTTP #{response.code}"
      raise StandardError, "Yodlee API Error: #{error_message} (#{error_data['errorCode']})"
    end
  end

  # PUBLIC API METHODS ------------------------------------------------

  def client_token
    # In v1.1, we need to use a pre-configured sandbox user for client-level operations
    admin_login = ENV["ADMIN_LOGIN_NAME"] || "sbMem6nt8db39480c61"
    generate_access_token(login_name: admin_login)
  end

  def create_user(user)
    login_name = "maybe_user_#{user.id}"
    
    # Try to get user token directly first
    begin
      user_token = generate_access_token(login_name: login_name)
      return user_token if user_token
    rescue => e
      # If user doesn't exist (Y305 error), we need to register first
      Rails.logger.info("User not registered, attempting registration: #{e.message}")
    end

    # Register the user first with client token
    client_token_val = client_token
    return nil unless client_token_val

    # Register user with direct HTTP
    uri = URI("#{@base_url}/user/register")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Api-Version'] = API_VERSION
    request['Authorization'] = "Bearer #{client_token_val}"

    user_data = {
      user: {
        loginName: login_name,
        email: user.email,
        password: SecureRandom.hex(12)
      }
    }
    request.body = user_data.to_json

    response = http.request(request)
    
    if response.code.to_i >= 200 && response.code.to_i < 300
      # After registration, get the user token
      generate_access_token(login_name: login_name)
    else
      # User might already exist, try to get token anyway
      generate_access_token(login_name: login_name)
    end
  end

  def get_user(user_token)
    get("/user", token: user_token).dig("user")
  end

  # Account methods
  def get_accounts(user_token)
    get("/accounts", token: user_token).dig("account") || []
  end

  def get_account_details(user_token, account_id)
    get("/accounts/#{account_id}", token: user_token).dig("account")
  end

  # Transaction methods
  def get_transactions(user_token, from:, to:)
    params = {
      fromDate: from.to_s,
      toDate: to.to_s
    }
    get("/transactions", params: params, token: user_token).dig("transaction") || []
  end

  def get_transaction_categories(user_token)
    get("/transactions/categories", token: user_token).dig("transactionCategory") || []
  end

  # Provider methods (institutions in v1.1 are called providers)
  def get_institution(provider_id)
    get("/providers/#{provider_id}", token: client_token).dig("provider")
  end

  def get_institutions
    get("/providers", token: client_token).dig("provider") || []
  end

  # FastLink methods
  def get_fastlink_token(user_token)
    # v1.1: FastLink just needs the user token and URL
    FastLinkTokenResponse.new(
      user_token: user_token,
      fastlink_url: fastlink_url
    )
  end

  # Convenience method for creating FastLink bundle
  def fastlink_bundle(user_token)
    get_fastlink_token(user_token)
  end

  private

  # Response structs
  FastLinkTokenResponse = Struct.new(:user_token, :fastlink_url, keyword_init: true)

  def get(path, token:, params: {})
    require 'net/http'
    require 'uri'
    
    query_string = params.empty? ? "" : "?#{URI.encode_www_form(params)}"
    uri = URI("#{@base_url}#{path}#{query_string}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request['Api-Version'] = API_VERSION
    request['Authorization'] = "Bearer #{token}"
    request['Content-Type'] = "application/json"

    response = http.request(request)
    
    if response.code.to_i >= 200 && response.code.to_i < 300
      JSON.parse(response.body)
    else
      error_data = JSON.parse(response.body) rescue {}
      error_message = error_data["errorMessage"] || "HTTP #{response.code}"
      Rails.logger.error("Yodlee API Error: #{error_message}")
      {}
    end
  end

  def headers(token)
    {
      "Api-Version"   => API_VERSION,
      "Authorization" => "Bearer #{token}",
      "Content-Type"  => "application/json"
    }
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
    
    error_message = if error_data["errorMessage"].present?
      "Yodlee API Error: #{error_data["errorMessage"]} (Code: #{error_data["errorCode"]})"
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
    
    # Raise error to trigger job retries
    raise StandardError, error_message
  end
end

