defmodule TeslaMate.Auth.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Auth.Tokens
  alias TeslaMate.Log.Car

  @schema_prefix :private

  schema "users" do
    field :email, :string
    field :name, :string

    has_many :tokens, Tokens
    has_many :cars, Car

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
  end
end
