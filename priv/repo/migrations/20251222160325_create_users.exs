defmodule TeslaMate.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def up do
    # Create users table in private schema
    execute("CREATE TABLE private.users (
      id SERIAL PRIMARY KEY,
      email VARCHAR(255),
      name VARCHAR(255),
      inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMP NOT NULL DEFAULT NOW()
    )")

    execute("CREATE UNIQUE INDEX users_email_index ON private.users (email) WHERE email IS NOT NULL")

    # Create a default user for existing installation
    execute("INSERT INTO private.users (email, name, inserted_at, updated_at) 
             VALUES ('default_user@teslamate.local', 'Default User', NOW(), NOW())")

    # Add user_id to tokens table
    execute("ALTER TABLE private.tokens ADD COLUMN user_id INTEGER")
    
    # Set default user for existing tokens
    execute("UPDATE private.tokens SET user_id = (SELECT id FROM private.users WHERE email = 'default_user@teslamate.local')")
    
    # Make user_id not null and add foreign key
    execute("ALTER TABLE private.tokens ALTER COLUMN user_id SET NOT NULL")
    execute("ALTER TABLE private.tokens ADD CONSTRAINT tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES private.users(id) ON DELETE CASCADE")
    execute("CREATE INDEX tokens_user_id_index ON private.tokens (user_id)")

    # Add user_id to cars table
    execute("ALTER TABLE cars ADD COLUMN user_id INTEGER")
    
    # Set default user for existing cars
    execute("UPDATE cars SET user_id = (SELECT id FROM private.users WHERE email = 'default_user@teslamate.local')")
    
    # Make user_id not null and add foreign key
    execute("ALTER TABLE cars ALTER COLUMN user_id SET NOT NULL")
    execute("ALTER TABLE cars ADD CONSTRAINT cars_user_id_fkey FOREIGN KEY (user_id) REFERENCES private.users(id) ON DELETE CASCADE")
    execute("CREATE INDEX cars_user_id_index ON cars (user_id)")
  end

  def down do
    # Remove user_id from cars
    execute("DROP INDEX IF EXISTS cars_user_id_index")
    execute("ALTER TABLE cars DROP CONSTRAINT IF EXISTS cars_user_id_fkey")
    execute("ALTER TABLE cars DROP COLUMN IF EXISTS user_id")

    # Remove user_id from tokens
    execute("DROP INDEX IF EXISTS tokens_user_id_index")
    execute("ALTER TABLE private.tokens DROP CONSTRAINT IF EXISTS tokens_user_id_fkey")
    execute("ALTER TABLE private.tokens DROP COLUMN IF EXISTS user_id")

    # Drop users table
    execute("DROP INDEX IF EXISTS users_email_index")
    execute("DROP TABLE IF EXISTS private.users")
  end
end
