require 'test_helper'

class ImportYodleeDataJobTest < ActiveJob::TestCase
  def setup
    @family = families(:dylan_family)
    @yodlee_item = yodlee_items(:one)
    @yodlee_item.update!(family: @family)
    @job = ImportYodleeDataJob.new
    
    # Mock provider and service dependencies
    @yodlee_provider = mock('YodleeProvider')
    Provider::Registry.stubs(:get_provider).with(:yodlee).returns(@yodlee_provider)
    
    # Sample account data from Yodlee API
    @sample_accounts = [
      {
        'id' => 12345,
        'accountName' => 'Test Checking Account',
        'accountType' => 'CHECKING',
        'accountStatus' => 'ACTIVE',
        'balance' => {
          'amount' => 1500.50,
          'currency' => 'USD'
        },
        'providerId' => 67890,
        'providerName' => 'Test Bank'
      },
      {
        'id' => 54321,
        'accountName' => 'Test Savings Account', 
        'accountType' => 'SAVINGS',
        'accountStatus' => 'ACTIVE',
        'balance' => {
          'amount' => 5000.00,
          'currency' => 'USD'
        }
      }
    ]
    
    # Sample transaction data
    @sample_transactions = [
      {
        'id' => 98765,
        'amount' => {
          'amount' => -25.00,
          'currency' => 'USD'
        },
        'baseType' => 'DEBIT',
        'categoryType' => 'EXPENSE',
        'description' => {
          'simple' => 'Coffee Shop Purchase'
        },
        'date' => '2023-12-01',
        'status' => 'POSTED',
        'accountId' => 12345
      }
    ]
  end

  def teardown
    Mocha::Mockery.instance.teardown if defined?(Mocha::Mockery)
  end

  # Basic job configuration tests
  test "should inherit from ApplicationJob" do
    assert_kind_of ApplicationJob, @job
  end

  test "should have default queue" do
    assert_equal :default, ImportYodleeDataJob.queue_name
  end

  test "should enqueue job with correct arguments" do
    assert_enqueued_with(job: ImportYodleeDataJob, args: [@yodlee_item.id]) do
      ImportYodleeDataJob.perform_later(@yodlee_item.id)
    end
  end

  # Happy path - successful import
  test "should successfully import data with valid yodlee item" do
    mock_successful_import
    
    perform_enqueued_jobs do
      ImportYodleeDataJob.perform_later(@yodlee_item.id)
    end
    
    @yodlee_item.reload
    assert_not_nil @yodlee_item.last_synced_at
    assert @yodlee_item.syncs.exists?
    assert_equal 'completed', @yodlee_item.syncs.last.status
  end

  test "should create sync record and mark as started" do
    mock_successful_import
    
    assert_difference '@yodlee_item.syncs.count', 1 do
      @job.perform(@yodlee_item.id)
    end
    
    sync = @yodlee_item.syncs.last
    assert_equal 'completed', sync.status
  end

  test "should process accounts before transactions" do
    @yodlee_provider.expects(:get_accounts).with(@yodlee_item.user_session).returns(@sample_accounts)
    
    # Mock YodleeAccount creation and processing
    yodlee_account1 = mock('YodleeAccount1')
    yodlee_account2 = mock('YodleeAccount2')
    
    @yodlee_item.yodlee_accounts.expects(:find_or_initialize_by).with(yodlee_id: '12345').returns(yodlee_account1)
    @yodlee_item.yodlee_accounts.expects(:find_or_initialize_by).with(yodlee_id: '54321').returns(yodlee_account2)
    
    yodlee_account1.expects(:raw_payload=).with(@sample_accounts[0])
    yodlee_account1.expects(:last_synced_at=)
    yodlee_account1.expects(:save!)
    yodlee_account1.expects(:create_or_update_account!)
    
    yodlee_account2.expects(:raw_payload=).with(@sample_accounts[1])
    yodlee_account2.expects(:last_synced_at=)
    yodlee_account2.expects(:save!)
    yodlee_account2.expects(:create_or_update_account!)
    
    # Mock empty linked accounts for transaction processing
    @yodlee_item.yodlee_accounts.expects(:linked).returns([])
    
    # Mock other required methods
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    @job.perform(@yodlee_item.id)
  end

  test "should process transactions for linked accounts" do
    # Mock empty accounts response
    @yodlee_provider.expects(:get_accounts).returns([])
    
    # Create mock linked yodlee accounts
    linked_account = mock('LinkedYodleeAccount')
    linked_account.stubs(:yodlee_id).returns('12345')
    linked_account.stubs(:account).returns(accounts(:checking))
    
    @yodlee_item.yodlee_accounts.expects(:linked).returns([linked_account])
    
    # Mock transaction sync
    linked_account.expects(:sync_transactions).with(
      from_date: anything,
      to_date: anything
    ).returns(@sample_transactions)
    
    # Mock auto-categorization
    @family.expects(:auto_sync_enabled?).returns(true).twice
    @family.expects(:auto_categorize_transactions_later).with(@sample_transactions)
    @family.expects(:auto_detect_transaction_merchants_later).with(@sample_transactions)
    
    # Mock other required methods
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    @job.perform(@yodlee_item.id)
  end

  # Error handling tests
  test "should raise error for invalid yodlee item id" do
    assert_raises(ActiveRecord::RecordNotFound) do
      @job.perform(99999)
    end
  end

  test "should handle nil yodlee item id" do
    assert_raises(TypeError) do
      @job.perform(nil)
    end
  end

  test "should mark sync as failed on error and update item status" do
    # Create a sync record that will be marked as failed
    sync = @yodlee_item.syncs.create!
    @yodlee_item.syncs.expects(:create!).returns(sync)
    sync.expects(:start!)
    sync.expects(:fail!)
    
    # Mock error during account import
    @yodlee_provider.expects(:get_accounts).raises(StandardError.new("API Error"))
    
    # Mock status update
    @yodlee_item.expects(:update).with(status: :requires_update)
    
    assert_raises(StandardError) do
      @job.perform(@yodlee_item.id)
    end
  end

  test "should log errors with proper context" do
    error_message = "Connection timeout"
    @yodlee_provider.expects(:get_accounts).raises(StandardError.new(error_message))
    
    Rails.logger.expects(:error).with("Error importing Yodlee data: #{error_message}")
    Rails.logger.expects(:error).with(anything) # backtrace
    
    assert_raises(StandardError) do
      @job.perform(@yodlee_item.id)
    end
  end

  test "should capture exception to Sentry when available" do
    # Mock Sentry being defined
    sentry_mock = mock('Sentry')
    stub_const('Sentry', sentry_mock)
    
    scope_mock = mock('Scope')
    sentry_mock.expects(:capture_exception).yields(scope_mock)
    scope_mock.expects(:set_context).with('yodlee_item', { id: @yodlee_item.id, name: @yodlee_item.name })
    
    @yodlee_provider.expects(:get_accounts).raises(StandardError.new("Test error"))
    
    assert_raises(StandardError) do
      @job.perform(@yodlee_item.id)
    end
  end

  # Rate limiting tests
  test "should apply rate limiting between account processing" do
    @yodlee_provider.expects(:get_accounts).returns(@sample_accounts)
    
    # Mock account processing
    @sample_accounts.each_with_index do |account_data, index|
      yodlee_account = mock("YodleeAccount#{index}")
      @yodlee_item.yodlee_accounts.expects(:find_or_initialize_by).with(yodlee_id: account_data['id'].to_s).returns(yodlee_account)
      yodlee_account.expects(:raw_payload=).with(account_data)
      yodlee_account.expects(:last_synced_at=)
      yodlee_account.expects(:save!)
      yodlee_account.expects(:create_or_update_account!)
    end
    
    # Expect sleep to be called once (for second account)
    @job.expects(:sleep).with(ImportYodleeDataJob::RATE_LIMIT_DELAY).once
    
    # Mock other required methods
    @yodlee_item.yodlee_accounts.expects(:linked).returns([])
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    @job.perform(@yodlee_item.id)
  end

  test "should apply rate limiting between transaction account processing" do
    @yodlee_provider.expects(:get_accounts).returns([])
    
    # Create two mock linked accounts
    account1 = mock('Account1')
    account1.stubs(:yodlee_id).returns('123')
    account1.stubs(:account).returns(accounts(:checking))
    account1.expects(:sync_transactions).returns([])
    
    account2 = mock('Account2') 
    account2.stubs(:yodlee_id).returns('456')
    account2.stubs(:account).returns(accounts(:savings))
    account2.expects(:sync_transactions).returns([])
    
    @yodlee_item.yodlee_accounts.expects(:linked).returns([account1, account2])
    
    # Expect sleep to be called once (for second account)
    @job.expects(:sleep).with(ImportYodleeDataJob::RATE_LIMIT_DELAY).once
    
    # Mock other required methods
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    @job.perform(@yodlee_item.id)
  end

  # Date range determination tests
  test "should use max history days for first sync" do
    @yodlee_item.update!(last_synced_at: nil)
    
    expected_from_date = ImportYodleeDataJob::MAX_HISTORY_DAYS.days.ago.to_date
    
    @yodlee_provider.expects(:get_accounts).returns([])
    
    linked_account = mock('LinkedAccount')
    linked_account.stubs(:yodlee_id).returns('123')
    linked_account.stubs(:account).returns(accounts(:checking))
    linked_account.expects(:sync_transactions).with(
      from_date: expected_from_date,
      to_date: Date.current
    ).returns([])
    
    @yodlee_item.yodlee_accounts.expects(:linked).returns([linked_account])
    
    # Mock other required methods
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    @job.perform(@yodlee_item.id)
  end

  test "should use last sync date with overlap for subsequent syncs" do
    last_sync = 30.days.ago
    @yodlee_item.update!(last_synced_at: last_sync)
    
    expected_from_date = last_sync.to_date - 7.days
    
    @yodlee_provider.expects(:get_accounts).returns([])
    
    linked_account = mock('LinkedAccount')
    linked_account.stubs(:yodlee_id).returns('123')
    linked_account.stubs(:account).returns(accounts(:checking))
    linked_account.expects(:sync_transactions).with(
      from_date: expected_from_date,
      to_date: Date.current
    ).returns([])
    
    @yodlee_item.yodlee_accounts.expects(:linked).returns([linked_account])
    
    # Mock other required methods
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    @job.perform(@yodlee_item.id)
  end

  test "should respect max history limit even with old last sync date" do
    very_old_sync = 200.days.ago
    @yodlee_item.update!(last_synced_at: very_old_sync)
    
    expected_from_date = ImportYodleeDataJob::MAX_HISTORY_DAYS.days.ago.to_date
    
    @yodlee_provider.expects(:get_accounts).returns([])
    
    linked_account = mock('LinkedAccount')
    linked_account.stubs(:yodlee_id).returns('123')  
    linked_account.stubs(:account).returns(accounts(:checking))
    linked_account.expects(:sync_transactions).with(
      from_date: expected_from_date,
      to_date: Date.current
    ).returns([])
    
    @yodlee_item.yodlee_accounts.expects(:linked).returns([linked_account])
    
    # Mock other required methods
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    @job.perform(@yodlee_item.id)
  end

  # Auto-sync feature tests
  test "should auto-categorize transactions when auto_sync enabled" do
    @yodlee_provider.expects(:get_accounts).returns([])
    
    linked_account = mock('LinkedAccount')
    linked_account.stubs(:yodlee_id).returns('123')
    linked_account.stubs(:account).returns(accounts(:checking))
    linked_account.expects(:sync_transactions).returns(@sample_transactions)
    
    @yodlee_item.yodlee_accounts.expects(:linked).returns([linked_account])
    
    @family.expects(:auto_sync_enabled?).returns(true).twice
    @family.expects(:auto_categorize_transactions_later).with(@sample_transactions)
    @family.expects(:auto_detect_transaction_merchants_later).with(@sample_transactions)
    
    # Mock other required methods
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    @job.perform(@yodlee_item.id)
  end

  test "should skip auto-categorization when auto_sync disabled" do
    @yodlee_provider.expects(:get_accounts).returns([])
    
    linked_account = mock('LinkedAccount')
    linked_account.stubs(:yodlee_id).returns('123')
    linked_account.stubs(:account).returns(accounts(:checking))
    linked_account.expects(:sync_transactions).returns(@sample_transactions)
    
    @yodlee_item.yodlee_accounts.expects(:linked).returns([linked_account])
    
    @family.expects(:auto_sync_enabled?).returns(false).twice
    @family.expects(:auto_categorize_transactions_later).never
    @family.expects(:auto_detect_transaction_merchants_later).never
    
    # Mock other required methods
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    @job.perform(@yodlee_item.id)
  end

  # Edge cases
  test "should handle empty accounts response" do
    @yodlee_provider.expects(:get_accounts).returns([])
    @yodlee_item.yodlee_accounts.expects(:linked).returns([])
    
    # Mock other required methods
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    assert_nothing_raised do
      @job.perform(@yodlee_item.id)
    end
  end

  test "should handle nil accounts response" do
    @yodlee_provider.expects(:get_accounts).returns(nil)
    @yodlee_item.yodlee_accounts.expects(:linked).returns([])
    
    # Mock other required methods  
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    assert_nothing_raised do
      @job.perform(@yodlee_item.id)
    end
  end

  test "should skip transaction processing for accounts without linked Maybe accounts" do
    @yodlee_provider.expects(:get_accounts).returns([])
    
    unlinked_account = mock('UnlinkedAccount')
    unlinked_account.stubs(:yodlee_id).returns('123')
    unlinked_account.stubs(:account).returns(nil) # Not linked to Maybe account
    
    @yodlee_item.yodlee_accounts.expects(:linked).returns([unlinked_account])
    
    # Should not attempt to sync transactions
    unlinked_account.expects(:sync_transactions).never
    
    # Mock other required methods
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    @job.perform(@yodlee_item.id)
  end

  test "should handle empty transactions response" do
    @yodlee_provider.expects(:get_accounts).returns([])
    
    linked_account = mock('LinkedAccount')
    linked_account.stubs(:yodlee_id).returns('123')
    linked_account.stubs(:account).returns(accounts(:checking))
    linked_account.expects(:sync_transactions).returns([])
    
    @yodlee_item.yodlee_accounts.expects(:linked).returns([linked_account])
    
    # Should not attempt auto-categorization with empty transactions
    @family.expects(:auto_sync_enabled?).never
    
    # Mock other required methods
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
    
    @job.perform(@yodlee_item.id)
  end

  # Performance and constants tests
  test "should have correct MAX_HISTORY_DAYS constant" do
    assert_equal 90, ImportYodleeDataJob::MAX_HISTORY_DAYS
  end

  test "should have correct RATE_LIMIT_DELAY constant" do
    assert_equal 0.5, ImportYodleeDataJob::RATE_LIMIT_DELAY
  end

  test "should complete within reasonable time for normal dataset" do
    mock_successful_import
    
    start_time = Time.current
    @job.perform(@yodlee_item.id)
    execution_time = Time.current - start_time
    
    assert execution_time < 30.seconds, "Job took too long: #{execution_time} seconds"
  end

  # Logging tests
  test "should log import start and completion" do
    mock_successful_import
    
    Rails.logger.expects(:info).with("Starting Yodlee data import for item #{@yodlee_item.id}")
    Rails.logger.expects(:info).with("Completed Yodlee data import for item #{@yodlee_item.id}")
    
    @job.perform(@yodlee_item.id)
  end

  test "should log account and transaction processing details" do
    mock_successful_import
    
    Rails.logger.expects(:info).with("Fetching accounts from Yodlee")
    Rails.logger.expects(:info).with("Found #{@sample_accounts.size} accounts in Yodlee")
    Rails.logger.expects(:info).with("Fetching transactions from Yodlee")
    Rails.logger.expects(:info).with(regexp_matches(/Fetching transactions from .* to .*/))
    
    @job.perform(@yodlee_item.id)
  end

  private

  def mock_successful_import
    # Mock account import
    @yodlee_provider.expects(:get_accounts).with(@yodlee_item.user_session).returns(@sample_accounts)
    
    @sample_accounts.each_with_index do |account_data, index|
      yodlee_account = mock("YodleeAccount#{index}")
      @yodlee_item.yodlee_accounts.expects(:find_or_initialize_by).with(yodlee_id: account_data['id'].to_s).returns(yodlee_account)
      yodlee_account.expects(:raw_payload=).with(account_data)
      yodlee_account.expects(:last_synced_at=)
      yodlee_account.expects(:save!)
      yodlee_account.expects(:create_or_update_account!)
    end
    
    # Mock transaction import - empty for simplicity
    @yodlee_item.yodlee_accounts.expects(:linked).returns([])
    
    # Mock final processing steps
    @yodlee_item.expects(:process_accounts)
    @yodlee_item.expects(:schedule_account_syncs)
    @yodlee_item.expects(:update!).with(last_synced_at: anything)
  end

  def stub_const(const_name, value)
    Object.const_set(const_name, value) unless Object.const_defined?(const_name)
  end
end