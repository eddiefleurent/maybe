Rails.application.configure do
  # Initialize Yodlee configuration as nil by default
  config.yodlee = nil

  # Check if required Yodlee environment variables are present
  if ENV["YODLEE_CLIENT_ID"].present? && ENV["YODLEE_SECRET"].present?
    # Create a hash of Yodlee configuration values
    config.yodlee = {
      client_id: ENV["YODLEE_CLIENT_ID"],
      secret: ENV["YODLEE_SECRET"],
      base_url: ENV["YODLEE_BASE"] || "https://sandbox.api.yodlee.com/ysl",
      fastlink_url: ENV["YODLEE_FASTLINK_URL"] || "https://fl4.sandbox.yodlee.com/authenticate/restserver/fastlink"
    }

    # Enable Yodlee integration if explicitly set
    config.enable_yodlee = ENV["ENABLE_YODLEE"] == "true"

    Rails.logger.info "Yodlee integration configured with client ID: #{ENV["YODLEE_CLIENT_ID"]}"
  else
    config.enable_yodlee = false
    Rails.logger.info "Yodlee integration not configured. Missing required environment variables."
  end
end
