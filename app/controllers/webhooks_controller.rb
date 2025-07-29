class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_authentication

  def plaid
    webhook_body = request.body.read
    plaid_verification_header = request.headers["Plaid-Verification"]

    client = Provider::Registry.plaid_provider_for_region(:us)

    client.validate_webhook!(plaid_verification_header, webhook_body)

    PlaidItem::WebhookProcessor.new(webhook_body).process

    render json: { received: true }, status: :ok
  rescue => error
    Sentry.capture_exception(error)
    render json: { error: "Invalid webhook: #{error.message}" }, status: :bad_request
  end

  def plaid_eu
    webhook_body = request.body.read
    plaid_verification_header = request.headers["Plaid-Verification"]

    client = Provider::Registry.plaid_provider_for_region(:eu)

    client.validate_webhook!(plaid_verification_header, webhook_body)

    PlaidItem::WebhookProcessor.new(webhook_body).process

    render json: { received: true }, status: :ok
  rescue => error
    Sentry.capture_exception(error)
    render json: { error: "Invalid webhook: #{error.message}" }, status: :bad_request
  end

  def stripe
    stripe_provider = Provider::Registry.get_provider(:stripe)

    begin
      webhook_body = request.body.read
      sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

      stripe_provider.process_webhook_later(webhook_body, sig_header)

      head :ok
    rescue JSON::ParserError => error
      Sentry.capture_exception(error)
      Rails.logger.error "JSON parser error: #{error.message}"
      head :bad_request
    rescue Stripe::SignatureVerificationError => error
      Sentry.capture_exception(error)
      Rails.logger.error "Stripe signature verification error: #{error.message}"
      head :bad_request
    end
  end

  # Yodlee webhooks – called from POST /webhooks/yodlee
  # Docs: https://developer.yodlee.com/docs/api/webhooks/
  #
  # At the moment Yodlee does not provide a public signature verification
  # mechanism similar to Plaid.  We therefore treat these webhooks as
  # unauthenticated → they *must* be scoped to private/tunnel endpoints
  # that only Yodlee can reach.
  #
  # The payload looks like:
  # {
  #   "event": {
  #     "name": "DATA_UPDATES",
  #     "data": {
  #       "providerAccountId": 123456,
  #       ...
  #     }
  #   }
  # }
  def yodlee
    webhook_body = request.body.read

    # Parse JSON; if parsing fails we'll still acknowledge to avoid retries
    payload = JSON.parse(webhook_body) rescue {}

    provider_account_ids = Array.wrap(payload.dig("event", "data", "providerAccountId"))

    if provider_account_ids.any?
      YodleeItem.active.where(yodlee_id: provider_account_ids.map(&:to_s)).find_each do |item|
        item.sync_later unless item.syncing?
      end
    else
      # Fallback: schedule a sync for every active Yodlee item (safer than doing nothing)
      YodleeItem.active.find_each { |item| item.sync_later unless item.syncing? }
    end

    render json: { received: true }, status: :ok
  rescue JSON::ParserError => error
    Rails.logger.error "Yodlee webhook JSON parse error: #{error.message}"
    Sentry.capture_exception(error) if defined?(Sentry)
    render json: { error: "Invalid JSON" }, status: :bad_request
  rescue => error
    Sentry.capture_exception(error) if defined?(Sentry)
    render json: { error: "Error processing webhook: #{error.message}" }, status: :bad_request
  end
end
