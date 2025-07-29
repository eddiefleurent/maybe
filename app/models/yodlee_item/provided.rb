module YodleeItem::Provided
  extend ActiveSupport::Concern

  # Returns the Yodlee provider instance from the registry
  def yodlee_provider
    @yodlee_provider ||= Provider::Registry.get_provider(:yodlee)
  end
end
