class YodleeItem < ApplicationRecord
  # Use the namespaced `YodleeItem::Provided` concern for provider helpers
  include Syncable, YodleeItem::Provided

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  if Rails.application.credentials.active_record_encryption.present?
    encrypts :user_session, deterministic: true
  end

  validates :name, :user_session, presence: true

  before_destroy :remove_yodlee_item

  belongs_to :family
  has_one_attached :logo

  has_many :yodlee_accounts, dependent: :destroy
  has_many :accounts, through: :yodlee_accounts

  scope :active, -> { where(scheduled_for_deletion: false) }
  scope :ordered, -> { order(created_at: :desc) }
  scope :needs_update, -> { where(status: :requires_update) }

  def get_update_link_token(webhooks_url:, redirect_url:)
    cobrand_token = yodlee_provider.auth_cobrand
    return nil unless cobrand_token && user_session

    token_response = yodlee_provider.get_fastlink_token(user_session, cobrand_token)
    token_response
  rescue StandardError => e
    # Mark the connection as invalid but don't auto-delete
    update!(status: :requires_update)

    Sentry.capture_exception(e) if defined?(Sentry)
    nil
  end

  def destroy_later
    update!(scheduled_for_deletion: true)
    DestroyJob.perform_later(self)
  end

  def import_latest_yodlee_data
    YodleeItem::Importer.new(self, yodlee_provider: yodlee_provider).import
  end

  # Reads the fetched data and updates internal domain objects
  # Generally, this should only be called within a "sync", but can be called
  # manually to "re-sync" the already fetched data
  def process_accounts
    yodlee_accounts.each do |yodlee_account|
      YodleeAccount::Processor.new(yodlee_account).process
    end
  end

  # Once all the data is fetched, we can schedule account syncs to calculate historical balances
  def schedule_account_syncs(parent_sync: nil, window_start_date: nil, window_end_date: nil)
    accounts.each do |account|
      account.sync_later(
        parent_sync: parent_sync,
        window_start_date: window_start_date,
        window_end_date: window_end_date
      )
    end
  end

  # Saves the raw data fetched from Yodlee API for this item
  def upsert_yodlee_snapshot!(item_snapshot)
    assign_attributes(
      available_products: item_snapshot['CONTAINER'] || [],
      raw_payload: item_snapshot,
    )

    save!
  end

  # Saves the raw data fetched from Yodlee API for this item's institution
  def upsert_yodlee_institution_snapshot!(institution_snapshot)
    assign_attributes(
      institution_id: institution_snapshot['id'],
      institution_url: institution_snapshot['url'],
      institution_color: institution_snapshot['primaryColor'],
      raw_institution_payload: institution_snapshot
    )

    save!
  end

  def supports_product?(product)
    supported_products.include?(product)
  end

  private
    def remove_yodlee_item
      # Yodlee doesn't have a direct "remove item" API call
      # Instead, we just delete our local record
      true
    rescue StandardError => e
      Sentry.capture_exception(e) if defined?(Sentry)
      # Continue with deletion regardless of API errors
      true
    end

    def supported_products
      available_products || []
    end
end
