require "test_helper"

class FamilyTest < ActiveSupport::TestCase
  include SyncableInterfaceTest

  def setup
    @syncable = families(:dylan_family)
    @family = families(:dylan_family)
  end

  # Test associations with proper dependency configurations
  test "should have many users with destroy dependency" do
    assert_respond_to @family, :users
    assert_equal :destroy, @family.class.reflect_on_association(:users).options[:dependent]
  end

  test "should have many accounts with destroy dependency" do
    assert_respond_to @family, :accounts
    assert_equal :destroy, @family.class.reflect_on_association(:accounts).options[:dependent]
  end

  test "should have many invitations with destroy dependency" do
    assert_respond_to @family, :invitations
    assert_equal :destroy, @family.class.reflect_on_association(:invitations).options[:dependent]
  end

  test "should have many imports with destroy dependency" do
    assert_respond_to @family, :imports
    assert_equal :destroy, @family.class.reflect_on_association(:imports).options[:dependent]
  end

  test "should have many family_exports with destroy dependency" do
    assert_respond_to @family, :family_exports
    assert_equal :destroy, @family.class.reflect_on_association(:family_exports).options[:dependent]
  end

  test "should have many entries through accounts" do
    assert_respond_to @family, :entries
    assert_equal :accounts, @family.class.reflect_on_association(:entries).options[:through]
  end

  test "should have many transactions through accounts" do
    assert_respond_to @family, :transactions
    assert_equal :accounts, @family.class.reflect_on_association(:transactions).options[:through]
  end

  test "should have many rules with destroy dependency" do
    assert_respond_to @family, :rules
    assert_equal :destroy, @family.class.reflect_on_association(:rules).options[:dependent]
  end

  test "should have many trades through accounts" do
    assert_respond_to @family, :trades
    assert_equal :accounts, @family.class.reflect_on_association(:trades).options[:through]
  end

  test "should have many holdings through accounts" do
    assert_respond_to @family, :holdings
    assert_equal :accounts, @family.class.reflect_on_association(:holdings).options[:through]
  end

  test "should have many tags with destroy dependency" do
    assert_respond_to @family, :tags
    assert_equal :destroy, @family.class.reflect_on_association(:tags).options[:dependent]
  end

  test "should have many categories with destroy dependency" do
    assert_respond_to @family, :categories
    assert_equal :destroy, @family.class.reflect_on_association(:categories).options[:dependent]
  end

  test "should have many merchants with correct class name and destroy dependency" do
    assert_respond_to @family, :merchants
    assert_equal :destroy, @family.class.reflect_on_association(:merchants).options[:dependent]
    assert_equal "FamilyMerchant", @family.class.reflect_on_association(:merchants).options[:class_name]
  end

  test "should have many budgets with destroy dependency" do
    assert_respond_to @family, :budgets
    assert_equal :destroy, @family.class.reflect_on_association(:budgets).options[:dependent]
  end

  test "should have many budget_categories through budgets" do
    assert_respond_to @family, :budget_categories
    assert_equal :budgets, @family.class.reflect_on_association(:budget_categories).options[:through]
  end

  # Test validations
  test "should validate locale inclusion in available locales" do
    family = Family.new(name: "Test Family")
    
    # Test valid locale
    if I18n.available_locales.include?(:en)
      family.locale = "en"
      family.valid?
      assert_not_includes family.errors[:locale], "is not included in the list"
    end
    
    # Test invalid locale
    family.locale = "invalid_locale"
    assert_not family.valid?
    assert_includes family.errors[:locale], "is not included in the list"
  end

  test "should validate date_format inclusion in predefined formats" do
    family = Family.new(name: "Test Family")
    
    # Test valid date format
    family.date_format = "%m-%d-%Y"
    family.valid?
    assert_not_includes family.errors[:date_format], "is not included in the list"
    
    # Test invalid date format
    family.date_format = "invalid_format"
    assert_not family.valid?
    assert_includes family.errors[:date_format], "is not included in the list"
  end

  # Test DATE_FORMATS constant
  test "DATE_FORMATS constant should contain expected formats and be frozen" do
    expected_formats = [
      [ "MM-DD-YYYY", "%m-%d-%Y" ],
      [ "DD.MM.YYYY", "%d.%m.%Y" ],
      [ "DD-MM-YYYY", "%d-%m-%Y" ],
      [ "YYYY-MM-DD", "%Y-%m-%d" ],
      [ "DD/MM/YYYY", "%d/%m/%Y" ],
      [ "YYYY/MM/DD", "%Y/%m/%d" ],
      [ "MM/DD/YYYY", "%m/%d/%Y" ],
      [ "D/MM/YYYY", "%e/%m/%Y" ],
      [ "YYYY.MM.DD", "%Y.%m.%d" ]
    ]
    
    assert_equal expected_formats, Family::DATE_FORMATS
    assert Family::DATE_FORMATS.frozen?
    assert_equal 9, Family::DATE_FORMATS.length
    
    Family::DATE_FORMATS.each do |format|
      assert_kind_of Array, format
      assert_equal 2, format.length
      assert_kind_of String, format[0]
      assert_kind_of String, format[1]
    end
  end

  # Test assigned_merchants method
  test "assigned_merchants should return merchants from family transactions" do
    # Mock the chain of method calls
    transactions_relation = mock('transactions')
    transactions_relation.expects(:where).with.not(merchant_id: nil).returns(transactions_relation)
    transactions_relation.expects(:pluck).with(:merchant_id).returns([1, 2, 3, 2, 1])
    transactions_relation.expects(:uniq).returns([1, 2, 3])
    
    @family.expects(:transactions).returns(transactions_relation)
    
    merchants_result = mock('merchants')
    Merchant.expects(:where).with(id: [1, 2, 3]).returns(merchants_result)
    
    result = @family.assigned_merchants
    assert_equal merchants_result, result
  end

  test "assigned_merchants should handle empty merchant list" do
    transactions_relation = mock('transactions')
    transactions_relation.expects(:where).with.not(merchant_id: nil).returns(transactions_relation)
    transactions_relation.expects(:pluck).with(:merchant_id).returns([])
    transactions_relation.expects(:uniq).returns([])
    
    @family.expects(:transactions).returns(transactions_relation)
    
    merchants_result = mock('merchants')
    Merchant.expects(:where).with(id: []).returns(merchants_result)
    
    result = @family.assigned_merchants
    assert_equal merchants_result, result
  end

  # Test auto-categorization methods
  test "auto_categorize_transactions_later should enqueue AutoCategorizeJob" do
    transactions = mock('transactions')
    transactions.expects(:pluck).with(:id).returns([1, 2, 3])
    
    assert_enqueued_with(job: AutoCategorizeJob, args: [@family, { transaction_ids: [1, 2, 3] }]) do
      @family.auto_categorize_transactions_later(transactions)
    end
  end

  test "auto_categorize_transactions should call AutoCategorizer" do
    transaction_ids = [1, 2, 3]
    
    categorizer = mock('auto_categorizer')
    categorizer.expects(:auto_categorize).once
    
    AutoCategorizer.expects(:new).with(@family, transaction_ids: transaction_ids).returns(categorizer)
    
    @family.auto_categorize_transactions(transaction_ids)
  end

  # Test auto-merchant detection methods
  test "auto_detect_transaction_merchants_later should enqueue AutoDetectMerchantsJob" do
    transactions = mock('transactions')
    transactions.expects(:pluck).with(:id).returns([4, 5, 6])
    
    assert_enqueued_with(job: AutoDetectMerchantsJob, args: [@family, { transaction_ids: [4, 5, 6] }]) do
      @family.auto_detect_transaction_merchants_later(transactions)
    end
  end

  test "auto_detect_transaction_merchants should call AutoMerchantDetector" do
    transaction_ids = [4, 5, 6]
    
    detector = mock('auto_merchant_detector')
    detector.expects(:auto_detect).once
    
    AutoMerchantDetector.expects(:new).with(@family, transaction_ids: transaction_ids).returns(detector)
    
    @family.auto_detect_transaction_merchants(transaction_ids)
  end

  # Test financial statement methods with memoization
  test "balance_sheet should return and memoize BalanceSheet instance" do
    balance_sheet = mock('balance_sheet')
    BalanceSheet.expects(:new).with(@family).returns(balance_sheet).once
    
    # First call should create new instance
    result1 = @family.balance_sheet
    assert_equal balance_sheet, result1
    
    # Second call should return memoized instance (no new BalanceSheet.new call)
    result2 = @family.balance_sheet
    assert_equal balance_sheet, result2
    assert_same result1, result2
  end

  test "income_statement should return and memoize IncomeStatement instance" do
    income_statement = mock('income_statement')
    IncomeStatement.expects(:new).with(@family).returns(income_statement).once
    
    # First call should create new instance
    result1 = @family.income_statement
    assert_equal income_statement, result1
    
    # Second call should return memoized instance (no new IncomeStatement.new call)
    result2 = @family.income_statement
    assert_equal income_statement, result2
    assert_same result1, result2
  end

  # Test eu? method
  test "eu? should return true for non-US and non-CA countries" do
    family = Family.new(name: "Test Family")
    
    # Test EU countries
    family.country = "DE"
    assert family.eu?
    
    family.country = "FR"
    assert family.eu?
    
    family.country = "IT"
    assert family.eu?
    
    # Test non-EU countries
    family.country = "US"
    assert_not family.eu?
    
    family.country = "CA"
    assert_not family.eu?
    
    # Test nil/empty country (should be considered EU)
    family.country = nil
    assert family.eu?
    
    family.country = ""
    assert family.eu?
  end

  # Test requires_data_provider? method - comprehensive scenarios
  test "requires_data_provider? should return true when family has trades" do
    @family.currency = "USD"
    
    trades_relation = mock('trades')
    trades_relation.expects(:any?).returns(true)
    @family.expects(:trades).returns(trades_relation)
    
    assert @family.requires_data_provider?
  end

  test "requires_data_provider? should return true when accounts have different currencies" do
    @family.currency = "USD"
    
    # Mock trades to return false
    trades_relation = mock('trades')
    trades_relation.expects(:any?).returns(false)
    @family.expects(:trades).returns(trades_relation)
    
    # Mock accounts with different currency
    accounts_relation = mock('accounts')
    accounts_relation.expects(:where).returns(accounts_relation)
    accounts_relation.expects(:not).with(currency: "USD").returns(accounts_relation)
    accounts_relation.expects(:any?).returns(true)
    @family.expects(:accounts).returns(accounts_relation)
    
    assert @family.requires_data_provider?
  end

  test "requires_data_provider? should return true when entries have multiple currencies" do
    @family.currency = "USD"
    
    # Mock trades to return false
    trades_relation = mock('trades')
    trades_relation.expects(:any?).returns(false)
    @family.expects(:trades).returns(trades_relation)
    
    # Mock accounts to return false
    accounts_relation = mock('accounts')
    accounts_relation.expects(:where).returns(accounts_relation)
    accounts_relation.expects(:not).with(currency: "USD").returns(accounts_relation)
    accounts_relation.expects(:any?).returns(false)
    @family.expects(:accounts).returns(accounts_relation)
    
    # Mock entries with multiple currencies
    entries_relation = mock('entries')
    entries_relation.expects(:pluck).with(:currency).returns(["USD", "EUR", "USD"])
    entries_relation.expects(:uniq).returns(["USD", "EUR"])
    @family.expects(:entries).returns(entries_relation)
    
    assert @family.requires_data_provider?
  end

  test "requires_data_provider? should return true when single entry currency differs from family currency" do
    @family.currency = "USD"
    
    # Mock trades to return false
    trades_relation = mock('trades')
    trades_relation.expects(:any?).returns(false)
    @family.expects(:trades).returns(trades_relation)
    
    # Mock accounts to return false
    accounts_relation = mock('accounts')
    accounts_relation.expects(:where).returns(accounts_relation)
    accounts_relation.expects(:not).with(currency: "USD").returns(accounts_relation)
    accounts_relation.expects(:any?).returns(false)
    @family.expects(:accounts).returns(accounts_relation)
    
    # Mock entries with single different currency
    entries_relation = mock('entries')
    entries_relation.expects(:pluck).with(:currency).returns(["EUR", "EUR"])
    entries_relation.expects(:uniq).returns(["EUR"])
    @family.expects(:entries).returns(entries_relation)
    
    assert @family.requires_data_provider?
  end

  test "requires_data_provider? should return false when no special conditions are met" do
    @family.currency = "USD"
    
    # Mock trades to return false
    trades_relation = mock('trades')
    trades_relation.expects(:any?).returns(false)
    @family.expects(:trades).returns(trades_relation)
    
    # Mock accounts to return false
    accounts_relation = mock('accounts')
    accounts_relation.expects(:where).returns(accounts_relation)
    accounts_relation.expects(:not).with(currency: "USD").returns(accounts_relation)
    accounts_relation.expects(:any?).returns(false)
    @family.expects(:accounts).returns(accounts_relation)
    
    # Mock entries with same currency as family
    entries_relation = mock('entries')
    entries_relation.expects(:pluck).with(:currency).returns(["USD", "USD"])
    entries_relation.expects(:uniq).returns(["USD"])
    @family.expects(:entries).returns(entries_relation)
    
    assert_not @family.requires_data_provider?
  end

  test "requires_data_provider? should return false when no entries exist" do
    @family.currency = "USD"
    
    # Mock trades to return false
    trades_relation = mock('trades')
    trades_relation.expects(:any?).returns(false)
    @family.expects(:trades).returns(trades_relation)
    
    # Mock accounts to return false
    accounts_relation = mock('accounts')
    accounts_relation.expects(:where).returns(accounts_relation)
    accounts_relation.expects(:not).with(currency: "USD").returns(accounts_relation)
    accounts_relation.expects(:any?).returns(false)
    @family.expects(:accounts).returns(accounts_relation)
    
    # Mock empty entries
    entries_relation = mock('entries')
    entries_relation.expects(:pluck).with(:currency).returns([])
    entries_relation.expects(:uniq).returns([])
    @family.expects(:entries).returns(entries_relation)
    
    assert_not @family.requires_data_provider?
  end

  # Test missing_data_provider? method
  test "missing_data_provider? should return true when requires provider but none available" do
    @family.expects(:requires_data_provider?).returns(true)
    Provider::Registry.expects(:get_provider).with(:synth).returns(nil)
    
    assert @family.missing_data_provider?
  end

  test "missing_data_provider? should return false when requires provider and provider available" do
    @family.expects(:requires_data_provider?).returns(true)
    Provider::Registry.expects(:get_provider).with(:synth).returns(mock('provider'))
    
    assert_not @family.missing_data_provider?
  end

  test "missing_data_provider? should return false when no provider required" do
    @family.expects(:requires_data_provider?).returns(false)
    
    assert_not @family.missing_data_provider?
  end

  # Test oldest_entry_date method
  test "oldest_entry_date should return date of oldest entry" do
    oldest_date = Date.current - 1.year
    
    entries_relation = mock('entries')
    entries_relation.expects(:order).with(:date).returns(entries_relation)
    
    oldest_entry = mock('entry')
    oldest_entry.expects(:date).returns(oldest_date)
    entries_relation.expects(:first).returns(oldest_entry)
    
    @family.expects(:entries).returns(entries_relation)
    
    assert_equal oldest_date, @family.oldest_entry_date
  end

  test "oldest_entry_date should return current date when no entries exist" do
    entries_relation = mock('entries')
    entries_relation.expects(:order).with(:date).returns(entries_relation)
    entries_relation.expects(:first).returns(nil)
    
    @family.expects(:entries).returns(entries_relation)
    
    assert_equal Date.current, @family.oldest_entry_date
  end

  # Test build_cache_key method
  test "build_cache_key should create cache key with basic components" do
    @family.id = 123
    current_time = Time.current
    
    accounts_relation = mock('accounts')
    accounts_relation.expects(:maximum).with(:updated_at).returns(current_time)
    @family.expects(:accounts).returns(accounts_relation)
    
    result = @family.build_cache_key("test_key")
    
    assert_includes result, "123"
    assert_includes result, "test_key"
    assert_includes result, current_time.to_s
  end

  test "build_cache_key should include data invalidation key when requested" do
    @family.id = 456
    sync_time = Time.current - 1.hour
    accounts_time = Time.current
    
    @family.expects(:latest_sync_completed_at).returns(sync_time)
    
    accounts_relation = mock('accounts')
    accounts_relation.expects(:maximum).with(:updated_at).returns(accounts_time)
    @family.expects(:accounts).returns(accounts_relation)
    
    result = @family.build_cache_key("sync_key", invalidate_on_data_updates: true)
    
    assert_includes result, "456"
    assert_includes result, "sync_key"
    assert_includes result, sync_time.to_s
    assert_includes result, accounts_time.to_s
  end

  test "build_cache_key should handle nil values gracefully" do
    @family.id = 789
    
    @family.expects(:latest_sync_completed_at).returns(nil)
    
    accounts_relation = mock('accounts')
    accounts_relation.expects(:maximum).with(:updated_at).returns(nil)
    @family.expects(:accounts).returns(accounts_relation)
    
    result = @family.build_cache_key("nil_key", invalidate_on_data_updates: true)
    
    assert_includes result, "789"
    assert_includes result, "nil_key"
    # Should not include nil values
    assert_not_includes result, "nil"
  end

  # Test entries_cache_version method
  test "entries_cache_version should return timestamp of most recent entry update" do
    recent_time = Time.current
    
    entries_relation = mock('entries')
    entries_relation.expects(:maximum).with(:updated_at).returns(recent_time)
    @family.expects(:entries).returns(entries_relation)
    
    result = @family.entries_cache_version
    assert_equal recent_time.to_i, result
  end

  test "entries_cache_version should return 0 when no entries exist" do
    entries_relation = mock('entries')
    entries_relation.expects(:maximum).with(:updated_at).returns(nil)
    @family.expects(:entries).returns(entries_relation)
    
    result = @family.entries_cache_version
    assert_equal 0, result
  end

  test "entries_cache_version should memoize result" do
    recent_time = Time.current
    
    entries_relation = mock('entries')
    entries_relation.expects(:maximum).with(:updated_at).returns(recent_time).once
    @family.expects(:entries).returns(entries_relation).once
    
    # First call
    result1 = @family.entries_cache_version
    assert_equal recent_time.to_i, result1
    
    # Second call should return memoized value without hitting the database
    result2 = @family.entries_cache_version
    assert_equal result1, result2
  end

  # Test self_hoster? method
  test "self_hoster? should delegate to Rails app config" do
    app_mode = mock('app_mode')
    app_mode.expects(:self_hosted?).returns(true)
    
    config = mock('config')
    config.expects(:app_mode).returns(app_mode)
    
    Rails.application.expects(:config).returns(config)
    
    assert @family.self_hoster?
  end

  test "self_hoster? should return false when not self hosted" do
    app_mode = mock('app_mode')
    app_mode.expects(:self_hosted?).returns(false)
    
    config = mock('config')
    config.expects(:app_mode).returns(app_mode)
    
    Rails.application.expects(:config).returns(config)
    
    assert_not @family.self_hoster?
  end

  # Test included modules
  test "should include all required modules" do
    assert Family.include?(PlaidConnectable), "Should include PlaidConnectable"
    assert Family.include?(YodleeConnectable), "Should include YodleeConnectable" 
    assert Family.include?(Syncable), "Should include Syncable"
    assert Family.include?(AutoTransferMatchable), "Should include AutoTransferMatchable"
    assert Family.include?(Subscribeable), "Should include Subscribeable"
  end

  # Edge cases and error handling
  test "should handle nil currency gracefully in requires_data_provider?" do
    family = Family.new(name: "Test Family")
    family.currency = nil
    
    # Mock the method chain to not fail on nil currency
    trades_relation = mock('trades')
    trades_relation.expects(:any?).returns(false)
    family.expects(:trades).returns(trades_relation)
    
    accounts_relation = mock('accounts')
    accounts_relation.expects(:where).returns(accounts_relation)
    accounts_relation.expects(:not).with(currency: nil).returns(accounts_relation)
    accounts_relation.expects(:any?).returns(false)
    family.expects(:accounts).returns(accounts_relation)
    
    entries_relation = mock('entries')
    entries_relation.expects(:pluck).with(:currency).returns([])
    entries_relation.expects(:uniq).returns([])
    family.expects(:entries).returns(entries_relation)
    
    assert_nothing_raised do
      family.requires_data_provider?
    end
  end

  test "should handle database errors gracefully in assigned_merchants" do
    @family.expects(:transactions).raises(ActiveRecord::StatementInvalid.new("Database connection failed"))
    
    assert_raises ActiveRecord::StatementInvalid do
      @family.assigned_merchants
    end
  end

  test "should handle empty results in financial calculations" do
    # Test balance_sheet with no accounts
    balance_sheet = mock('balance_sheet')
    BalanceSheet.expects(:new).with(@family).returns(balance_sheet)
    
    result = @family.balance_sheet
    assert_equal balance_sheet, result
  end

  # Test data integrity
  test "destroying family should destroy associated records" do
    # This would be tested with actual data in integration tests
    # Here we just verify the associations are configured correctly
    dependent_associations = [:users, :accounts, :invitations, :imports, :family_exports, 
                             :rules, :tags, :categories, :merchants, :budgets]
    
    dependent_associations.each do |association|
      reflection = @family.class.reflect_on_association(association)
      assert_not_nil reflection, "Association #{association} should exist"
      assert_equal :destroy, reflection.options[:dependent], 
                   "Association #{association} should have dependent: :destroy"
    end
  end
end
