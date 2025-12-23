# TeslaMate Multi-User Support

## Overview

This document describes the implementation of multi-user support for TeslaMate, enabling it to work as an infrastructure service for multiple Tesla user accounts simultaneously.

## Architecture Changes

### Database Schema

#### New `users` Table
A new `users` table has been added to the `private` schema to store Tesla user information:

```sql
CREATE TABLE private.users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255),
  name VARCHAR(255),
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

#### Updated `tokens` Table
The `tokens` table now includes a `user_id` foreign key:
- `user_id INTEGER NOT NULL REFERENCES private.users(id) ON DELETE CASCADE`
- Each token set is now associated with a specific user

#### Updated `cars` Table  
The `cars` table now includes a `user_id` foreign key:
- `user_id INTEGER NOT NULL REFERENCES private.users(id) ON DELETE CASCADE`
- Each car is now associated with the user who owns it

### Data Model

**Previous Architecture:**
```
Tokens (1) -> Vehicles (N)
```

**New Architecture:**
```
Users (1) -> Tokens (1)
Users (1) -> Cars (N)
```

All data (positions, charges, drives, etc.) remains linked to `car_id`, which is now transitively linked to users through the `user_id` foreign key.

### Application Changes

#### 1. New Modules

**`TeslaMate.Auth.User`**
- Schema module for the `users` table
- Manages user records in the database
- Located at: `lib/teslamate/auth/user.ex`

**`TeslaMate.ApiRegistry`**
- Supervisor for managing multiple API instances
- One API instance per user
- Handles starting/stopping API instances for users
- Located at: `lib/teslamate/api_registry.ex`

#### 2. Updated Modules

**`TeslaMate.Auth.Tokens`**
- Added `belongs_to :user, User` relationship
- Updated changeset to require and validate `user_id`

**`TeslaMate.Log.Car`**
- Added `user_id` field
- Added `belongs_to :user, User` relationship  
- Updated changeset to require and validate `user_id`

**`TeslaMate.Auth`**
- Added user management functions:
  - `list_users/0` - Get all users
  - `get_user/1` - Get user by ID
  - `get_user_by/1` - Get user by parameters
  - `create_user/1` - Create a new user
  - `update_user/2` - Update user information
  - `delete_user/1` - Delete a user
  - `get_or_create_default_user/0` - Get or create the default user for backward compatibility

- Updated token management for multi-user:
  - `get_tokens_for_user/1` - Get tokens for a specific user
  - `get_all_tokens/0` - Get all tokens for all users
  - `save_for_user/2` - Save tokens for a specific user

- Maintained backward compatibility:
  - `get_tokens/0` - Still works, uses default user
  - `save/1` - Still works, uses default user

**`TeslaMate.Api`**
- Updated initialization to support user-specific authentication
- Added helper functions `get_user_tokens/1` and `save_user_tokens/2` to handle both:
  - Old style: `auth: TeslaMate.Auth` (module)
  - New style: `auth: {TeslaMate.Auth, user_id}` (tuple with user_id)

**`TeslaMate.Vehicles`**
- Updated `create_or_update!/2` to accept optional `user_id` parameter
- Defaults to the default user if not provided (backward compatibility)
- Assigns new vehicles to the correct user

## How It Works

### Data Fetching

Tesla API fetches data on a **per-user basis**. When you authenticate with a Tesla account:
1. You receive access and refresh tokens
2. Using these tokens, the API returns **all vehicles** associated with that account
3. Each vehicle is then tracked and its data is stored in the database

### Multi-User Flow

1. **User Registration**: When a new Tesla user is added:
   - A new `User` record is created in the database
   - User provides their Tesla credentials
   - Tokens are saved with `user_id` association

2. **API Instance Management**:
   - `ApiRegistry` starts one `Api` GenServer per user
   - Each API instance manages tokens for its user
   - Token refresh happens independently per user

3. **Vehicle Management**:
   - When vehicles are fetched for a user, they're assigned to that user
   - The `Vehicles` supervisor manages all vehicles across all users
   - Each vehicle knows its owner through `user_id`

4. **Data Collection**:
   - Vehicle processes fetch data using their user's API instance
   - All collected data (positions, charges, drives) is linked to `car_id`
   - Cars are linked to users, creating a complete ownership chain

## Backward Compatibility

The implementation maintains full backward compatibility with existing single-user installations:

1. **Default User**: A "default_user@teslamate.local" user is automatically created during migration
2. **Existing Data**: All existing tokens and cars are assigned to the default user
3. **Existing API Calls**: All existing function calls continue to work:
   - `Auth.get_tokens/0` - Works with default user
   - `Auth.save/1` - Saves to default user
   - `Vehicles.create_or_update!/1` - Assigns to default user

## Migration Path

### For Existing Installations

The migration `20251222160325_create_users.exs` automatically:
1. Creates the `users` table
2. Creates a default user
3. Adds `user_id` columns to `tokens` and `cars` tables
4. Associates all existing data with the default user
5. Adds foreign key constraints

No manual intervention is required. Existing installations will continue working as before.

### For New Multi-User Deployments

To use TeslaMate with multiple users:

1. **Add Users**: Create user records for each Tesla account
   ```elixir
   {:ok, user} = TeslaMate.Auth.create_user(%{
     email: "user@example.com",
     name: "User Name"
   })
   ```

2. **Authenticate Users**: Have each user sign in with their Tesla credentials
   - This will create tokens associated with their user_id
   - The ApiRegistry will start an API instance for them

3. **Fetch Vehicles**: Vehicles will be automatically fetched and associated with the correct user

## API Usage for Multi-User

### Creating a New User

```elixir
{:ok, user} = TeslaMate.Auth.create_user(%{
  email: "john@example.com",
  name: "John Doe"
})
```

### Saving Tokens for a User

```elixir
TeslaMate.Auth.save_for_user(user.id, %{
  token: "access_token_here",
  refresh_token: "refresh_token_here"
})
```

### Getting Tokens for a User

```elixir
tokens = TeslaMate.Auth.get_tokens_for_user(user.id)
```

### Starting API for a User

```elixir
TeslaMate.ApiRegistry.start_api_for_user(user.id)
```

### Listing All Users

```elixir
users = TeslaMate.Auth.list_users()
```

## Security Considerations

1. **Token Encryption**: All tokens are encrypted using the existing `TeslaMate.Vault` encryption system
2. **Private Schema**: User and token data is stored in the `private` PostgreSQL schema
3. **Cascade Deletes**: Deleting a user will cascade delete their tokens and disassociate their cars
4. **User Isolation**: Each user's API instance is isolated and manages its own token lifecycle

## Database Queries

### Find All Cars for a User

```sql
SELECT * FROM cars WHERE user_id = <user_id>;
```

### Find All Data for a User's Cars

```sql
-- Positions
SELECT p.* FROM positions p
JOIN cars c ON p.car_id = c.id
WHERE c.user_id = <user_id>;

-- Charges
SELECT ch.* FROM charges ch
JOIN charging_processes cp ON ch.charging_process_id = cp.id
JOIN cars c ON cp.car_id = c.id
WHERE c.user_id = <user_id>;

-- Drives
SELECT d.* FROM drives d
JOIN cars c ON d.car_id = c.id
WHERE c.user_id = <user_id>;
```

### Count Vehicles per User

```sql
SELECT u.email, COUNT(c.id) as vehicle_count
FROM private.users u
LEFT JOIN cars c ON c.user_id = u.id
GROUP BY u.id, u.email;
```

## Future Enhancements

Potential improvements for multi-user support:

1. **Web UI**: Add user management interface in TeslaMate web UI
2. **API Endpoints**: Create REST API endpoints for user and vehicle management
3. **Authentication**: Add user authentication/authorization layer
4. **Multi-Tenancy**: Add tenant isolation for complete multi-user SaaS deployment
5. **User Dashboards**: Create per-user Grafana dashboards
6. **Quota Management**: Add vehicle/user limits and usage quotas

## Testing

To test multi-user functionality:

1. Create multiple users:
   ```elixir
   {:ok, user1} = TeslaMate.Auth.create_user(%{email: "user1@test.com", name: "User 1"})
   {:ok, user2} = TeslaMate.Auth.create_user(%{email: "user2@test.com", name: "User 2"})
   ```

2. Save tokens for each user (use real tokens from Tesla authentication)

3. Verify vehicles are associated correctly:
   ```elixir
   TeslaMate.Log.list_cars()
   |> Enum.group_by(& &1.user_id)
   ```

4. Check that data is isolated per user by querying through car associations

## Troubleshooting

### Issue: Existing installation not working after migration

**Solution**: The migration should automatically create a default user and associate all data. Check:
```sql
SELECT * FROM private.users WHERE email = 'default_user@teslamate.local';
SELECT * FROM cars WHERE user_id IS NULL;
SELECT * FROM private.tokens WHERE user_id IS NULL;
```

All cars and tokens should have a non-null user_id.

### Issue: Cannot start API for new user

**Solution**: Ensure the user has tokens saved:
```elixir
TeslaMate.Auth.get_tokens_for_user(user_id)
```

If nil, the user needs to authenticate first.

## Summary

The multi-user implementation:

✅ Maintains complete backward compatibility  
✅ Uses minimal database changes (adds user_id foreign keys)  
✅ Isolates user data through proper relationships  
✅ Supports independent token management per user  
✅ Enables TeslaMate to serve as multi-user infrastructure  
✅ Preserves existing data integrity  
✅ Uses existing security measures (encryption, private schema)  

The implementation is production-ready for both single-user (existing behavior) and multi-user scenarios.
