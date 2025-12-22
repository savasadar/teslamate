# API Usage Examples for Multi-User Support

This document provides practical examples of using the multi-user support features in TeslaMate.

## Creating and Managing Users

### Create a New User

```elixir
# In IEx console or in application code
{:ok, user} = TeslaMate.Auth.create_user(%{
  email: "john.doe@example.com",
  name: "John Doe"
})

# Returns:
# {:ok, %TeslaMate.Auth.User{
#   id: 2,
#   email: "john.doe@example.com",
#   name: "John Doe",
#   inserted_at: ~N[2025-12-22 16:00:00],
#   updated_at: ~N[2025-12-22 16:00:00]
# }}
```

### List All Users

```elixir
users = TeslaMate.Auth.list_users()

# Returns list of users:
# [
#   %TeslaMate.Auth.User{id: 1, email: "default_user@teslamate.local", ...},
#   %TeslaMate.Auth.User{id: 2, email: "john.doe@example.com", ...}
# ]
```

### Get a Specific User

```elixir
# By ID
user = TeslaMate.Auth.get_user(2)

# By email
user = TeslaMate.Auth.get_user_by(email: "john.doe@example.com")
```

### Update a User

```elixir
{:ok, user} = TeslaMate.Auth.get_user(2)
{:ok, updated_user} = TeslaMate.Auth.update_user(user, %{name: "John D."})
```

### Delete a User

```elixir
{:ok, user} = TeslaMate.Auth.get_user(2)
{:ok, deleted_user} = TeslaMate.Auth.delete_user(user)

# Note: This will cascade delete:
# - All tokens for this user
# - All cars will have their user_id set to null (or handle as needed)
```

## Managing Tokens

### Save Tokens for a Specific User

```elixir
# After user authenticates with Tesla and you get tokens
user_id = 2

TeslaMate.Auth.save_for_user(user_id, %{
  token: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  refresh_token: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
})

# Returns: :ok
```

### Get Tokens for a Specific User

```elixir
tokens = TeslaMate.Auth.get_tokens_for_user(2)

# Returns:
# %TeslaMate.Auth.Tokens{
#   id: 2,
#   user_id: 2,
#   access: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
#   refresh: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
#   inserted_at: ~N[2025-12-22 16:00:00],
#   updated_at: ~N[2025-12-22 16:00:00]
# }
```

### Get All Tokens (for all users)

```elixir
all_tokens = TeslaMate.Auth.get_all_tokens()

# Returns list of all token records across all users
```

## Managing API Instances

### Start API Instance for a User

```elixir
:ok = TeslaMate.ApiRegistry.start_api_for_user(2)

# This starts a dedicated API GenServer for user 2
# The API instance will manage token refresh automatically
```

### Get API Process Name for a User

```elixir
{:ok, api_name} = TeslaMate.ApiRegistry.get_api(2)

# Returns: {:ok, :"TeslaMate.Api.User2"}
# You can use this name to make API calls specific to this user
```

### Stop API Instance for a User

```elixir
:ok = TeslaMate.ApiRegistry.stop_api_for_user(2)

# Stops the API GenServer for user 2
```

## Working with Vehicles

### Create or Update Vehicle with User Assignment

```elixir
# Vehicle data from Tesla API
vehicle = %TeslaApi.Vehicle{
  id: 123456789,
  vehicle_id: 987654321,
  vin: "5YJ3E1EA1KF000001",
  display_name: "Model 3"
}

# Assign to specific user
user_id = 2
car = TeslaMate.Vehicles.create_or_update!(vehicle, user_id)

# Or let it use default user (backward compatible)
car = TeslaMate.Vehicles.create_or_update!(vehicle)
```

## Database Queries

### Find All Cars for a User

```elixir
# Using Ecto
import Ecto.Query
alias TeslaMate.{Repo, Log.Car}

user_id = 2
cars = Repo.all(from c in Car, where: c.user_id == ^user_id)
```

### Find All Positions for a User's Cars

```elixir
import Ecto.Query
alias TeslaMate.{Repo, Log.Car, Log.Position}

user_id = 2

positions = 
  Repo.all(
    from p in Position,
    join: c in Car, on: p.car_id == c.id,
    where: c.user_id == ^user_id,
    order_by: [desc: p.date]
  )
```

### Count Vehicles per User

```elixir
import Ecto.Query
alias TeslaMate.{Repo, Auth.User, Log.Car}

user_vehicle_counts = 
  Repo.all(
    from u in User,
    left_join: c in Car, on: c.user_id == u.id,
    group_by: u.id,
    select: {u.email, count(c.id)}
  )

# Returns: [{"default_user@teslamate.local", 2}, {"john.doe@example.com", 1}]
```

## Complete Multi-User Workflow Example

```elixir
# Step 1: Create a new user
{:ok, user} = TeslaMate.Auth.create_user(%{
  email: "jane@example.com",
  name: "Jane Smith"
})

# Step 2: User authenticates with Tesla (this would happen through a web interface)
# For this example, assume we already have tokens from Tesla OAuth flow
tesla_tokens = %{
  token: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  refresh_token: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}

# Step 3: Save tokens for the user
:ok = TeslaMate.Auth.save_for_user(user.id, tesla_tokens)

# Step 4: Start API instance for the user
:ok = TeslaMate.ApiRegistry.start_api_for_user(user.id)

# Step 5: Fetch vehicles for this user (this would happen automatically in TeslaMate)
# But here's how you would do it manually:
{:ok, api_name} = TeslaMate.ApiRegistry.get_api(user.id)
{:ok, vehicles} = TeslaMate.Api.list_vehicles(api_name)

# Step 6: Create or update vehicles with user assignment
Enum.each(vehicles, fn vehicle ->
  TeslaMate.Vehicles.create_or_update!(vehicle, user.id)
end)

# Step 7: Now vehicles are being tracked for this user!
# Check the user's cars:
import Ecto.Query
alias TeslaMate.{Repo, Log.Car}

cars = Repo.all(from c in Car, where: c.user_id == ^user.id)
IO.inspect(cars, label: "Jane's Cars")
```

## Backward Compatibility Examples

### Single-User Flow (Original Behavior)

```elixir
# These all still work and use the default user automatically:

# Get tokens (uses default user)
tokens = TeslaMate.Auth.get_tokens()

# Save tokens (uses default user)
:ok = TeslaMate.Auth.save(%{
  token: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  refresh_token: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
})

# List vehicles (uses default API instance)
{:ok, vehicles} = TeslaMate.Api.list_vehicles()

# Create/update vehicle (assigns to default user)
car = TeslaMate.Vehicles.create_or_update!(vehicle)
```

## Error Handling

### User Not Found

```elixir
case TeslaMate.Auth.get_user(999) do
  nil -> IO.puts("User not found")
  user -> IO.inspect(user)
end
```

### No Tokens for User

```elixir
case TeslaMate.Auth.get_tokens_for_user(2) do
  nil -> IO.puts("User needs to authenticate with Tesla")
  tokens -> IO.puts("User has tokens")
end
```

### API Instance Not Running

```elixir
case TeslaMate.ApiRegistry.get_api(2) do
  {:ok, api_name} -> IO.puts("API running")
  {:error, :not_found} -> 
    IO.puts("Starting API for user...")
    TeslaMate.ApiRegistry.start_api_for_user(2)
end
```

## Testing Multi-User Setup

```elixir
# Create test users
{:ok, user1} = TeslaMate.Auth.create_user(%{email: "test1@example.com", name: "Test 1"})
{:ok, user2} = TeslaMate.Auth.create_user(%{email: "test2@example.com", name: "Test 2"})

# Verify users are isolated
import Ecto.Query
alias TeslaMate.{Repo, Log.Car}

user1_cars = Repo.all(from c in Car, where: c.user_id == ^user1.id)
user2_cars = Repo.all(from c in Car, where: c.user_id == ^user2.id)

IO.puts("User 1 has #{length(user1_cars)} cars")
IO.puts("User 2 has #{length(user2_cars)} cars")

# Verify no overlap
car_ids_1 = Enum.map(user1_cars, & &1.id) |> MapSet.new()
car_ids_2 = Enum.map(user2_cars, & &1.id) |> MapSet.new()

if MapSet.intersection(car_ids_1, car_ids_2) |> MapSet.size() == 0 do
  IO.puts("✓ Cars are properly isolated per user")
else
  IO.puts("✗ ERROR: Car ownership overlap detected!")
end
```

## Notes

- Always ensure a user has valid tokens before starting their API instance
- Token refresh happens automatically per user
- Each user's API instance is independent and isolated
- Database constraints ensure data integrity (cascade deletes, foreign keys)
- All tokens are encrypted using TeslaMate's Vault system
- User and token data is stored in the PostgreSQL private schema for additional security
