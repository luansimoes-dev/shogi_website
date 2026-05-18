defmodule ShogiWeb.Layouts do
  use ShogiWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <meta name="viewport" content="width=device-width, initial-scale=1" />

        <title>Shogi</title>

        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
        </script>
      </head>

      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <main class="min-h-screen bg-zinc-100 text-zinc-900">
      <header class="border-b bg-white px-8 py-4">
        <div class="flex items-center justify-between">
          <a href={~p"/"} class="text-xl font-bold">
            Shogi
          </a>

          <span class="text-sm text-zinc-500">
            MVP
          </span>
        </div>
      </header>

      <section class="p-8">
        <%= @inner_content %>
      </section>
    </main>
    """
  end
end
