class YodleeAccount::Processor
  attr_reader :yodlee_account, :maybe_account

  def initialize(yodlee_account)
    @yodlee_account = yodlee_account
    @maybe_account = yodlee_account.account
  end

  def process
    Rails.logger.tagged("YodleeAccount::Processor", yodlee_account.id) do
      Rails.logger.info("Processing Yodlee account #{yodlee_account.yodlee_id}")

      # Create or update the Maybe account
      @maybe_account = create_or_update_account

      return unless @maybe_account.present?

      # Update account status and metadata
      update_account_metadata

      # Process account balance
      process_account_balance

      # Create initial valuation if needed
      create_initial_valuation if should_create_initial_valuation?

      Rails.logger.info("Completed processing Yodlee account #{yodlee_account.yodlee_id}")

      @maybe_account
    end
  rescue StandardError => e
    Rails.logger.error("Error processing Yodlee account #{yodlee_account.yodlee_id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    if defined?(Sentry)
      Sentry.capture_exception(e) do |scope|
        scope.set_context('yodlee_account', { 
          id: yodlee_account.id, 
          yodlee_id: yodlee_account.yodlee_id 
        })
      end
    end

    nil
  end

  private
    def create_or_update_account
      # If account already exists, return it
      return yodlee_account.account if yodlee_account.account.present?

      # Create a new account based on the Yodlee account type
      account = build_account_from_yodlee_data
      
      if account.save
        yodlee_account.update!(account: account)
        account
      else
        Rails.logger.error("Failed to create account from Yodlee account #{yodlee_account.id}: #{account.errors.full_messages.join(', ')}")
        nil
      end
    end

    def build_account_from_yodlee_data
      accountable_type = map_account_type
      
      # Create the accountable record based on the type
      accountable = accountable_type.constantize.new(
        name: yodlee_account.name,
        institution_name: yodlee_account.institution_name,
        notes: "Imported from Yodlee"
      )

      # Set specific attributes based on account type
      case accountable_type
      when 'Depository'
        accountable.account_type = yodlee_account.account_subtype.downcase.include?('checking') ? 'checking' : 'savings'
      when 'CreditCard'
        accountable.account_type = 'credit_card'
        accountable.limit_cents = yodlee_account.raw_payload.dig('availableCredit', 'amount')&.to_d&.*(100)&.to_i
      when 'Investment'
        accountable.account_type = 'brokerage'
      when 'Loan'
        accountable.account_type = yodlee_account.account_subtype.downcase.include?('mortgage') ? 'mortgage' : 'personal_loan'
        accountable.interest_rate = yodlee_account.raw_payload.dig('interestRate')&.to_f
      when 'Property'
        accountable.property_type = 'residential'
      end

      # Create the account with the accountable
      Account.new(
        family: yodlee_account.yodlee_item.family,
        name: yodlee_account.name,
        mask: yodlee_account.mask,
        institution_name: yodlee_account.institution_name,
        accountable: accountable,
        external_id: yodlee_account.yodlee_id,
        provider: 'yodlee',
        currency: yodlee_account.currency || yodlee_account.yodlee_item.family.currency,
        balance_cents: yodlee_account.balance&.to_d&.*(100)&.to_i,
        last_synced_at: Time.current
      )
    end

    def update_account_metadata
      return unless @maybe_account.present?

      @maybe_account.update!(
        mask: yodlee_account.mask,
        last_synced_at: Time.current,
        sync_error: nil,
        sync_error_at: nil
      )
    end

    def process_account_balance
      return unless @maybe_account.present? && yodlee_account.balance.present?

      # Convert balance to cents
      balance_cents = yodlee_account.balance.to_d * 100

      # Update the account balance
      @maybe_account.update!(balance_cents: balance_cents)

      # Create a balance record for today
      create_balance_record(balance_cents)
    end

    def create_balance_record(balance_cents)
      # Check if we already have a balance for today
      today = Date.current
      existing_balance = @maybe_account.balances.find_by(date: today)

      if existing_balance
        # Update existing balance
        existing_balance.update!(balance_cents: balance_cents)
      else
        # Create new balance
        @maybe_account.balances.create!(
          date: today,
          balance_cents: balance_cents,
          currency: @maybe_account.currency
        )
      end
    end

    def should_create_initial_valuation?
      # Only create initial valuations for certain account types
      return false unless ['Property', 'Vehicle', 'OtherAsset', 'Crypto'].include?(@maybe_account.accountable_type)
      
      # Only create if no valuations exist yet
      @maybe_account.valuations.none?
    end

    def create_initial_valuation
      # Create an initial valuation based on the current balance
      @maybe_account.valuations.create!(
        date: Date.current,
        amount_cents: @maybe_account.balance_cents,
        currency: @maybe_account.currency,
        notes: "Initial valuation from Yodlee import"
      )
    end

    def map_account_type
      container = yodlee_account.raw_payload['CONTAINER']
      subtype = yodlee_account.raw_payload['accountType']
      
      case container
      when 'bank'
        if ['CHECKING', 'SAVINGS'].include?(subtype)
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
        if subtype == 'MORTGAGE'
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
end
