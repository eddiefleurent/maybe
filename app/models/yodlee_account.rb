class YodleeAccount < ApplicationRecord
  include Provided

  belongs_to :yodlee_item
  belongs_to :account, optional: true

  validates :yodlee_id, presence: true, uniqueness: { scope: :yodlee_item_id }

  scope :active, -> { joins(:yodlee_item).where(yodlee_items: { scheduled_for_deletion: false }) }
  scope :ordered, -> { order(created_at: :desc) }
  scope :unlinked, -> { where(account_id: nil) }
  scope :linked, -> { where.not(account_id: nil) }

  def name
    raw_payload['accountName']
  end

  def mask
    raw_payload['accountNumber']&.last(4)
  end

  def institution_name
    raw_payload['providerName']
  end

  def balance
    raw_payload.dig('balance', 'amount')
  end

  def currency
    raw_payload.dig('currency')
  end

  def account_type
    map_account_type
  end

  def account_subtype
    raw_payload['accountType']
  end

  def create_or_update_account!
    return account if account.present?

    # Create a new account based on the Yodlee account type
    new_account = build_account_from_yodlee_data
    
    if new_account.save
      update!(account: new_account)
      new_account
    else
      Rails.logger.error("Failed to create account from Yodlee account #{id}: #{new_account.errors.full_messages.join(', ')}")
      nil
    end
  end

  def sync_transactions(from_date:, to_date:)
    # Ensure a provider is available – self-hosting instances might disable it.
    return [] unless provider

    transactions = provider.get_transactions(
      yodlee_item.user_session,
      from: from_date,
      to:   to_date
    ) || []

    # Keep only the transactions that belong to this specific Yodlee account
    account_transactions = transactions.select { |tx| tx['accountId'].to_s == yodlee_id.to_s }

    # Process & persist each transaction, compacting nil/failed ones
    account_transactions.map do |tx|
      YodleeAccount::TransactionProcessor.new(self, tx).process
    end.compact
  end

  private
    # Lazily resolve the Yodlee provider.  Falls back to the mix-in’s method
    # (if provided) otherwise fetches directly from the registry.
    def provider
      @provider ||= (respond_to?(:yodlee_provider) ? yodlee_provider : Provider::Registry.get_provider(:yodlee))
    end

    # Maps Yodlee account types to Maybe account types
    def map_account_type
      container = raw_payload['CONTAINER']
      
      case container
      when 'bank'
        if ['CHECKING', 'SAVINGS'].include?(account_subtype)
          'Depository'
        else
          'OtherAsset'
        end
      when 'creditCard'
        'CreditCard'
      when 'investment'
        'Investment'
      when 'insurance'
        'OtherAsset'
      when 'loan'
        if account_subtype == 'MORTGAGE'
          'Loan'
        else
          'Loan'
        end
      when 'realEstate'
        'Property'
      when 'otherAssets'
        'OtherAsset'
      when 'otherLiabilities'
        'OtherLiability'
      else
        'OtherAsset'
      end
    end

    def build_account_from_yodlee_data
      accountable_type = account_type
      
      # Create the accountable record based on the type
      accountable = accountable_type.constantize.new(
        name: name,
        institution_name: institution_name,
        notes: "Imported from Yodlee"
      )

      # Set specific attributes based on account type
      case accountable_type
      when 'Depository'
        accountable.account_type = account_subtype == 'CHECKING' ? 'checking' : 'savings'
      when 'CreditCard'
        accountable.account_type = 'credit_card'
        accountable.limit_cents = raw_payload.dig('availableCredit', 'amount')&.to_i
      when 'Investment'
        accountable.account_type = 'brokerage'
      when 'Loan'
        accountable.account_type = account_subtype == 'MORTGAGE' ? 'mortgage' : 'personal_loan'
        accountable.interest_rate = raw_payload.dig('interestRate')&.to_f
      when 'Property'
        accountable.property_type = 'residential'
      end

      # Create the account with the accountable
      Account.new(
        family: yodlee_item.family,
        name: name,
        mask: mask,
        institution_name: institution_name,
        accountable: accountable,
        external_id: yodlee_id,
        provider: 'yodlee',
        currency: currency || yodlee_item.family.currency,
        balance_cents: balance&.to_i,
        last_synced_at: Time.current
      )
    end
end
