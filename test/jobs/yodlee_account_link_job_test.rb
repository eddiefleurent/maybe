require "test_helper"

class YodleeAccountLinkJobTest < ActiveJob::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @enrollment_data = {
      institution: { name: "Test Bank" },
      providerName: "Test Provider",
      user_session: "test_session_123",
      metadata: { key: "value" }
    }

    # Mock Provider::Registry to return a yodlee provider
    @yodlee_provider = mock('yodlee_provider')
    Provider::Registry.stubs(:get_provider).with(:yodlee).returns(@yodlee_provider)
  end

  test "should enqueue job with correct arguments" do
    assert_enqueued_with(job: YodleeAccountLinkJob, args: [@user.id, @enrollment_data]) do
      YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
    end
  end

  test "should perform job successfully with valid user and enrollment data" do
    @family.stubs(:can_connect_yodlee?).returns(true)
    @yodlee_provider.stubs(:create_user).with(@user).returns("user_session_123")

    yodlee_item = mock('yodlee_item')
    yodlee_item.stubs(:id).returns(1)
    @family.stubs(:create_yodlee_item!).returns(yodlee_item)

    assert_enqueued_with(job: ImportYodleeDataJob, args: [1]) do
      perform_enqueued_jobs do
        YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
      end
    end
  end

  test "should skip processing when family cannot connect to Yodlee" do
    @family.stubs(:can_connect_yodlee?).returns(false)

    @yodlee_provider.expects(:create_user).never
    @family.expects(:create_yodlee_item!).never

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
    end
  end

  test "should handle user not found" do
    non_existent_user_id = 999999

    assert_raises(ActiveRecord::RecordNotFound) do
      perform_enqueued_jobs do
        YodleeAccountLinkJob.perform_later(non_existent_user_id, @enrollment_data)
      end
    end
  end

  test "should handle nil user_id" do
    assert_raises(ActiveRecord::RecordNotFound) do
      perform_enqueued_jobs do
        YodleeAccountLinkJob.perform_later(nil, @enrollment_data)
      end
    end
  end

  test "should handle invalid user_id types" do
    assert_raises(ActiveRecord::RecordNotFound) do
      perform_enqueued_jobs do
        YodleeAccountLinkJob.perform_later("invalid", @enrollment_data)
      end
    end
  end

  test "should use user_session from enrollment_data when provided" do
    @family.stubs(:can_connect_yodlee?).returns(true)
    @yodlee_provider.expects(:create_user).never # Should not create new session

    yodlee_item = mock('yodlee_item')
    yodlee_item.stubs(:id).returns(1)
    @family.expects(:create_yodlee_item!).with(
      user_session: "test_session_123",
      item_name: "Test Bank",
      metadata: @enrollment_data
    ).returns(yodlee_item)

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
    end
  end

  test "should create new user session when not provided in enrollment_data" do
    enrollment_data_without_session = @enrollment_data.except(:user_session)

    @family.stubs(:can_connect_yodlee?).returns(true)
    @yodlee_provider.expects(:create_user).with(@user).returns("new_session_456")

    yodlee_item = mock('yodlee_item')
    yodlee_item.stubs(:id).returns(1)
    @family.expects(:create_yodlee_item!).with(
      user_session: "new_session_456",
      item_name: "Test Bank",
      metadata: enrollment_data_without_session
    ).returns(yodlee_item)

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, enrollment_data_without_session)
    end
  end

  test "should return early when user_session creation fails" do
    enrollment_data_without_session = @enrollment_data.except(:user_session)

    @family.stubs(:can_connect_yodlee?).returns(true)
    @yodlee_provider.stubs(:create_user).with(@user).returns(nil)

    @family.expects(:create_yodlee_item!).never

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, enrollment_data_without_session)
    end
  end

  test "should use institution name from enrollment_data" do
    @family.stubs(:can_connect_yodlee?).returns(true)

    yodlee_item = mock('yodlee_item')
    yodlee_item.stubs(:id).returns(1)
    @family.expects(:create_yodlee_item!).with(
      user_session: "test_session_123",
      item_name: "Test Bank",
      metadata: @enrollment_data
    ).returns(yodlee_item)

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
    end
  end

  test "should fallback to providerName when institution name not available" do
    enrollment_data = @enrollment_data.except(:institution)

    @family.stubs(:can_connect_yodlee?).returns(true)

    yodlee_item = mock('yodlee_item')
    yodlee_item.stubs(:id).returns(1)
    @family.expects(:create_yodlee_item!).with(
      user_session: "test_session_123",
      item_name: "Test Provider",
      metadata: enrollment_data
    ).returns(yodlee_item)

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, enrollment_data)
    end
  end

  test "should use default institution name when neither institution nor providerName available" do
    enrollment_data = @enrollment_data.except(:institution, :providerName)

    @family.stubs(:can_connect_yodlee?).returns(true)

    yodlee_item = mock('yodlee_item')
    yodlee_item.stubs(:id).returns(1)
    @family.expects(:create_yodlee_item!).with(
      user_session: "test_session_123",
      item_name: "Financial Institution",
      metadata: enrollment_data
    ).returns(yodlee_item)

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, enrollment_data)
    end
  end

  test "should log successful processing" do
    @family.stubs(:can_connect_yodlee?).returns(true)

    yodlee_item = mock('yodlee_item')
    yodlee_item.stubs(:id).returns(1)
    @family.stubs(:create_yodlee_item!).returns(yodlee_item)
    @family.stubs(:id).returns(42)

    Rails.logger.expects(:info).with("Processing Yodlee account link for user #{@user.id}")
    Rails.logger.expects(:info).with("Successfully created Yodlee item 1 for family 42")

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
    end
  end

  test "should handle StandardError and log error" do
    @family.stubs(:can_connect_yodlee?).returns(true)
    @family.stubs(:create_yodlee_item!).raises(StandardError.new("Database error"))

    Rails.logger.expects(:error).with("Error linking Yodlee account for user #{@user.id}: Database error")

    assert_raises(StandardError) do
      perform_enqueued_jobs do
        YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
      end
    end
  end

  test "should capture exception with Sentry when available" do
    @family.stubs(:can_connect_yodlee?).returns(true)
    error = StandardError.new("Test error")
    @family.stubs(:create_yodlee_item!).raises(error)

    # Mock Sentry
    sentry_scope = mock('sentry_scope')
    sentry_scope.expects(:set_user).with(id: @user.id)
    sentry_scope.expects(:set_context).with('yodlee_enrollment', @enrollment_data.to_h)

    Object.const_set('Sentry', mock('sentry'))
    Sentry.expects(:capture_exception).with(error).yields(sentry_scope)

    assert_raises(StandardError) do
      perform_enqueued_jobs do
        YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
      end
    end

    # Clean up
    Object.send(:remove_const, 'Sentry') if defined?(Sentry)
  end

  test "should handle Provider::Registry returning nil" do
    Provider::Registry.stubs(:get_provider).with(:yodlee).returns(nil)
    @family.stubs(:can_connect_yodlee?).returns(true)

    assert_raises(NoMethodError) do
      perform_enqueued_jobs do
        YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
      end
    end
  end

  test "should handle empty enrollment_data" do
    @family.stubs(:can_connect_yodlee?).returns(true)

    yodlee_item = mock('yodlee_item')
    yodlee_item.stubs(:id).returns(1)
    @family.expects(:create_yodlee_item!).with(
      user_session: "test_session_123",
      item_name: "Financial Institution",
      metadata: {}
    ).returns(yodlee_item)

    @yodlee_provider.stubs(:create_user).with(@user).returns("test_session_123")

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, {})
    end
  end

  test "should handle nil enrollment_data" do
    @family.stubs(:can_connect_yodlee?).returns(true)

    @yodlee_provider.stubs(:create_user).with(@user).returns("test_session_123")

    yodlee_item = mock('yodlee_item')
    yodlee_item.stubs(:id).returns(1)
    @family.expects(:create_yodlee_item!).with(
      user_session: "test_session_123",
      item_name: "Financial Institution",
      metadata: nil
    ).returns(yodlee_item)

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, nil)
    end
  end

  test "should handle yodlee_item creation failure" do
    @family.stubs(:can_connect_yodlee?).returns(true)
    @family.stubs(:create_yodlee_item!).raises(ActiveRecord::RecordInvalid.new(mock('record')))

    Rails.logger.expects(:error).with(includes("Error linking Yodlee account"))

    assert_raises(ActiveRecord::RecordInvalid) do
      perform_enqueued_jobs do
        YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
      end
    end
  end

  test "should queue ImportYodleeDataJob after successful yodlee_item creation" do
    @family.stubs(:can_connect_yodlee?).returns(true)

    yodlee_item = mock('yodlee_item')
    yodlee_item.stubs(:id).returns(123)
    @family.stubs(:create_yodlee_item!).returns(yodlee_item)

    assert_enqueued_with(job: ImportYodleeDataJob, args: [123]) do
      perform_enqueued_jobs do
        YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
      end
    end
  end

  test "should handle concurrent job execution for different users" do
    user2 = users(:family_member)
    user2.stubs(:family).returns(@family)

    @family.stubs(:can_connect_yodlee?).returns(true)

    yodlee_item1 = mock('yodlee_item1')
    yodlee_item1.stubs(:id).returns(1)
    yodlee_item2 = mock('yodlee_item2')
    yodlee_item2.stubs(:id).returns(2)

    @family.expects(:create_yodlee_item!).twice.returns(yodlee_item1, yodlee_item2)

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
      YodleeAccountLinkJob.perform_later(user2.id, @enrollment_data)
    end
  end

  test "should execute within reasonable time limit" do
    @family.stubs(:can_connect_yodlee?).returns(true)

    yodlee_item = mock('yodlee_item')
    yodlee_item.stubs(:id).returns(1)
    @family.stubs(:create_yodlee_item!).returns(yodlee_item)

    start_time = Time.current

    perform_enqueued_jobs do
      YodleeAccountLinkJob.perform_later(@user.id, @enrollment_data)
    end

    execution_time = Time.current - start_time
    assert execution_time < 5.seconds, "Job execution should complete within 5 seconds"
  end
end