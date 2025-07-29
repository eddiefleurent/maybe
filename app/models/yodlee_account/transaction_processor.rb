class YodleeAccount::TransactionProcessor
  attr_reader :yodlee_account, :transaction_data, :account

  # Load Yodlee category mapping from config file
  CATEGORY_MAP = begin
    yaml_path = Rails.root.join('config', 'yodlee_categories.yml')
    if File.exist?(yaml_path)
      YAML.load_file(yaml_path)
    else
      # Default empty mapping if file doesn't exist yet
      {}
    end
  rescue StandardError => e
    Rails.logger.error("Error loading Yodlee category mapping: #{e.message}")
    {}
  end

  def initialize(yodlee_account, transaction_data)
    @yodlee_account = yodlee_account
    @transaction_data = transaction_data
    @account = yodlee_account.account
  end

  def process
    # Skip processing if the account doesn't exist
    return nil unless account.present?

    Rails.logger.tagged("YodleeAccount::TransactionProcessor", yodlee_account.id) do
      Rails.logger.debug("Processing Yodlee transaction: #{transaction_data['id']}")

      # Check if transaction already exists
      existing_transaction = find_existing_transaction
      return existing_transaction if existing_transaction.present?

      # Create the transaction
      transaction = create_transaction
      
      if transaction&.persisted?
        Rails.logger.debug("Created transaction: #{transaction.id} for Yodlee transaction: #{transaction_data['id']}")
      else
        error_message = transaction ? transaction.errors.full_messages.join(', ') : "Unknown error"
        Rails.logger.error("Failed to create transaction for Yodlee transaction #{transaction_data['id']}: #{error_message}")
      end

      transaction
    end
  rescue StandardError => e
    Rails.logger.error("Error processing Yodlee transaction #{transaction_data['id']}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    
    if defined?(Sentry)
      Sentry.capture_exception(e) do |scope|
        scope.set_context('yodlee_transaction', { 
          id: transaction_data['id'],
          account_id: yodlee_account.id
        })
      end
    end
    
    nil
  end

  private
    def find_existing_transaction
      # Look for existing transaction by external ID
      external_id = transaction_data['id'].to_s
      account.transactions.find_by(external_id: external_id, provider: 'yodlee')
    end

    def create_transaction
      # Extract transaction data
      date = parse_date
      amount_cents = calculate_amount_cents
      description = extract_description
      category_slug = map_category
      merchant_name = extract_merchant_name
      
      # Create the transaction
      transaction = account.transactions.new(
        date: date,
        amount_cents: amount_cents,
        payee: description,
        description: description,
        notes: extract_notes,
        category_slug: category_slug,
        external_id: transaction_data['id'].to_s,
        provider: 'yodlee',
        raw: transaction_data,
        currency: account.currency
      )

      # Set merchant if available
      set_merchant(transaction, merchant_name) if merchant_name.present?

      # Save the transaction
      if transaction.save
        # Create entry for the transaction (handled by Transaction model callbacks)
        transaction
      else
        Rails.logger.error("Failed to save transaction: #{transaction.errors.full_messages.join(', ')}")
        nil
      end
    end

    def parse_date
      # Parse transaction date from Yodlee data
      date_str = transaction_data['date'] || transaction_data['transactionDate']
      return Date.current unless date_str.present?

      begin
        Date.parse(date_str.to_s)
      rescue ArgumentError
        Rails.logger.warn("Invalid date format for Yodlee transaction #{transaction_data['id']}: #{date_str}")
        Date.current
      end
    end

    def calculate_amount_cents
      # Extract amount from transaction data
      amount = transaction_data.dig('amount', 'amount')
      return 0 unless amount.present?

      # Convert to cents
      amount_cents = (amount.to_d * 100).to_i

      # Determine if this is a debit or credit
      # In Yodlee, DEBIT means money leaving the account (negative for the user)
      # CREDIT means money entering the account (positive for the user)
      transaction_type = transaction_data['baseType']
      
      if transaction_type == 'DEBIT'
        -amount_cents.abs
      else
        amount_cents.abs
      end
    end

    def extract_description
      # Get the best description from the transaction data
      simple_desc = transaction_data.dig('description', 'simple')
      original_desc = transaction_data.dig('description', 'original')
      
      # Prefer simple description, fall back to original or a default
      simple_desc.presence || original_desc.presence || "Unknown Transaction"
    end

    def extract_notes
      # Extract any additional information that might be useful as notes
      [
        transaction_data.dig('description', 'original'),
        transaction_data['memo'],
        transaction_data['checkNumber'] ? "Check ##{transaction_data['checkNumber']}" : nil
      ].compact.join("\n").presence
    end

    def map_category
      # Map Yodlee category to Maybe category
      yodlee_category_id = transaction_data.dig('category', 'id')
      return 'uncategorized' unless yodlee_category_id.present?
      
      # Look up the category in our mapping
      CATEGORY_MAP[yodlee_category_id.to_s] || 'uncategorized'
    end

    def extract_merchant_name
      # Try to extract merchant name from various fields
      merchant_name = transaction_data['merchant']
      return merchant_name if merchant_name.present?
      
      # Fall back to simple description as merchant name
      simple_desc = transaction_data.dig('description', 'simple')
      return simple_desc if simple_desc.present?
      
      nil
    end

    def set_merchant(transaction, merchant_name)
      # Find or create a merchant record
      family = account.family
      
      # Look for existing merchant
      merchant = family.merchants.find_by(name: merchant_name)
      
      # If no merchant exists, create one
      unless merchant.present?
        merchant = family.merchants.create(name: merchant_name)
      end
      
      # Associate merchant with transaction if created successfully
      transaction.merchant = merchant if merchant.persisted?
    end
end
