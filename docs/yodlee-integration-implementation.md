# Yodlee Integration for Maybe Finance

## Overview

This document details the implementation of Yodlee financial data aggregation services into Maybe Finance. The integration enables users to connect their financial accounts through Yodlee as an alternative to Plaid, providing broader coverage of financial institutions and a cost-effective solution for self-hosted deployments.

**Key Features Implemented:**

- Secure connection to financial institutions via Yodlee FastLink widget
- Automatic import of accounts, balances, and transactions
- Categorization of transactions using configurable mapping
- Background synchronization of financial data
- Webhook support for real-time updates
- Complete UI integration following Maybe Finance design patterns

## Architecture and Design Decisions

The Yodlee integration follows the same architectural patterns as the existing Plaid integration in Maybe Finance, ensuring consistency and maintainability:

### Provider Pattern

The integration uses the Provider pattern already established in Maybe Finance:

- `Provider::Registry` - Extended to include Yodlee provider
- `Provider::Yodlee` - Implements the Yodlee API client
- `YodleeItem::Provided` concern - Provides access to the Yodlee provider

### Model Structure

The data model mirrors the existing Plaid structure:

```
Family
  ↳ YodleeItem (similar to PlaidItem)
      ↳ YodleeAccount (similar to PlaidAccount)
          ↳ Account (existing Maybe account model)
```

### Syncable Pattern

The integration leverages the existing `Syncable` concern for background processing:

- `YodleeItem` includes the `Syncable` concern
- Syncs are processed through the existing `SyncJob` infrastructure
- Background jobs handle data fetching and processing

### Categorization System

A configurable mapping system translates Yodlee categories to Maybe Finance categories:

- YAML-based mapping file (`config/yodlee_categories.yml`)
- Default mappings for common categories
- Extensible for custom category mappings

## File Structure and Key Components

### Core Files

| File | Purpose |
|------|---------|
| `app/models/provider/yodlee.rb` | Yodlee API client implementation |
| `app/models/provider/registry.rb` | Updated to include Yodlee provider |
| `app/models/yodlee_item.rb` | Model for Yodlee connections |
| `app/models/yodlee_account.rb` | Model for Yodlee accounts |
| `app/models/family/yodlee_connectable.rb` | Family extension for Yodlee |
| `app/controllers/yodlee_items_controller.rb` | Controller for Yodlee items |
| `app/controllers/yodlee_tokens_controller.rb` | Controller for FastLink tokens |
| `config/initializers/yodlee.rb` | Yodlee configuration |
| `config/yodlee_categories.yml` | Category mapping |
| `db/migrate/TIMESTAMP_create_yodlee_items.rb` | Database migration |

### Processors and Importers

| File | Purpose |
|------|---------|
| `app/models/yodlee_item/importer.rb` | Imports data from Yodlee API |
| `app/models/yodlee_account/processor.rb` | Processes account data |
| `app/models/yodlee_account/transaction_processor.rb` | Processes transaction data |

### Background Jobs

| File | Purpose |
|------|---------|
| `app/jobs/yodlee_account_link_job.rb` | Handles initial account linking |
| `app/jobs/import_yodlee_data_job.rb` | Imports and processes Yodlee data |

### Views and UI Components

| File | Purpose |
|------|---------|
| `app/views/yodlee_items/new.html.erb` | FastLink integration view |
| `app/views/yodlee_items/_yodlee_item.html.erb` | Yodlee item display partial |

## Setup Process for Developers

### Prerequisites

- Maybe Finance application set up and running
- Yodlee Developer account (register at https://developer.yodlee.com)
- Public HTTPS endpoint for webhooks (optional, for production)

### Step 1: Register with Yodlee

1. Visit https://developer.yodlee.com and register for an account
2. Verify your email and access the dashboard
3. Navigate to **API Keys** and copy your Cobrand Client ID and Secret
4. Go to **FastLink Configuration**:
   - Create a new configuration
   - Enter your company name
   - Choose the "Aggregation" template
   - Publish to the Development environment

### Step 2: Configure Environment Variables

Add the following to your `.env` file:

```
# Yodlee Configuration
YODLEE_CLIENT_ID=your_client_id
YODLEE_SECRET=your_secret
YODLEE_BASE=https://development.api.envestnet.com/ysl
YODLEE_FASTLINK_URL=https://development.fastlink.envestnet.com
YODLEE_COBRAND_NAME=your_cobrand_name
ENABLE_YODLEE=true
```

### Step 3: Run Database Migrations

```bash
rails db:migrate
```

### Step 4: Restart Your Application

```bash
# If using Docker Compose
docker-compose restart web

# If running Rails directly
rails server
```

### Step 5: Verify Installation

1. Navigate to the Accounts page in Maybe Finance
2. Click "New account"
3. Verify that "Link account via Yodlee" appears as an option
4. Test the connection with Yodlee sandbox credentials

## Configuration Options

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `YODLEE_CLIENT_ID` | Your Yodlee Cobrand Client ID | (Required) |
| `YODLEE_SECRET` | Your Yodlee Cobrand Secret | (Required) |
| `YODLEE_BASE` | Yodlee API base URL | `https://development.api.envestnet.com/ysl` |
| `YODLEE_FASTLINK_URL` | Yodlee FastLink widget URL | `https://development.fastlink.envestnet.com` |
| `YODLEE_COBRAND_NAME` | Your Yodlee Cobrand Name | (Required) |
| `ENABLE_YODLEE` | Enable/disable Yodlee integration | `false` |

### Category Mapping

The `config/yodlee_categories.yml` file maps Yodlee category IDs to Maybe Finance category slugs:

```yaml
# Example mapping
1: income
2: salary
101: shopping
102: groceries
201: restaurants
```

To customize:

1. Edit `config/yodlee_categories.yml`
2. Add or modify mappings in the format `yodlee_category_id: maybe_category_slug`
3. Restart the application for changes to take effect

## Testing Guidelines

### Manual Testing

1. **Connection Testing**:
   - Navigate to Accounts > New account
   - Select "Link account via Yodlee"
   - Use Yodlee sandbox credentials to test the connection flow
   - Verify accounts appear in Maybe Finance

2. **Sync Testing**:
   - Click the sync button on a Yodlee item
   - Verify that accounts and transactions are updated
   - Check transaction categorization against your mapping

3. **Webhook Testing**:
   - Use a tool like ngrok to expose your local webhook endpoint
   - Configure the webhook URL in your Yodlee developer settings
   - Trigger events in Yodlee and verify they're processed correctly

### Automated Testing

Add the following tests to ensure proper integration:

- Unit tests for `Provider::Yodlee` methods
- Model tests for `YodleeItem` and `YodleeAccount`
- Controller tests for `YodleeItemsController` and `YodleeTokensController`
- Integration tests for the complete connection flow

## Troubleshooting Common Issues

### Connection Issues

**Problem**: Unable to connect to Yodlee FastLink widget

**Solutions**:
- Verify your Yodlee credentials are correct in `.env`
- Check that `ENABLE_YODLEE` is set to `true`
- Ensure your FastLink configuration is published in the Yodlee dashboard
- Check browser console for JavaScript errors

### Data Import Issues

**Problem**: Accounts connected but no transactions appear

**Solutions**:
- Check Rails logs for API errors
- Verify the Yodlee account has transactions in the date range
- Manually trigger a sync from the UI
- Check if transaction processing is failing due to mapping issues

### Category Mapping Issues

**Problem**: Transactions are all categorized as "uncategorized"

**Solutions**:
- Verify `config/yodlee_categories.yml` exists and has valid mappings
- Check Rails logs for category mapping errors
- Inspect raw transaction data to confirm category IDs
- Update the mapping file with missing categories

### Webhook Issues

**Problem**: Webhooks not triggering syncs

**Solutions**:
- Verify your webhook URL is accessible from the internet
- Check webhook logs in the Yodlee dashboard
- Ensure the webhook controller is properly handling the payload
- Check Rails logs for webhook processing errors

## Future Improvements

1. **Enhanced Error Handling**:
   - Implement more granular error handling for specific Yodlee API errors
   - Add user-friendly error messages for common connection issues

2. **Advanced Category Mapping**:
   - Implement machine learning for improved transaction categorization
   - Add support for subcategories and hierarchical mapping

3. **Performance Optimizations**:
   - Implement batched processing for large transaction imports
   - Add caching for frequently accessed Yodlee data

4. **UI Enhancements**:
   - Add detailed connection status indicators
   - Provide more granular control over which accounts to import
   - Implement a dedicated Yodlee settings page

5. **Security Enhancements**:
   - Implement additional encryption for stored Yodlee tokens
   - Add audit logging for Yodlee API access

6. **Multi-User Support**:
   - Allow different users within a family to connect their own Yodlee accounts
   - Implement permission controls for Yodlee connections

7. **Webhook Improvements**:
   - Add webhook signature verification when Yodlee supports it
   - Implement webhook retry mechanisms

## Monitoring and Maintenance

### Usage Monitoring

Yodlee has usage limits that should be monitored:

- Check your Yodlee Dashboard > Usage regularly
- Consider implementing usage tracking in Maybe Finance
- Set up alerts for approaching usage limits

### Scheduled Maintenance

To keep the integration running smoothly:

- Schedule regular syncs instead of on-demand syncs when possible
- Implement a cleanup job for stale Yodlee connections
- Keep the Yodlee SDK and API client updated

## Conclusion

The Yodlee integration provides Maybe Finance users with an alternative to Plaid for connecting financial accounts. By following the setup process and configuration guidelines in this document, developers can enable and maintain this integration successfully.

For further assistance, refer to the [Yodlee Developer Documentation](https://developer.yodlee.com/docs) or open an issue in the Maybe Finance repository.
