class ImportYodleeDataJob < ApplicationJob
  queue_as :default
  
  # Maximum number of days to look back for transactions on initial import
  MAX_HISTORY_DAYS = 90
  
  # Rate limiting - avoid hitting Yodlee API too frequently
  RATE_LIMIT_DELAY = 0.5 # seconds between API calls

  def perform(yodlee_item_id)
    @yodlee_item = YodleeItem.find(yodlee_item_id)
    @family = @yodlee_item.family
    @yodlee_provider = Provider::Registry.get_provider(:yodlee)
    
    Rails.logger.tagged("ImportYodleeData", @yodlee_item.id) do
      begin
        Rails.logger.info("Starting Yodlee data import for item #{@yodlee_item.id}")
        
        # Create a sync record to track progress
        sync = @yodlee_item.syncs.create!
        sync.start!
        
        # Fetch and process accounts
        import_accounts
        
        # Fetch and process transactions
        import_transactions
        
        # Process the accounts (calculate balances, etc.)
        @yodlee_item.process_accounts
        
        # Schedule account syncs to calculate historical balances
        @yodlee_item.schedule_account_syncs(parent_sync: sync)
        
        # Update last synced timestamp
        @yodlee_item.update!(last_synced_at: Time.current)
        
        # Complete the sync
        sync.complete!
        
        Rails.logger.info("Completed Yodlee data import for item #{@yodlee_item.id}")
      rescue StandardError => e
        Rails.logger.error("Error importing Yodlee data: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        
        # Mark sync as failed if it exists
        sync&.fail!
        
        # Update item status to indicate it needs attention
        @yodlee_item.update(status: :requires_update)
        
        # Report to Sentry if available
        if defined?(Sentry)
          Sentry.capture_exception(e) do |scope|
            scope.set_context('yodlee_item', { id: @yodlee_item.id, name: @yodlee_item.name })
          end
        end
        
        raise e # Re-raise to mark the job as failed
      end
    end
  end
  
  private
  
    def import_accounts
      Rails.logger.info("Fetching accounts from Yodlee")
      
      # Get accounts from Yodlee API
      accounts = @yodlee_provider.get_accounts(@yodlee_item.user_session)
      return if accounts.blank?
      
      Rails.logger.info("Found #{accounts.size} accounts in Yodlee")
      
      # Process each account
      accounts.each_with_index do |account_data, index|
        # Rate limiting
        sleep(RATE_LIMIT_DELAY) if index > 0
        
        process_account(account_data)
      end
    end
    
    def process_account(account_data)
      yodlee_id = account_data['id'].to_s
      
      # Find or create YodleeAccount
      yodlee_account = @yodlee_item.yodlee_accounts.find_or_initialize_by(yodlee_id: yodlee_id)
      yodlee_account.raw_payload = account_data
      yodlee_account.last_synced_at = Time.current
      yodlee_account.save!
      
      # Create or link to Maybe account
      maybe_account = yodlee_account.create_or_update_account!
      
      Rails.logger.info("Processed Yodlee account: #{yodlee_id}, linked to Maybe account: #{maybe_account&.id || 'none'}")
      
      yodlee_account
    end
    
    def import_transactions
      Rails.logger.info("Fetching transactions from Yodlee")
      
      # Determine date range for transactions
      from_date = determine_from_date
      to_date = Date.current
      
      Rails.logger.info("Fetching transactions from #{from_date} to #{to_date}")
      
      # Get all YodleeAccounts that have been linked to Maybe accounts
      linked_accounts = @yodlee_item.yodlee_accounts.linked
      
      # For each linked account, fetch and process transactions
      linked_accounts.each_with_index do |yodlee_account, index|
        # Rate limiting
        sleep(RATE_LIMIT_DELAY) if index > 0
        
        # Fetch transactions for this account
        process_account_transactions(yodlee_account, from_date, to_date)
      end
    end
    
    def process_account_transactions(yodlee_account, from_date, to_date)
      maybe_account = yodlee_account.account
      return unless maybe_account.present?
      
      Rails.logger.info("Processing transactions for account: #{yodlee_account.yodlee_id}")
      
      # Fetch transactions from Yodlee API
      transactions = yodlee_account.sync_transactions(from_date: from_date, to_date: to_date)
      
      if transactions.present?
        Rails.logger.info("Found #{transactions.size} transactions for account #{yodlee_account.yodlee_id}")
        
        # Auto-categorize transactions if enabled
        @family.auto_categorize_transactions_later(transactions) if @family.auto_sync_enabled?
        
        # Auto-detect merchants if enabled
        @family.auto_detect_transaction_merchants_later(transactions) if @family.auto_sync_enabled?
      else
        Rails.logger.info("No transactions found for account #{yodlee_account.yodlee_id}")
      end
    end
    
    def determine_from_date
      # If this is the first sync, look back MAX_HISTORY_DAYS
      if @yodlee_item.last_synced_at.nil?
        MAX_HISTORY_DAYS.days.ago.to_date
      else
        # Otherwise, look back from the last sync date (with a small overlap to catch any missed transactions)
        [@yodlee_item.last_synced_at.to_date - 7.days, MAX_HISTORY_DAYS.days.ago.to_date].max
      end
    end
end
