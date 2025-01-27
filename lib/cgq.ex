defmodule CGQ.Application do
  use Application

  @impl true
  def start(_type, _args) do
    case :cgq.main() do
      {:ok, _} -> 
        {:ok, self()}
      {:error, err} ->
        {:error, err}
    end
    
    System.halt(0)
  end
end
