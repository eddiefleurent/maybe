class YodleeItem::Importer
  attr_reader :yodlee_item, :yodlee_provider

  def initialize(yodlee_item, yodlee_provider: nil)
    @yodlee_item = yodlee_item
    @yodlee_provider = yodlee_provider || Provider::Registry.get_provider(:yodlee)
  end

  def import
    Rails.logger.tagged("YodleeItem::Importer", yodlee_item.id) do
      Rails.logger.info("Importing Yodlee data for item #{yodlee_item.id}")

      # Step 1: Fetch accounts data from Yodlee
      fetch_and_store_accounts

      # Step 2: Fetch institution data if available
      fetch_and_store_institution

      # Step 3: Update last synced timestamp
      yodlee_item.update!(last_synced_at: Time.current)

      Rails.logger.info("Completed Yodlee import for item #{yodlee_item.id}")
    end
  rescue StandardError => e
    Rails.logger.error("Error importing Yodlee data: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    # Update item status to indicate it needs attention
    yodlee_item.update(status: :requires_update)

    # Report to Sentry if available
    if defined?(Sentry)
      Sentry.capture_exception(e) do |scope|
        scope.set_context('yodlee_item', { id: yodlee_item.id, name: yodlee_item.name })
      end
    end

    raise e # Re-raise to mark the job as failed
  end

  private
    def fetch_and_store_accounts
      # Get accounts from Yodlee API
      accounts = yodlee_provider.get_accounts(yodlee_item.user_session)
      return if accounts.blank?

      Rails.logger.info("Found #{accounts.size} accounts in Yodlee")

      # Store the first account's data in the YodleeItem for reference
      yodlee_item.upsert_yodlee_snapshot!(accounts.first) if accounts.first.present?

      # Process each account
      accounts.each do |account_data|
        process_account(account_data)
      end
    end

    def process_account(account_data)
      yodlee_id = account_data['id'].to_s

      # Find or create YodleeAccount
      yodlee_account = yodlee_item.yodlee_accounts.find_or_initialize_by(yodlee_id: yodlee_id)
      yodlee_account.raw_payload = account_data
      yodlee_account.last_synced_at = Time.current
      yodlee_account.save!

      Rails.logger.info("Processed Yodlee account: #{yodlee_id}")

      yodlee_account
    end

    def fetch_and_store_institution
      # Skip if no institution ID is available
      return unless yodlee_item.institution_id.present?

      # Fetch institution data from Yodlee
      institution_data = yodlee_provider.get_institution(yodlee_item.institution_id)
      return unless institution_data.present?

      # Store institution data in the YodleeItem
      yodlee_item.upsert_yodlee_institution_snapshot!(institution_data)

      # Try to fetch and attach logo if URL is available
      attach_institution_logo(institution_data) if institution_data['logo'].present?
    end

    def attach_institution_logo(institution_data)
      return if institution_data['logo'].blank?

      begin
        logo_url = institution_data['logo']
        
        # Download and attach the logo
        uri = URI.parse(logo_url)
        response = Net::HTTP.get_response(uri)
        
        if response.is_a?(Net::HTTPSuccess)
          # Create a tempfile with the image data
          temp_file = Tempfile.new(['institution_logo', '.png'])
          temp_file.binmode
          temp_file.write(response.body)
          temp_file.rewind
          
          # Attach the logo to the YodleeItem
          yodlee_item.logo.attach(
            io: temp_file,
            filename: "institution_logo_#{yodlee_item.institution_id}.png",
            content_type: 'image/png'
          )
          
          temp_file.close
          temp_file.unlink
        end
      rescue StandardError => e
        Rails.logger.warn("Failed to attach institution logo: #{e.message}")
        # Don't fail the import if logo attachment fails
      end
    end
end
