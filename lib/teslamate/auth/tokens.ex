defmodule TeslaMate.Auth.Tokens do
  use Ecto.Schema

  import Ecto.Changeset

  alias TeslaMate.Vault.Encrypted
  alias TeslaMate.Auth.User

  @schema_prefix :private

  schema "tokens" do
    field :refresh, Encrypted.Binary, redact: true
    field :access, Encrypted.Binary, redact: true

    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(tokens, attrs) do
    tokens
    |> cast(attrs, [:access, :refresh, :user_id])
    |> validate_required([:access, :refresh, :user_id])
    |> foreign_key_constraint(:user_id)
  end
end
