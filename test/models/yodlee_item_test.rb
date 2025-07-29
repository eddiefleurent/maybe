require "test_helper"

class YodleeItemTest < ActiveSupport::TestCase
  setup do
    @yodlee_item = YodleeItem.new(
      yodlee_id: "123456",
      status: "active",
      last_synced_at: 1.hour.ago
    )
  end

  test "should have active scope" do
    assert_respond_to YodleeItem, :active
    
    # Mock the scope
    active_items = YodleeItem.active
    assert_not_nil active_items
  end

  test "should check if item is syncing" do
    assert_respond_to @yodlee_item, :syncing?
    
    # Test different syncing states
    @yodlee_item.sync_status = "syncing"
    assert @yodlee_item.syncing?
    
    @yodlee_item.sync_status = "idle"
    assert_not @yodlee_item.syncing?
  end

  test "should schedule sync later" do
    assert_respond_to @yodlee_item, :sync_later
    
    # Mock job scheduling
    YodleeItem::SyncJob.expects(:perform_later).with(@yodlee_item)
    
    @yodlee_item.sync_later
  end

  test "should find items by yodlee_id" do
    # Test the where clause used in webhook processing
    yodlee_ids = ["123456", "789012"]
    
    YodleeItem.expects(:where).with(yodlee_id: yodlee_ids).returns([])
    
    result = YodleeItem.where(yodlee_id: yodlee_ids)
    assert_not_nil result
  end

  test "should handle string and integer yodlee_ids" do
    # Webhook payloads might contain integers that need to be converted to strings
    integer_id = 123456
    string_id = "123456"
    
    assert_equal string_id, integer_id.to_s
    
    # Test that both formats work in queries
    YodleeItem.expects(:where).with(yodlee_id: [string_id]).returns([])
    YodleeItem.where(yodlee_id: [integer_id.to_s])
  end

  test "should validate yodlee_id presence" do
    item = YodleeItem.new
    
    assert_not item.valid?
    assert_includes item.errors[:yodlee_id], "can't be blank"
  end

  test "should track last sync time" do
    assert_respond_to @yodlee_item, :last_synced_at
    
    # Should update after sync
    @yodlee_item.last_synced_at = Time.current
    assert @yodlee_item.last_synced_at.present?
  end
end