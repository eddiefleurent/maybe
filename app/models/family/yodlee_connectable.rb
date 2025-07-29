module Family::YodleeConnectable
  extend ActiveSupport::Concern

  included do
    has_many :yodlee_items, dependent: :destroy
  end

  def can_connect_yodlee?
    yodlee_provider.present? && Rails.application.config.enable_yodlee
  end

  def create_yodlee_item!(user_session:, item_name:, metadata: {})
    yodlee_item = yodlee_items.create!(
      name: item_name,
      user_session: user_session,
      raw_payload: metadata
    )

    yodlee_item.sync_later

    yodlee_item
  end

  def get_yodlee_token(webhooks_url:, redirect_url:)
    return nil unless can_connect_yodlee?

    # First, we need to create a user in Yodlee if one doesn't exist
    # This is typically done after the user authenticates with Maybe
    # but before they see the FastLink widget
    user_session = find_or_create_yodlee_user

    # If we couldn't create a user, return nil
    return nil unless user_session

    # Get tokens for FastLink initialization
    token_response = yodlee_provider.get_fastlink_token(user_session)
    
    # Return the token response which includes cobrand_token, user_token, and fastlink_url
    token_response
  rescue StandardError => e
    Rails.logger.error("Failed to get Yodlee token: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    nil
  end

  private
    def yodlee_provider
      Provider::Registry.get_provider(:yodlee)
    end

    def find_or_create_yodlee_user
      # Check if any existing yodlee_items have a valid user_session
      existing_item = yodlee_items.active.first
      return existing_item.user_session if existing_item.present?

      # Create a new Yodlee user for this family
      # We use the primary user of the family
      primary_user = users.find_by(role: :admin) || users.first
      return nil unless primary_user.present?

      yodlee_provider.create_user(primary_user)
    end
end
