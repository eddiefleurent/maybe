class YodleeAccountLinkJob < ApplicationJob
  queue_as :default

  def perform(user_id, enrollment_data)
    user = User.find(user_id)
    family = user.family

    # Skip if Yodlee is not configured
    return unless family.can_connect_yodlee?

    Rails.logger.info("Processing Yodlee account link for user #{user_id}")

    begin
      # Get the Yodlee provider from the registry
      yodlee_provider = Provider::Registry.get_provider(:yodlee)
      
      # Get or create a Yodlee user session
      user_session = enrollment_data[:user_session] || yodlee_provider.create_user(user)
      
      return unless user_session.present?

      # Create a Yodlee item for this family
      institution_name = enrollment_data.dig(:institution, :name) || 
                         enrollment_data[:providerName] || 
                         "Financial Institution"
      
      yodlee_item = family.create_yodlee_item!(
        user_session: user_session,
        item_name: institution_name,
        metadata: enrollment_data
      )
      
      # Queue the import job to fetch account data
      ImportYodleeDataJob.perform_later(yodlee_item.id)
      
      Rails.logger.info("Successfully created Yodlee item #{yodlee_item.id} for family #{family.id}")
    rescue StandardError => e
      Rails.logger.error("Error linking Yodlee account for user #{user_id}: #{e.message}")
      
      if defined?(Sentry)
        Sentry.capture_exception(e) do |scope|
          scope.set_user(id: user_id)
          scope.set_context('yodlee_enrollment', enrollment_data.to_h)
        end
      end
      
      raise e # Re-raise to mark the job as failed
    end
  end
end
