require 'test_helper'

class Provider::YodleeTest < ActiveSupport::TestCase
  setup do
    @config = {
      client_id: 'test_client_id',
      secret: 'test_secret',
      base_url: 'https://development.api.envestnet.com/ysl',
      fastlink_url: 'https://development.fastlink.envestnet.com',
      cobrand_name: 'test_cobrand'
    }
    @yodlee = Provider::Yodlee.new(@config)
    @user = users(:one)
    @cobrand_token = 'test_cobrand_token'
    @user_session = 'test_user_session'
  end

  teardown do
    WebMock.reset!
  end

  # Initialization tests
  test "should initialize with configuration" do
    yodlee = Provider::Yodlee.new(@config)
    
    assert_equal 'test_client_id', yodlee.client_id
    assert_equal 'test_secret', yodlee.secret
    assert_equal 'https://development.api.envestnet.com/ysl', yodlee.base_url
    assert_equal 'https://development.fastlink.envestnet.com', yodlee.fastlink_url
    assert_equal 'test_cobrand', yodlee.cobrand_name
  end

  test "should initialize Faraday connection" do
    yodlee = Provider::Yodlee.new(@config)
    
    assert_not_nil yodlee.instance_variable_get(:@conn)
    assert_equal @config[:base_url], yodlee.instance_variable_get(:@conn).url_prefix.to_s
  end

  # Authentication tests - auth_cobrand
  test "should authenticate cobrand successfully" do
    VCR.use_cassette("yodlee/auth_cobrand_success") do
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .with(
          body: {
            cobrand: {
              cobrandLogin: @config[:client_id],
              cobrandPassword: @config[:secret]
            }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
        .to_return(
          status: 200,
          body: {
            session: {
              cobSession: @cobrand_token
            }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = @yodlee.auth_cobrand
      
      assert_equal @cobrand_token, result
    end
  end

  test "should handle cobrand authentication failure" do
    VCR.use_cassette("yodlee/auth_cobrand_failure") do
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .to_return(
          status: 401,
          body: {
            errorCode: 'Y013',
            errorMessage: 'Invalid cobrand credentials'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = @yodlee.auth_cobrand
      
      assert_nil result
    end
  end

  test "should handle cobrand authentication network error" do
    stub_request(:post, "#{@config[:base_url]}/cobrand/login")
      .to_raise(Faraday::ConnectionFailed.new('Connection failed'))

    assert_raises(Faraday::ConnectionFailed) do
      @yodlee.auth_cobrand
    end
  end

  # Client token tests
  test "should return client token from cobrand authentication" do
    VCR.use_cassette("yodlee/client_token_success") do
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .to_return(
          status: 200,
          body: {
            session: {
              cobSession: @cobrand_token
            }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = @yodlee.client_token
      
      assert_equal @cobrand_token, result
    end
  end

  test "should return nil client token when cobrand auth fails" do
    VCR.use_cassette("yodlee/client_token_failure") do
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .to_return(status: 401, body: '{"errorCode": "Y013"}')

      result = @yodlee.client_token
      
      assert_nil result
    end
  end

  # User creation tests
  test "should create user successfully" do
    VCR.use_cassette("yodlee/create_user_success") do
      # Mock cobrand auth
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .to_return(
          status: 200,
          body: { session: { cobSession: @cobrand_token } }.to_json
        )

      # Mock user creation
      stub_request(:post, "#{@config[:base_url]}/user/register")
        .with(
          headers: {
            'Content-Type' => 'application/json',
            'Cobrand-Name' => @config[:cobrand_name],
            'Authorization' => "cobSession=#{@cobrand_token}"
          }
        )
        .to_return(
          status: 200,
          body: {
            user: {
              session: {
                userSession: @user_session
              }
            }
          }.to_json
        )

      result = @yodlee.create_user(@user)
      
      assert_equal @user_session, result
    end
  end

  test "should handle user creation failure" do
    VCR.use_cassette("yodlee/create_user_failure") do
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .to_return(
          status: 200,
          body: { session: { cobSession: @cobrand_token } }.to_json
        )

      stub_request(:post, "#{@config[:base_url]}/user/register")
        .to_return(
          status: 400,
          body: {
            errorCode: 'Y013',
            errorMessage: 'User creation failed'
          }.to_json
        )

      result = @yodlee.create_user(@user)
      
      assert_nil result
    end
  end

  test "should return nil when cobrand auth fails during user creation" do
    VCR.use_cassette("yodlee/create_user_no_cobrand") do
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .to_return(status: 401, body: '{}')

      result = @yodlee.create_user(@user)
      
      assert_nil result
    end
  end

  # Get user tests
  test "should get user successfully" do
    VCR.use_cassette("yodlee/get_user_success") do
      stub_request(:get, "#{@config[:base_url]}/user")
        .with(
          headers: {
            'Content-Type' => 'application/json',
            'Cobrand-Name' => @config[:cobrand_name],
            'Authorization' => "cobSession=#{@cobrand_token},userSession=#{@user_session}"
          }
        )
        .to_return(
          status: 200,
          body: {
            user: {
              id: 123,
              loginName: 'test_user',
              email: @user.email
            }
          }.to_json
        )

      result = @yodlee.get_user(@user_session, @cobrand_token)
      
      assert_not_nil result
      assert_equal 123, result['id']
      assert_equal 'test_user', result['loginName']
    end
  end

  test "should return nil when get user fails" do
    VCR.use_cassette("yodlee/get_user_failure") do
      stub_request(:get, "#{@config[:base_url]}/user")
        .to_return(status: 401, body: '{"errorCode": "Y013"}')

      result = @yodlee.get_user(@user_session, @cobrand_token)
      
      assert_nil result
    end
  end

  test "should return nil when user session or cobrand token missing" do
    assert_nil @yodlee.get_user(nil, @cobrand_token)
    assert_nil @yodlee.get_user(@user_session, nil)
    assert_nil @yodlee.get_user(nil, nil)
  end

  # Account tests
  test "should get accounts successfully" do
    VCR.use_cassette("yodlee/get_accounts_success") do
      accounts_data = [
        {
          'id' => 123,
          'accountName' => 'Test Checking',
          'balance' => { 'amount' => 1500.50, 'currency' => 'USD' },
          'accountType' => 'CHECKING'
        }
      ]

      stub_request(:get, "#{@config[:base_url]}/accounts")
        .with(
          headers: {
            'Content-Type' => 'application/json',
            'Cobrand-Name' => @config[:cobrand_name],
            'Authorization' => "cobSession=#{@cobrand_token},userSession=#{@user_session}"
          }
        )
        .to_return(
          status: 200,
          body: { account: accounts_data }.to_json
        )

      result = @yodlee.get_accounts(@user_session, @cobrand_token)
      
      assert_equal accounts_data, result
      assert_equal 1, result.length
      assert_equal 'Test Checking', result.first['accountName']
    end
  end

  test "should handle empty accounts response" do
    VCR.use_cassette("yodlee/get_accounts_empty") do
      stub_request(:get, "#{@config[:base_url]}/accounts")
        .to_return(
          status: 200,
          body: { account: [] }.to_json
        )

      result = @yodlee.get_accounts(@user_session, @cobrand_token)
      
      assert_equal [], result
    end
  end

  test "should return nil when get accounts fails" do
    VCR.use_cassette("yodlee/get_accounts_failure") do
      stub_request(:get, "#{@config[:base_url]}/accounts")
        .to_return(status: 500, body: '{"errorCode": "Y013"}')

      result = @yodlee.get_accounts(@user_session, @cobrand_token)
      
      assert_nil result
    end
  end

  # Account details tests
  test "should get account details successfully" do
    VCR.use_cassette("yodlee/get_account_details_success") do
      account_id = '123'
      account_data = {
        'id' => 123,
        'accountName' => 'Test Checking',
        'balance' => { 'amount' => 1500.50, 'currency' => 'USD' },
        'accountType' => 'CHECKING',
        'accountStatus' => 'ACTIVE'
      }

      stub_request(:get, "#{@config[:base_url]}/accounts/#{account_id}")
        .with(
          headers: {
            'Content-Type' => 'application/json',
            'Cobrand-Name' => @config[:cobrand_name],
            'Authorization' => "cobSession=#{@cobrand_token},userSession=#{@user_session}"
          }
        )
        .to_return(
          status: 200,
          body: { account: account_data }.to_json
        )

      result = @yodlee.get_account_details(@user_session, account_id, @cobrand_token)
      
      assert_equal account_data, result
      assert_equal 'Test Checking', result['accountName']
      assert_equal 'ACTIVE', result['accountStatus']
    end
  end

  test "should return nil for invalid account id" do
    VCR.use_cassette("yodlee/get_account_details_invalid") do
      stub_request(:get, "#{@config[:base_url]}/accounts/invalid")
        .to_return(status: 404, body: '{"errorCode": "Y013"}')

      result = @yodlee.get_account_details(@user_session, 'invalid', @cobrand_token)
      
      assert_nil result
    end
  end

  # Transaction tests
  test "should get transactions successfully" do
    VCR.use_cassette("yodlee/get_transactions_success") do
      from_date = Date.parse('2023-01-01')
      to_date = Date.parse('2023-01-31')
      
      transactions_data = [
        {
          'id' => 456,
          'amount' => { 'amount' => -25.99, 'currency' => 'USD' },
          'date' => '2023-01-15',
          'description' => { 'original' => 'GROCERY STORE' }
        }
      ]

      stub_request(:get, "#{@config[:base_url]}/transactions")
        .with(
          query: {
            fromDate: from_date.to_s,
            toDate: to_date.to_s
          },
          headers: {
            'Content-Type' => 'application/json',
            'Cobrand-Name' => @config[:cobrand_name],
            'Authorization' => "cobSession=#{@cobrand_token},userSession=#{@user_session}"
          }
        )
        .to_return(
          status: 200,
          body: { transaction: transactions_data }.to_json
        )

      result = @yodlee.get_transactions(@user_session, from: from_date, to: to_date, cobrand_token: @cobrand_token)
      
      assert_equal transactions_data, result
      assert_equal 1, result.length
      assert_equal 'GROCERY STORE', result.first['description']['original']
    end
  end

  test "should handle empty transactions response" do
    VCR.use_cassette("yodlee/get_transactions_empty") do
      from_date = Date.current - 30.days
      to_date = Date.current

      stub_request(:get, "#{@config[:base_url]}/transactions")
        .to_return(
          status: 200,
          body: { transaction: [] }.to_json
        )

      result = @yodlee.get_transactions(@user_session, from: from_date, to: to_date)
      
      assert_equal [], result
    end
  end

  test "should return nil when transactions request fails" do
    VCR.use_cassette("yodlee/get_transactions_failure") do
      stub_request(:get, "#{@config[:base_url]}/transactions")
        .to_return(status: 500, body: '{"errorCode": "Y013"}')

      result = @yodlee.get_transactions(@user_session, from: Date.current, to: Date.current)
      
      assert_nil result
    end
  end

  # Transaction categories tests
  test "should get transaction categories successfully" do
    VCR.use_cassette("yodlee/get_transaction_categories_success") do
      categories_data = [
        {
          'id' => 1,
          'category' => 'Food',
          'classification' => 'EXPENSE'
        },
        {
          'id' => 2,
          'category' => 'Transportation',
          'classification' => 'EXPENSE'
        }
      ]

      stub_request(:get, "#{@config[:base_url]}/transactions/categories")
        .with(
          headers: {
            'Content-Type' => 'application/json',
            'Cobrand-Name' => @config[:cobrand_name],
            'Authorization' => "cobSession=#{@cobrand_token},userSession=#{@user_session}"
          }
        )
        .to_return(
          status: 200,
          body: { transactionCategory: categories_data }.to_json
        )

      result = @yodlee.get_transaction_categories(@user_session, @cobrand_token)
      
      assert_equal categories_data, result
      assert_equal 2, result.length
      assert_equal 'Food', result.first['category']
    end
  end

  test "should return nil when transaction categories request fails" do
    VCR.use_cassette("yodlee/get_transaction_categories_failure") do
      stub_request(:get, "#{@config[:base_url]}/transactions/categories")
        .to_return(status: 500, body: '{"errorCode": "Y013"}')

      result = @yodlee.get_transaction_categories(@user_session, @cobrand_token)
      
      assert_nil result
    end
  end

  # Institution tests
  test "should get institution successfully" do
    VCR.use_cassette("yodlee/get_institution_success") do
      institution_id = '16441'
      institution_data = {
        'id' => 16441,
        'name' => 'Chase Bank',
        'loginUrl' => 'https://www.chase.com',
        'isAddedByUser' => 'true'
      }

      stub_request(:get, "#{@config[:base_url]}/institutions/#{institution_id}")
        .with(
          headers: {
            'Content-Type' => 'application/json',
            'Cobrand-Name' => @config[:cobrand_name],
            'Authorization' => "cobSession=#{@cobrand_token}"
          }
        )
        .to_return(
          status: 200,
          body: { institution: institution_data }.to_json
        )

      result = @yodlee.get_institution(institution_id, @cobrand_token)
      
      assert_equal institution_data, result
      assert_equal 'Chase Bank', result['name']
    end
  end

  test "should return nil for invalid institution id" do
    VCR.use_cassette("yodlee/get_institution_invalid") do
      stub_request(:get, "#{@config[:base_url]}/institutions/invalid")
        .to_return(status: 404, body: '{"errorCode": "Y013"}')

      result = @yodlee.get_institution('invalid', @cobrand_token)
      
      assert_nil result
    end
  end

  test "should get institutions list successfully" do
    VCR.use_cassette("yodlee/get_institutions_success") do
      institutions_data = [
        {
          'id' => 16441,
          'name' => 'Chase Bank'
        },
        {
          'id' => 16442,
          'name' => 'Bank of America'
        }
      ]

      stub_request(:get, "#{@config[:base_url]}/institutions")
        .with(
          headers: {
            'Content-Type' => 'application/json',
            'Cobrand-Name' => @config[:cobrand_name],
            'Authorization' => "cobSession=#{@cobrand_token}"
          }
        )
        .to_return(
          status: 200,
          body: { institution: institutions_data }.to_json
        )

      result = @yodlee.get_institutions(@cobrand_token)
      
      assert_equal institutions_data, result
      assert_equal 2, result.length
    end
  end

  # FastLink token tests
  test "should get fastlink token successfully" do
    VCR.use_cassette("yodlee/get_fastlink_token_success") do
      # Mock cobrand auth for when cobrand_token is nil
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .to_return(
          status: 200,
          body: { session: { cobSession: @cobrand_token } }.to_json
        )

      result = @yodlee.get_fastlink_token(@user_session)
      
      assert_instance_of Provider::Yodlee::FastLinkTokenResponse, result
      assert_equal @cobrand_token, result.cobrand_token
      assert_equal @user_session, result.user_token
      assert_equal @config[:fastlink_url], result.fastlink_url
    end
  end

  test "should get fastlink token with provided cobrand token" do
    result = @yodlee.get_fastlink_token(@user_session, @cobrand_token)
    
    assert_instance_of Provider::Yodlee::FastLinkTokenResponse, result
    assert_equal @cobrand_token, result.cobrand_token
    assert_equal @user_session, result.user_token
    assert_equal @config[:fastlink_url], result.fastlink_url
  end

  test "should return nil fastlink token when cobrand auth fails" do
    VCR.use_cassette("yodlee/get_fastlink_token_failure") do
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .to_return(status: 401, body: '{}')

      result = @yodlee.get_fastlink_token(@user_session)
      
      assert_nil result
    end
  end

  test "should return nil fastlink token when user session missing" do
    result = @yodlee.get_fastlink_token(nil, @cobrand_token)
    
    assert_nil result
  end

  # Error handling tests
  test "should handle JSON parse errors gracefully" do
    VCR.use_cassette("yodlee/invalid_json_response") do
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .to_return(status: 200, body: 'invalid json')

      # Should not raise an exception, should handle gracefully
      assert_nothing_raised do
        result = @yodlee.auth_cobrand
        assert_nil result
      end
    end
  end

  test "should log error messages appropriately" do
    VCR.use_cassette("yodlee/error_logging") do
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .to_return(
          status: 400,
          body: {
            errorCode: 'Y013',
            errorMessage: 'Invalid credentials provided'
          }.to_json
        )

      # Capture Rails logger output
      log_output = capture_logs do
        @yodlee.auth_cobrand
      end

      assert_includes log_output, 'Yodlee API Error'
      assert_includes log_output, 'Invalid credentials provided'
      assert_includes log_output, 'Y013'
    end
  end

  test "should handle network timeouts gracefully" do
    stub_request(:post, "#{@config[:base_url]}/cobrand/login")
      .to_timeout

    assert_raises(Net::TimeoutError) do
      @yodlee.auth_cobrand
    end
  end

  test "should handle rate limiting responses" do
    VCR.use_cassette("yodlee/rate_limit_response") do
      stub_request(:post, "#{@config[:base_url]}/cobrand/login")
        .to_return(
          status: 429,
          body: {
            errorCode: 'Y013',
            errorMessage: 'Rate limit exceeded'
          }.to_json,
          headers: { 'Retry-After' => '60' }
        )

      result = @yodlee.auth_cobrand
      
      assert_nil result
    end
  end

  # Header construction tests
  test "should construct correct headers for cobrand requests" do
    expected_headers = {
      'Content-Type' => 'application/json',
      'Cobrand-Name' => @config[:cobrand_name],
      'Authorization' => "cobSession=#{@cobrand_token}"
    }

    actual_headers = @yodlee.send(:headers, @cobrand_token)
    
    assert_equal expected_headers, actual_headers
  end

  test "should construct correct headers for user requests" do
    expected_headers = {
      'Content-Type' => 'application/json',
      'Cobrand-Name' => @config[:cobrand_name],
      'Authorization' => "cobSession=#{@cobrand_token},userSession=#{@user_session}"
    }

    actual_headers = @yodlee.send(:user_headers, @cobrand_token, @user_session)
    
    assert_equal expected_headers, actual_headers
  end

  # Response handling tests
  test "should handle successful responses correctly" do
    response_double = Struct.new(:status, :body).new(200, { 'data' => 'test' })
    
    result = @yodlee.send(:handle_response, response_double) do |data|
      data['data']
    end
    
    assert_equal 'test', result
  end

  test "should handle error responses correctly" do
    response_double = Struct.new(:status, :body).new(400, { 'errorCode' => 'Y013' })
    
    result = @yodlee.send(:handle_response, response_double) do |data|
      data['data']
    end
    
    assert_nil result
  end

  test "should handle responses without block" do
    response_double = Struct.new(:status, :body).new(200, { 'data' => 'test' })
    
    result = @yodlee.send(:handle_response, response_double)
    
    assert_equal({ 'data' => 'test' }, result)
  end

  private

  def capture_logs
    log_output = StringIO.new
    old_logger = Rails.logger
    Rails.logger = Logger.new(log_output)
    
    yield
    
    log_output.string
  ensure
    Rails.logger = old_logger
  end
end