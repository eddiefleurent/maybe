class YodleeTokensController < ApplicationController
  before_action :authenticate_user!
  
  def create
    unless Current.family.can_connect_yodlee?
      render json: { error: "Yodlee integration is not configured" }, status: :service_unavailable
      return
    end
    
    token_response = Current.family.get_yodlee_token(
      webhooks_url: yodlee_webhooks_url,
      redirect_url: accounts_url
    )
    
    if token_response
      render json: { 
        cobrand_token: token_response.cobrand_token,
        user_token: token_response.user_token,
        fastlink: token_response.fastlink_url
      }
    else
      render json: { error: "Failed to obtain Yodlee tokens" }, status: :internal_server_error
    end
  rescue StandardError => e
    Rails.logger.error("Yodlee token error: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    render json: { error: "An error occurred while obtaining Yodlee tokens" }, status: :internal_server_error
  end
  
  private
    def yodlee_webhooks_url
      return webhooks_yodlee_url if Rails.env.production?
      
      ENV.fetch("DEV_WEBHOOKS_URL", root_url.chomp("/")) + "/webhooks/yodlee"
    end
end
