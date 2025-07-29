# Yodlee Integration: Local Development Setup Guide

This guide provides detailed instructions for setting up and testing the Yodlee integration in a local development environment for Maybe Finance.

## Docker vs. Native Rails Setup

Maybe Finance supports both Docker-based and native Rails development environments, but there are some important considerations for the Yodlee integration:

### Docker Setup (Recommended)

The Docker setup is the recommended approach for local development as it provides a consistent environment and simplifies dependency management:

- Environment variables are passed through the Docker Compose configuration
- Ensures consistent behavior across different development machines
- Simplifies setup of dependent services (PostgreSQL, Redis, etc.)

### Native Rails Setup

If you prefer to run Rails directly on your machine:

- You'll need to manually install all dependencies (PostgreSQL, Redis, etc.)
- Environment variables need to be loaded through your shell or a tool like `dotenv`
- You may need to adjust paths and configurations to match your local setup

## Environment File Configuration

### `.env.local` vs `.env`

Maybe Finance uses two primary environment files:

- **`.env`**: Used for production/deployment settings and shared configuration
- **`.env.local`**: Used for local development and not committed to version control

For Yodlee integration in local development:

1. Create a copy of `.env.local.example` as `.env.local`
2. Add your Yodlee credentials to `.env.local`
3. Do NOT add your credentials to `.env` as it may be committed to version control

Example `.env.local` configuration:

```
# Yodlee Configuration
YODLEE_CLIENT_ID=your_sandbox_client_id
YODLEE_SECRET=your_sandbox_secret
YODLEE_BASE=https://development.api.envestnet.com/ysl
YODLEE_FASTLINK_URL=https://development.fastlink.envestnet.com
YODLEE_COBRAND_NAME=your_cobrand_name
ENABLE_YODLEE=true
```

### Docker Environment Loading

When using Docker, make sure your `docker-compose.yml` or `compose.yml` is configured to load `.env.local`:

```yaml
services:
  web:
    env_file:
      - .env
      - .env.local  # Make sure this is included
```

## Rails Credentials and Encryption

### Sensitive Data Handling

Maybe Finance uses Rails' built-in encryption for sensitive credentials:

1. **Environment Variables**: Most configuration (including Yodlee) uses environment variables
2. **Rails Credentials**: Some sensitive data may be stored in `config/credentials.yml.enc`
3. **Active Record Encryption**: Database fields like `user_session` in `YodleeItem` are encrypted

### Active Record Encryption

The `YodleeItem` model includes encryption for sensitive fields:

```ruby
if Rails.application.credentials.active_record_encryption.present?
  encrypts :user_session, deterministic: true
end
```

This ensures that Yodlee tokens are stored securely in your development database.

### Local Development Encryption Keys

For local development, Maybe Finance can generate encryption keys based on your `SECRET_KEY_BASE`. You don't need to manually set up encryption keys unless you want to customize them.

If you need to customize encryption keys, you can add them to `.env.local`:

```
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=your_primary_key
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=your_deterministic_key
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=your_derivation_salt
```

## Local Testing with Yodlee Sandbox

### Step 1: Register for Yodlee Developer Account

1. Visit https://developer.yodlee.com and register for a free account
2. Verify your email and log in to the dashboard
3. Navigate to **API Keys** and copy your Cobrand Client ID and Secret
4. Note your developer username as your Cobrand Name

### Step 2: Configure FastLink

1. In the Yodlee Developer dashboard, go to **FastLink Configuration**
2. Click "Create new configuration"
3. Enter a name (e.g., "Maybe Finance Development")
4. Choose the "Aggregation" template
5. Publish to the Development environment

### Step 3: Configure Local Environment

1. Create or update your `.env.local` file with your Yodlee credentials:

```
YODLEE_CLIENT_ID=your_sandbox_client_id
YODLEE_SECRET=your_sandbox_secret
YODLEE_COBRAND_NAME=your_developer_username
ENABLE_YODLEE=true
```

2. Use the default sandbox URLs:

```
YODLEE_BASE=https://development.api.envestnet.com/ysl
YODLEE_FASTLINK_URL=https://development.fastlink.envestnet.com
```

### Step 4: Run Database Migrations

If you haven't already, run the migrations to create the necessary tables:

```bash
# For Docker setup
docker-compose exec web rails db:migrate

# For native Rails setup
rails db:migrate
```

### Step 5: Restart Your Application

```bash
# For Docker setup
docker-compose restart web

# For native Rails setup
rails server
```

### Step 6: Test the Integration

1. Navigate to http://localhost:3000/accounts
2. Click "New account"
3. You should see "Link account via Yodlee" as an option
4. Click it to launch the Yodlee FastLink widget
5. Use Yodlee sandbox credentials to test the connection

#### Sandbox Test Credentials

Yodlee provides sandbox credentials for testing. Common test credentials include:

- **Bank Name**: "Dag Site"
- **Username**: "DAG.Site.1"
- **Password**: "site1234"

More test credentials can be found in the Yodlee Developer documentation.

## Common Issues for Local Development

### CORS Issues with FastLink

**Problem**: FastLink widget fails to load due to CORS restrictions

**Solution**:
- Ensure you're running on `localhost` or a domain allowed by Yodlee
- Check browser console for specific CORS errors
- If needed, add your local domain to the FastLink configuration in Yodlee dashboard

### Authentication Failures

**Problem**: "Invalid credentials" or authentication errors

**Solution**:
- Verify your `YODLEE_CLIENT_ID` and `YODLEE_SECRET` are correct
- Ensure `YODLEE_COBRAND_NAME` matches your developer username
- Check Rails logs for detailed API error messages
- Verify your Yodlee account is active and not locked

### Webhook Issues

**Problem**: Webhooks don't work in local development

**Solution**:
- Yodlee requires public HTTPS endpoints for webhooks
- For local testing, use a tool like ngrok to expose your local server:
  ```bash
  ngrok http 3000
  ```
- Update your webhook URL in the Yodlee dashboard to your ngrok URL

### Database Encryption Errors

**Problem**: Errors related to encrypted fields

**Solution**:
- Ensure `SECRET_KEY_BASE` is set in your environment
- If you've changed encryption keys, you may need to reset the database
- For persistent issues, explicitly set encryption keys in `.env.local`

### Missing Transactions

**Problem**: Accounts connect but no transactions appear

**Solution**:
- Sandbox accounts may have limited transaction data
- Check the date range for transaction imports (defaults to 90 days)
- Manually trigger a sync from the UI
- Check Rails logs for transaction processing errors

## Quick Testing Steps

Use this checklist to quickly verify your Yodlee integration:

1. **Verify Configuration**:
   - Check that `ENABLE_YODLEE=true` in `.env.local`
   - Confirm all Yodlee credentials are set
   - Restart the application to load new environment variables

2. **Test Account Connection**:
   ```
   Accounts → New account → Link account via Yodlee
   ```

3. **Test FastLink Widget**:
   - Widget should load without errors
   - Use sandbox credentials to connect a test account
   - After successful connection, you should be redirected back to Maybe

4. **Verify Account Import**:
   - Connected accounts should appear in the Accounts list
   - Account details should display correctly

5. **Test Transaction Import**:
   - Click "Sync" on the Yodlee item
   - Transactions should appear in the account activity
   - Categories should be mapped according to `config/yodlee_categories.yml`

6. **Debug Issues**:
   - Check Rails logs for API errors: `docker-compose logs -f web`
   - Check browser console for JavaScript errors
   - Verify network requests to Yodlee APIs succeed

## Conclusion

With this setup, you should be able to develop and test the Yodlee integration locally. Remember that the Yodlee sandbox environment has limitations compared to the production environment, so some features may behave differently.

For further assistance, refer to the [Yodlee Developer Documentation](https://developer.yodlee.com/docs) or the main [Yodlee Integration Implementation](./yodlee-integration-implementation.md) document.
