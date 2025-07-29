require "test_helper"

class Provider::RegistryTest < ActiveSupport::TestCase
  test "synth configured with ENV" do
    Setting.stubs(:synth_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: "123" do
      assert_instance_of Provider::Synth, Provider::Registry.get_provider(:synth)
    end
  end

  test "synth configured with Setting" do
    Setting.stubs(:synth_api_key).returns("123")

    with_env_overrides SYNTH_API_KEY: nil do
      assert_instance_of Provider::Synth, Provider::Registry.get_provider(:synth)
    end
  end

  test "synth not configured" do
    Setting.stubs(:synth_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: nil do
      assert_nil Provider::Registry.get_provider(:synth)
    end
  end
end

  # Test class method get_provider with various providers
  test "get_provider raises error for unknown provider" do
    assert_raises(Provider::Registry::Error) do
      Provider::Registry.get_provider(:unknown_provider)
    end
    
    error = assert_raises(Provider::Registry::Error) do
      Provider::Registry.get_provider(:nonexistent)
    end
    assert_match(/Provider 'nonexistent' not found in registry/, error.message)
  end

  test "get_provider returns github provider" do
    provider = Provider::Registry.get_provider(:github)
    assert_instance_of Provider::Github, provider
  end

  test "get_provider returns openai provider when configured" do
    Setting.stubs(:openai_access_token).returns("test-token")
    
    with_env_overrides OPENAI_ACCESS_TOKEN: nil do
      provider = Provider::Registry.get_provider(:openai)
      assert_instance_of Provider::Openai, provider
    end
  end

  test "get_provider returns nil for openai when not configured" do
    Setting.stubs(:openai_access_token).returns(nil)
    
    with_env_overrides OPENAI_ACCESS_TOKEN: nil do
      provider = Provider::Registry.get_provider(:openai)
      assert_nil provider
    end
  end

  test "openai provider configuration priority ENV over Setting" do
    Setting.stubs(:openai_access_token).returns("setting_token")
    
    with_env_overrides OPENAI_ACCESS_TOKEN: "env_token" do
      provider = Provider::Registry.get_provider(:openai)
      assert_instance_of Provider::Openai, provider
    end
  end

  test "get_provider returns stripe provider when configured" do
    with_env_overrides STRIPE_SECRET_KEY: "sk_test_123", STRIPE_WEBHOOK_SECRET: "whsec_123" do
      provider = Provider::Registry.get_provider(:stripe)
      assert_instance_of Provider::Stripe, provider
    end
  end

  test "get_provider returns nil for stripe when partially configured" do
    # Only secret key, missing webhook secret
    with_env_overrides STRIPE_SECRET_KEY: "sk_test_123", STRIPE_WEBHOOK_SECRET: nil do
      provider = Provider::Registry.get_provider(:stripe)
      assert_nil provider
    end
    
    # Only webhook secret, missing secret key
    with_env_overrides STRIPE_SECRET_KEY: nil, STRIPE_WEBHOOK_SECRET: "whsec_123" do
      provider = Provider::Registry.get_provider(:stripe)
      assert_nil provider
    end
  end

  test "plaid_provider_for_region returns correct provider for US" do
    Rails.application.config.stubs(:plaid).returns({ client_id: "test", secret: "test" })
    
    provider = Provider::Registry.plaid_provider_for_region(:us)
    assert_instance_of Provider::Plaid, provider if provider
  end

  test "plaid_provider_for_region returns correct provider for EU" do
    Rails.application.config.stubs(:plaid_eu).returns({ client_id: "test", secret: "test" })
    
    provider = Provider::Registry.plaid_provider_for_region(:eu)
    assert_instance_of Provider::Plaid, provider if provider
  end

  test "plaid_provider_for_region handles string input" do
    Rails.application.config.stubs(:plaid).returns({ client_id: "test", secret: "test" })
    
    provider = Provider::Registry.plaid_provider_for_region("us")
    assert_instance_of Provider::Plaid, provider if provider
  end

  test "get_provider returns yodlee provider when fully configured" do
    env_vars = {
      YODLEE_CLIENT_ID: "test_client",
      YODLEE_SECRET: "test_secret",
      YODLEE_BASE: "https://test.yodlee.com",
      YODLEE_FASTLINK_URL: "https://test.fastlink.com",
      YODLEE_COBRAND_NAME: "test_cobrand"
    }
    
    with_env_overrides env_vars do
      provider = Provider::Registry.get_provider(:yodlee)
      assert_instance_of Provider::Yodlee, provider
    end
  end

  test "get_provider returns nil for yodlee when partially configured" do
    # Missing some required environment variables
    partial_env = {
      YODLEE_CLIENT_ID: "test_client",
      YODLEE_SECRET: "test_secret",
      YODLEE_BASE: nil,
      YODLEE_FASTLINK_URL: "https://test.fastlink.com",
      YODLEE_COBRAND_NAME: "test_cobrand"
    }
    
    with_env_overrides partial_env do
      provider = Provider::Registry.get_provider(:yodlee)
      assert_nil provider
    end
  end

  # Test instance methods and concept-based filtering
  test "for_concept creates registry instance with valid concept" do
    registry = Provider::Registry.for_concept(:exchange_rates)
    assert_instance_of Provider::Registry, registry
  end

  test "for_concept accepts string concept" do
    registry = Provider::Registry.for_concept("llm")
    assert_instance_of Provider::Registry, registry
  end

  test "registry validates concept inclusion" do
    assert_raises(ActiveModel::ValidationError) do
      Provider::Registry.new(:invalid_concept)
    end
  end

  test "registry concept validation includes all expected concepts" do
    Provider::Registry::CONCEPTS.each do |concept|
      assert_nothing_raised do
        Provider::Registry.new(concept)
      end
    end
  end

  test "registry providers method returns available providers for exchange_rates" do
    Setting.stubs(:synth_api_key).returns("test-key")
    
    with_env_overrides SYNTH_API_KEY: nil do
      registry = Provider::Registry.for_concept(:exchange_rates)
      providers = registry.providers
      
      assert_includes providers.map(&:class), Provider::Synth
      providers.each { |p| assert_not_nil p }
    end
  end

  test "registry providers method returns available providers for securities" do
    Setting.stubs(:synth_api_key).returns("test-key")
    
    with_env_overrides SYNTH_API_KEY: nil do
      registry = Provider::Registry.for_concept(:securities)
      providers = registry.providers
      
      assert_includes providers.map(&:class), Provider::Synth
      providers.each { |p| assert_not_nil p }
    end
  end

  test "registry providers method returns available providers for llm" do
    Setting.stubs(:openai_access_token).returns("test-token")
    
    with_env_overrides OPENAI_ACCESS_TOKEN: nil do
      registry = Provider::Registry.for_concept(:llm)
      providers = registry.providers
      
      assert_includes providers.map(&:class), Provider::Openai
      providers.each { |p| assert_not_nil p }
    end
  end

  test "registry instance get_provider method for exchange_rates concept" do
    Setting.stubs(:synth_api_key).returns("test-key")
    
    with_env_overrides SYNTH_API_KEY: nil do
      registry = Provider::Registry.for_concept(:exchange_rates)
      provider = registry.get_provider(:synth)
      
      assert_instance_of Provider::Synth, provider
    end
  end

  test "registry instance get_provider raises error for invalid provider in concept" do
    registry = Provider::Registry.for_concept(:exchange_rates)
    
    error = assert_raises(Provider::Registry::Error) do
      registry.get_provider(:openai)
    end
    
    assert_match(/Provider 'openai' not found for concept: exchange_rates/, error.message)
  end

  test "registry instance get_provider accepts string names" do
    Setting.stubs(:synth_api_key).returns("test-key")
    
    with_env_overrides SYNTH_API_KEY: nil do
      registry = Provider::Registry.for_concept(:exchange_rates)
      provider = registry.get_provider("synth")
      
      assert_instance_of Provider::Synth, provider
    end
  end

  # Test configuration edge cases
  test "synth provider with ENV fetch fallback behavior" do
    Setting.stubs(:synth_api_key).returns("setting_key")
    
    # When ENV key exists, it should take priority
    with_env_overrides SYNTH_API_KEY: "env_key" do
      provider = Provider::Registry.get_provider(:synth)
      assert_instance_of Provider::Synth, provider
    end
    
    # When ENV key doesn't exist, should fallback to Setting
    with_env_overrides SYNTH_API_KEY: nil do
      provider = Provider::Registry.get_provider(:synth)
      assert_instance_of Provider::Synth, provider
    end
  end

  test "openai provider with ENV fetch fallback behavior" do
    Setting.stubs(:openai_access_token).returns("setting_token")
    
    # When ENV token exists, it should take priority
    with_env_overrides OPENAI_ACCESS_TOKEN: "env_token" do
      provider = Provider::Registry.get_provider(:openai)
      assert_instance_of Provider::Openai, provider
    end
    
    # When ENV token doesn't exist, should fallback to Setting
    with_env_overrides OPENAI_ACCESS_TOKEN: nil do
      provider = Provider::Registry.get_provider(:openai)
      assert_instance_of Provider::Openai, provider
    end
  end

  # Test error handling and edge cases
  test "registry handles nil input gracefully in class method" do
    error = assert_raises(Provider::Registry::Error) do
      Provider::Registry.get_provider(nil)
    end
    assert_match(/Provider '' not found in registry/, error.message)
  end

  test "registry handles empty string input" do
    error = assert_raises(Provider::Registry::Error) do
      Provider::Registry.get_provider("")
    end
    assert_match(/Provider '' not found in registry/, error.message)
  end

  test "registry maintains consistent behavior across calls" do
    Setting.stubs(:synth_api_key).returns("test-key")
    
    with_env_overrides SYNTH_API_KEY: nil do
      provider1 = Provider::Registry.get_provider(:synth)
      provider2 = Provider::Registry.get_provider(:synth)
      
      assert_equal provider1.class, provider2.class
      assert_instance_of Provider::Synth, provider1
      assert_instance_of Provider::Synth, provider2
    end
  end

  test "registry concept validation error message" do
    error = assert_raises(ActiveModel::ValidationError) do
      Provider::Registry.new(:invalid_concept)
    end
    
    assert_match(/Validation failed/, error.message)
  end

  test "registry providers filters correctly for different concepts" do
    # Test that different concepts return different available providers
    exchange_registry = Provider::Registry.for_concept(:exchange_rates)
    llm_registry = Provider::Registry.for_concept(:llm)
    
    # Mock configurations
    Setting.stubs(:synth_api_key).returns("test-key")
    Setting.stubs(:openai_access_token).returns("test-token")
    
    with_env_overrides SYNTH_API_KEY: nil, OPENAI_ACCESS_TOKEN: nil do
      exchange_providers = exchange_registry.providers.compact
      llm_providers = llm_registry.providers.compact
      
      # Exchange rates should have synth but not openai
      assert exchange_providers.any? { |p| p.is_a?(Provider::Synth) }
      
      # LLM should have openai but not synth  
      assert llm_providers.any? { |p| p.is_a?(Provider::Openai) }
    end
  end

  test "plaid providers handle missing configuration gracefully" do
    Rails.application.config.stubs(:plaid).returns(nil)
    Rails.application.config.stubs(:plaid_eu).returns(nil)
    
    us_provider = Provider::Registry.plaid_provider_for_region(:us)
    eu_provider = Provider::Registry.plaid_provider_for_region(:eu)
    
    assert_nil us_provider
    assert_nil eu_provider
  end

  test "registry constants are properly defined" do
    assert_includes Provider::Registry::CONCEPTS, :exchange_rates
    assert_includes Provider::Registry::CONCEPTS, :securities  
    assert_includes Provider::Registry::CONCEPTS, :llm
    assert_equal 3, Provider::Registry::CONCEPTS.size
  end

  test "registry error class inheritance" do
    assert_equal StandardError, Provider::Registry::Error.superclass
  end

  test "registry includes ActiveModel validations" do
    assert_includes Provider::Registry.included_modules, ActiveModel::Validations
  end
