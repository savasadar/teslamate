# Multi-User Support Implementation Summary

## Question: Is data fetching per-car or per-user?

**Answer: Data fetching is PER-USER based.**

When you authenticate with Tesla's API:
1. You provide credentials (email/password or tokens) for a Tesla account
2. Tesla returns an access token and refresh token
3. Using these tokens, the API call to `/api/1/products` returns **ALL vehicles** associated with that Tesla account
4. Each vehicle in the response contains vehicle data (id, vin, vehicle_id, name, etc.)

**This means:**
- One user (Tesla account) can have multiple vehicles
- One API call with user's tokens returns all their vehicles
- Each vehicle then gets polled individually for real-time data
- But the initial vehicle list and authentication is USER-based, not CAR-based

## Implementation Changes

### Database Level

1. **Created `users` table** in private schema
   - Stores Tesla user information (email, name)
   - Primary key: `id`

2. **Added `user_id` to `tokens` table**
   - Each set of tokens belongs to one user
   - Foreign key constraint to users table

3. **Added `user_id` to `cars` table**
   - Each car belongs to one user
   - Foreign key constraint to users table

### Application Level

1. **Auth Module** (`lib/teslamate/auth.ex`)
   - Added user CRUD operations
   - Modified token operations to support per-user tokens
   - Maintained backward compatibility with default user

2. **New User Schema** (`lib/teslamate/auth/user.ex`)
   - Represents users in the database
   - Has many tokens and cars

3. **Updated Tokens Schema** (`lib/teslamate/auth/tokens.ex`)
   - Added belongs_to relationship with User
   - Requires user_id in changeset

4. **Updated Car Schema** (`lib/teslamate/log/car.ex`)
   - Added belongs_to relationship with User
   - Requires user_id in changeset

5. **API Module Updates** (`lib/teslamate/api.ex`)
   - Support for user-specific auth dependency
   - Helper functions to handle both old and new auth styles
   - Backward compatible with single-user flow

6. **Vehicles Module Updates** (`lib/teslamate/vehicles.ex`)
   - create_or_update! accepts optional user_id
   - Defaults to default user for backward compatibility

7. **New ApiRegistry** (`lib/teslamate/api_registry.ex`)
   - Supervisor for managing multiple API instances
   - One API instance per user
   - Start/stop API instances per user

## Backward Compatibility

✅ **100% backward compatible** with existing installations:

1. Migration automatically creates a default user
2. All existing tokens and cars are assigned to default user
3. All existing API calls work unchanged
4. No configuration changes required
5. Single-user installations continue working as before

## How Multi-User Works

### For Single User (Current Behavior - Still Works)
```
User logs in → Tokens saved → Vehicles fetched → All cars tracked
```

### For Multiple Users (New Capability)
```
User 1 logs in → Tokens saved with user_id=1 → Vehicles fetched → Cars assigned to user 1
User 2 logs in → Tokens saved with user_id=2 → Vehicles fetched → Cars assigned to user 2
Each user's cars are tracked independently using their own tokens
```

## Data Isolation

All data remains isolated through the car relationship:
```
User → Cars → (Positions, Charges, Drives, etc.)
```

To get all data for a user:
1. Find cars where `user_id = X`
2. Find all positions/charges/drives where `car_id IN (user X's car IDs)`

## Key Benefits

1. **Multiple Tesla accounts** can be tracked in one TeslaMate instance
2. **Each user's data is isolated** through database relationships
3. **Independent token management** - each user's tokens refresh independently
4. **Backward compatible** - existing installations work unchanged
5. **Production ready** - uses existing security (encryption, private schema)

## Files Changed

1. `priv/repo/migrations/20251222160325_create_users.exs` - Database migration
2. `lib/teslamate/auth/user.ex` - New user schema
3. `lib/teslamate/auth/tokens.ex` - Updated to include user relationship
4. `lib/teslamate/log/car.ex` - Updated to include user relationship
5. `lib/teslamate/auth.ex` - Added user management and per-user token operations
6. `lib/teslamate/api.ex` - Support for user-specific authentication
7. `lib/teslamate/api_registry.ex` - New module for managing multiple API instances
8. `lib/teslamate/vehicles.ex` - Updated to assign cars to users
9. `MULTI_USER_SUPPORT.md` - Comprehensive English documentation
10. `COKLU_KULLANICI_DESTEGI.md` - Comprehensive Turkish documentation

## Next Steps for Full Multi-User Deployment

To use this as a multi-user service:

1. **Add Web UI** for user management (future enhancement)
2. **Create REST API** endpoints for user/vehicle operations (future enhancement)
3. **Add authentication layer** for user access control (future enhancement)

The database and core application changes are complete and ready for use.
