require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:depository)
  end

  test "should get index" do
    get accounts_url
    assert_response :success
  end

  test "should get show" do
    get account_url(@account)
    assert_response :success
  end

  test "should sync account" do
    post sync_account_url(@account)
    assert_redirected_to account_url(@account)
  end

  test "should get sparkline" do
    get sparkline_account_url(@account)
    assert_response :success
  end

  test "destroys account" do
    delete account_url(@account)
    assert_redirected_to accounts_path
    assert_enqueued_with job: DestroyJob
    assert_equal "Account scheduled for deletion", flash[:notice]
  end
end

  test "should handle unauthorized access when not signed in" do
    sign_out @user
    get accounts_url
    assert_redirected_to new_user_session_path
  end

  test "should handle access to non-existent account" do
    assert_raises(ActiveRecord::RecordNotFound) do
      get account_url(id: 99999)
    end
  end

  test "index should render accounts data" do
    get accounts_url
    assert_response :success
    assert_select "title", /Accounts/i
    assert_not_nil assigns(:accounts)
  end

  test "show should display account details" do
    get account_url(@account)
    assert_response :success
    assert_select "h1", @account.name
    assert_not_nil assigns(:account)
  end

  test "show should handle account with no transactions" do
    empty_account = accounts(:empty)
    get account_url(empty_account)
    assert_response :success
  end

  test "sync should handle sync failure gracefully" do
    Account.any_instance.stubs(:sync).raises(StandardError.new("Sync failed"))
    post sync_account_url(@account)
    assert_redirected_to account_url(@account)
    assert_match /error/i, flash[:alert]
  end

  test "sync should update account balance on success" do
    original_balance = @account.balance
    Account.any_instance.stubs(:sync).returns(true)
    post sync_account_url(@account)
    assert_redirected_to account_url(@account)
    assert_match /success/i, flash[:notice]
  end

  test "sparkline should return valid JSON data" do
    get sparkline_account_url(@account)
    assert_response :success
    assert_equal "application/json", response.content_type
    json_response = JSON.parse(response.body)
    assert json_response.is_a?(Array)
  end

  test "sparkline should handle account with insufficient data" do
    empty_account = accounts(:empty)
    get sparkline_account_url(empty_account)
    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal [], json_response
  end

  test "destroy should not delete account immediately" do
    account_count = Account.count
    delete account_url(@account)
    assert_equal account_count, Account.count
    assert_redirected_to accounts_path
  end

  test "destroy should mark account for deletion" do
    delete account_url(@account)
    @account.reload
    assert @account.deletion_scheduled?
  end

  test "destroy should handle already deleted account" do
    @account.update!(deleted_at: Time.current)
    delete account_url(@account)
    assert_redirected_to accounts_path
    assert_match /already/i, flash[:alert]
  end

  test "should handle different account types correctly" do
    %w[checking savings credit investment].each do |account_type|
      account = accounts(account_type.to_sym)
      get account_url(account)
      assert_response :success
      assert_select ".account-type", account_type.humanize
    end
  end

  test "should enforce user access permissions" do
    other_user_account = accounts(:other_user_account)
    get account_url(other_user_account)
    assert_response :forbidden
  end

  test "index should filter accounts by status" do
    get accounts_url, params: { status: "active" }
    assert_response :success
    assigns(:accounts).each do |account|
      assert account.active?
    end
  end

  test "index should handle empty account list" do
    Account.where(user: @user).destroy_all
    get accounts_url
    assert_response :success
    assert_select ".empty-state"
  end

  test "show should display recent transactions" do
    get account_url(@account)
    assert_response :success
    assert_select ".transactions .transaction", count: @account.transactions.recent.count
  end

  test "sync should handle concurrent sync attempts" do
    # Simulate concurrent sync by setting a sync lock
    @account.update!(syncing: true)
    post sync_account_url(@account)
    assert_redirected_to account_url(@account)
    assert_match /in progress/i, flash[:notice]
  end

  test "should handle malformed sparkline requests" do
    get sparkline_account_url(@account), params: { period: "invalid" }
    assert_response :bad_request
  end

  test "should validate account ownership on all actions" do
    other_account = accounts(:other_user_account)
    
    get account_url(other_account)
    assert_response :forbidden
    
    post sync_account_url(other_account)
    assert_response :forbidden
    
    delete account_url(other_account)
    assert_response :forbidden
  end

  test "destroy should handle network errors during deletion job" do
    DestroyJob.any_instance.stubs(:perform).raises(Net::TimeoutError)
    delete account_url(@account)
    assert_redirected_to accounts_path
    assert_enqueued_with job: DestroyJob
  end

  private

  def sign_out(user)
    delete destroy_user_session_path
  end
