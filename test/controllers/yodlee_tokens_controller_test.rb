require "test_helper"

class YodleeTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  # Happy Path Tests
  
  test "should create tokens successfully when family can connect to yodlee" do
    # Mock successful token response
    mock_token_response = OpenStruct.new(
      cobrand_token: "test_cobrand_token_123",
      user_token: "test_user_token_456", 
      fastlink_url: "https://test.yodlee.com/fastlink"
    )
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        post yodlee_tokens_url
        
        assert_response :success
        json_response = JSON.parse(response.body)
        assert_equal "test_cobrand_token_123", json_response["cobrand_token"]
        assert_equal "test_user_token_456", json_response["user_token"]
        assert_equal "https://test.yodlee.com/fastlink", json_response["fastlink"]
      end
    end
  end

  test "should pass correct parameters to get_yodlee_token" do
    mock_token_response = OpenStruct.new(
      cobrand_token: "token", 
      user_token: "token", 
      fastlink_url: "url"
    )
    
    expected_webhooks_url = nil
    expected_redirect_url = nil
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.define_singleton_method(:get_yodlee_token) do |webhooks_url:, redirect_url:|
        expected_webhooks_url = webhooks_url
        expected_redirect_url = redirect_url
        mock_token_response
      end
      
      post yodlee_tokens_url
      
      assert_response :success
      assert_equal accounts_url, expected_redirect_url
      assert_includes expected_webhooks_url, "/webhooks/yodlee"
    end
  end

  # Error Handling Tests

  test "should return service unavailable when family cannot connect to yodlee" do
    Current.family.stub(:can_connect_yodlee?, false) do
      post yodlee_tokens_url
      
      assert_response :service_unavailable
      json_response = JSON.parse(response.body)
      assert_equal "Yodlee integration is not configured", json_response["error"]
    end
  end

  test "should return internal server error when get_yodlee_token returns nil" do
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, nil) do
        post yodlee_tokens_url
        
        assert_response :internal_server_error
        json_response = JSON.parse(response.body)
        assert_equal "Failed to obtain Yodlee tokens", json_response["error"]
      end
    end
  end

  test "should handle exceptions from get_yodlee_token gracefully" do
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, -> { raise StandardError.new("API Error") }) do
        Rails.logger.stub(:error, nil) do
          post yodlee_tokens_url
          
          assert_response :internal_server_error
          json_response = JSON.parse(response.body)
          assert_equal "An error occurred while obtaining Yodlee tokens", json_response["error"]
        end
      end
    end
  end

  test "should log errors when exceptions occur" do
    error_message = "Test API Error"
    logged_messages = []
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, -> { raise StandardError.new(error_message) }) do
        Rails.logger.stub(:error, ->(msg) { logged_messages << msg }) do
          post yodlee_tokens_url
          
          assert_includes logged_messages.join, "Yodlee token error: #{error_message}"
        end
      end
    end
  end

  test "should capture exceptions with Sentry when available" do
    captured_exceptions = []
    
    # Mock Sentry being defined
    Object.const_set(:Sentry, Module.new) unless defined?(Sentry)
    Sentry.define_singleton_method(:capture_exception) { |e| captured_exceptions << e }
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, -> { raise StandardError.new("Test Error") }) do
        Rails.logger.stub(:error, nil) do
          post yodlee_tokens_url
          
          assert_equal 1, captured_exceptions.length
          assert_equal "Test Error", captured_exceptions.first.message
        end
      end
    end
  end

  # Authentication Tests

  test "should require user authentication" do
    sign_out @user
    
    post yodlee_tokens_url
    
    # Should redirect to login or return unauthorized
    assert_response :redirect
  end

  test "should work with authenticated user" do
    mock_token_response = OpenStruct.new(
      cobrand_token: "token", 
      user_token: "token", 
      fastlink_url: "url"
    )
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        post yodlee_tokens_url
        
        assert_response :success
      end
    end
  end

  # Environment-specific Webhook URL Tests

  test "should use production webhook URL in production environment" do
    original_env = Rails.env
    Rails.env = "production"
    
    expected_webhooks_url = nil
    mock_token_response = OpenStruct.new(cobrand_token: "t", user_token: "t", fastlink_url: "u")
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.define_singleton_method(:get_yodlee_token) do |webhooks_url:, redirect_url:|
        expected_webhooks_url = webhooks_url
        mock_token_response
      end
      
      post yodlee_tokens_url
      
      assert_equal webhooks_yodlee_url, expected_webhooks_url
    end
  ensure
    Rails.env = original_env
  end

  test "should use development webhook URL with ENV variable in non-production" do
    original_env_var = ENV["DEV_WEBHOOKS_URL"]
    ENV["DEV_WEBHOOKS_URL"] = "https://dev.example.com"
    
    expected_webhooks_url = nil
    mock_token_response = OpenStruct.new(cobrand_token: "t", user_token: "t", fastlink_url: "u")
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.define_singleton_method(:get_yodlee_token) do |webhooks_url:, redirect_url:|
        expected_webhooks_url = webhooks_url
        mock_token_response
      end
      
      post yodlee_tokens_url
      
      assert_equal "https://dev.example.com/webhooks/yodlee", expected_webhooks_url
    end
  ensure
    ENV["DEV_WEBHOOKS_URL"] = original_env_var
  end

  test "should fallback to root_url for webhook URL when ENV variable not set" do
    original_env_var = ENV["DEV_WEBHOOKS_URL"]
    ENV.delete("DEV_WEBHOOKS_URL")
    
    expected_webhooks_url = nil
    mock_token_response = OpenStruct.new(cobrand_token: "t", user_token: "t", fastlink_url: "u")
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.define_singleton_method(:get_yodlee_token) do |webhooks_url:, redirect_url:|
        expected_webhooks_url = webhooks_url
        mock_token_response
      end
      
      post yodlee_tokens_url
      
      expected_url = root_url.chomp("/") + "/webhooks/yodlee"
      assert_equal expected_url, expected_webhooks_url
    end
  ensure
    ENV["DEV_WEBHOOKS_URL"] = original_env_var if original_env_var
  end

  # HTTP Method Tests

  test "should only accept POST requests" do
    mock_token_response = OpenStruct.new(cobrand_token: "t", user_token: "t", fastlink_url: "u")
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        # GET should not be allowed
        assert_raises(ActionController::RoutingError) do
          get yodlee_tokens_url
        end
        
        # PUT should not be allowed
        assert_raises(ActionController::RoutingError) do
          put yodlee_tokens_url
        end
        
        # DELETE should not be allowed
        assert_raises(ActionController::RoutingError) do
          delete yodlee_tokens_url
        end
        
        # PATCH should not be allowed
        assert_raises(ActionController::RoutingError) do
          patch yodlee_tokens_url
        end
      end
    end
  end

  # JSON Response Format Tests

  test "should return valid JSON response structure" do
    mock_token_response = OpenStruct.new(
      cobrand_token: "cb_token_123",
      user_token: "user_token_456", 
      fastlink_url: "https://fastlink.example.com"
    )
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        post yodlee_tokens_url
        
        assert_response :success
        assert_equal "application/json; charset=utf-8", response.content_type
        
        json_response = JSON.parse(response.body)
        assert_equal 3, json_response.keys.length
        assert json_response.key?("cobrand_token")
        assert json_response.key?("user_token")
        assert json_response.key?("fastlink")
      end
    end
  end

  test "should handle empty token values" do
    mock_token_response = OpenStruct.new(
      cobrand_token: "",
      user_token: "", 
      fastlink_url: ""
    )
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        post yodlee_tokens_url
        
        assert_response :success
        json_response = JSON.parse(response.body)
        assert_equal "", json_response["cobrand_token"]
        assert_equal "", json_response["user_token"]
        assert_equal "", json_response["fastlink"]
      end
    end
  end

  test "should handle nil token values" do
    mock_token_response = OpenStruct.new(
      cobrand_token: nil,
      user_token: nil, 
      fastlink_url: nil
    )
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        post yodlee_tokens_url
        
        assert_response :success
        json_response = JSON.parse(response.body)
        assert_nil json_response["cobrand_token"]
        assert_nil json_response["user_token"]
        assert_nil json_response["fastlink"]
      end
    end
  end

  # Edge Cases and Integration Tests

  test "should handle very long token values" do
    long_token = "a" * 10000
    mock_token_response = OpenStruct.new(
      cobrand_token: long_token,
      user_token: long_token, 
      fastlink_url: "https://example.com/" + long_token
    )
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        post yodlee_tokens_url
        
        assert_response :success
        json_response = JSON.parse(response.body)
        assert_equal long_token, json_response["cobrand_token"]
        assert_equal long_token, json_response["user_token"]
      end
    end
  end

  test "should handle special characters in token values" do
    special_token = "token_with_special_chars_!@#$%^&*()_+-={}[]|\\:;\"'<>?,./"
    mock_token_response = OpenStruct.new(
      cobrand_token: special_token,
      user_token: special_token, 
      fastlink_url: "https://example.com/path"
    )
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        post yodlee_tokens_url
        
        assert_response :success
        json_response = JSON.parse(response.body)
        assert_equal special_token, json_response["cobrand_token"]
        assert_equal special_token, json_response["user_token"]
      end
    end
  end

  test "should handle concurrent requests safely" do
    mock_token_response = OpenStruct.new(
      cobrand_token: "concurrent_token",
      user_token: "concurrent_user_token", 
      fastlink_url: "https://concurrent.example.com"
    )
    
    responses = []
    threads = []
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        3.times do
          threads << Thread.new do
            post yodlee_tokens_url
            responses << response.status
          end
        end
        
        threads.each(&:join)
        
        # All requests should succeed
        assert_equal [200, 200, 200], responses
      end
    end
  end

  test "should handle timeout scenarios" do
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, -> { raise Timeout::Error.new("Request timeout") }) do
        Rails.logger.stub(:error, nil) do
          post yodlee_tokens_url
          
          assert_response :internal_server_error
          json_response = JSON.parse(response.body)
          assert_equal "An error occurred while obtaining Yodlee tokens", json_response["error"]
        end
      end
    end
  end

  # Parameter and Header Tests

  test "should handle requests with extra parameters gracefully" do
    mock_token_response = OpenStruct.new(
      cobrand_token: "token",
      user_token: "token", 
      fastlink_url: "url"
    )
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        post yodlee_tokens_url, params: { 
          extra_param: "should_be_ignored",
          another_param: { nested: "value" }
        }
        
        assert_response :success
      end
    end
  end

  test "should handle different content types" do
    mock_token_response = OpenStruct.new(
      cobrand_token: "token",
      user_token: "token", 
      fastlink_url: "url"
    )
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        post yodlee_tokens_url, headers: { "Content-Type" => "application/json" }
        assert_response :success
        
        post yodlee_tokens_url, headers: { "Content-Type" => "text/plain" }
        assert_response :success
      end
    end
  end

  test "should maintain session state during request" do
    mock_token_response = OpenStruct.new(
      cobrand_token: "session_token",
      user_token: "session_user_token", 
      fastlink_url: "https://session.example.com"
    )
    
    # Set some session data
    post yodlee_tokens_url, params: {}, session: { test_data: "session_value" }
    
    Current.family.stub(:can_connect_yodlee?, true) do
      Current.family.stub(:get_yodlee_token, mock_token_response) do
        post yodlee_tokens_url
        
        assert_response :success
        # Session should still be accessible if needed
        assert_equal "session_value", session[:test_data]
      end
    end
  end
end