class YodleeItemsController < ApplicationController
  before_action :set_yodlee_item, only: %i[edit destroy sync]

  def new
    @token_response = Current.family.get_yodlee_token(
      webhooks_url: yodlee_webhooks_url,
      redirect_url: accounts_url
    )

    unless @token_response
      redirect_to accounts_path, alert: t(".error")
      return
    end
  end

  def edit
    @token_response = @yodlee_item.get_update_link_token(
      webhooks_url: yodlee_webhooks_url,
      redirect_url: accounts_url,
    )

    unless @token_response
      redirect_to accounts_path, alert: t(".error")
      return
    end
  end

  def create
    # Process the FastLink callback data
    Current.family.create_yodlee_item!(
      user_session: yodlee_item_params[:user_session],
      item_name: item_name,
      metadata: yodlee_item_params[:metadata]
    )

    redirect_to accounts_path, notice: t(".success")
  rescue StandardError => e
    Rails.logger.error("Failed to create Yodlee item: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    redirect_to accounts_path, alert: t(".error")
  end

  def destroy
    @yodlee_item.destroy_later
    redirect_to accounts_path, notice: t(".success")
  end

  def sync
    unless @yodlee_item.syncing?
      @yodlee_item.sync_later
    end

    respond_to do |format|
      format.html { redirect_back_or_to accounts_path }
      format.json { head :ok }
    end
  end

  private
    def set_yodlee_item
      @yodlee_item = Current.family.yodlee_items.find(params[:id])
    end

    def yodlee_item_params
      params.require(:yodlee_item).permit(:user_session, metadata: {})
    end

    def item_name
      yodlee_item_params.dig(:metadata, :institution, :name) || 
        yodlee_item_params.dig(:metadata, :providerName) || 
        "Financial Institution"
    end

    def yodlee_webhooks_url
      return webhooks_yodlee_url if Rails.env.production?

      ENV.fetch("DEV_WEBHOOKS_URL", root_url.chomp("/")) + "/webhooks/yodlee"
    end
end
