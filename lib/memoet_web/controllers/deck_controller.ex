defmodule MemoetWeb.DeckController do
  use MemoetWeb, :controller

  alias Memoet.Decks
  alias Memoet.Decks.Deck
  alias Memoet.Notes
  alias Memoet.Cards

  @spec index(Plug.Conn.t(), map) :: Plug.Conn.t()
  def index(conn, _params) do
    user = Pow.Plug.current_user(conn)
    %{entries: decks} = Decks.list_decks(%{"user_id" => user.id})
    %{entries: public_decks} = Decks.list_decks(%{"public" => true})
    render(conn, "index.html", decks: decks, public_decks: public_decks)
  end

  @spec public(Plug.Conn.t(), map) :: Plug.Conn.t()
  def public(conn, _params) do
    %{entries: public_decks, metadata: metadata} = Decks.list_decks(%{"public" => true})
    render(conn, "public.html", public_decks: public_decks, metadata: metadata)
  end

  @spec create(Plug.Conn.t(), map) :: Plug.Conn.t()
  def create(conn, deck_params) do
    user = Pow.Plug.current_user(conn)

    params =
      deck_params
      |> Map.merge(%{
        "user_id" => user.id
      })

    case Decks.create_deck(params) do
      {:ok, %Deck{} = deck} ->
        conn
        |> put_flash(:info, "Create deck \"" <> deck.name <> "\" success!")
        |> redirect(to: "/decks/" <> deck.id)

      {:error, changeset} ->
        conn
        |> render("new.html", changeset: changeset)
    end
  end

  @spec show(Plug.Conn.t(), map) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    user = Pow.Plug.current_user(conn)
    deck = Decks.get_deck!(id)

    if (user == nil or deck.user_id != user.id) and not deck.public do
      redirect(conn, to: "/decks")
    else
      notes = Notes.list_notes(deck.id, %{})
      render(conn, "show.html", deck: deck, notes: notes)
    end
  end

  @spec new(Plug.Conn.t(), map) :: Plug.Conn.t()
  def new(conn, _params) do
    render(conn, "new.html")
  end

  @spec edit(Plug.Conn.t(), map) :: Plug.Conn.t()
  def edit(conn, %{"id" => id}) do
    user = Pow.Plug.current_user(conn)
    deck = Decks.get_deck!(id, user.id)
    render(conn, "edit.html", deck: deck)
  end

  @spec delete(Plug.Conn.t(), map) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    user = Pow.Plug.current_user(conn)
    Decks.delete_deck!(id, user.id)

    conn
    |> put_flash(:info, "Delete success!")
    |> redirect(to: "/decks")
  end

  @spec clone(Plug.Conn.t(), map) :: Plug.Conn.t()
  def clone(conn, %{"id" => id}) do
    user = Pow.Plug.current_user(conn)
    deck = Decks.get_deck!(id)

    if deck.user_id == user.id or (deck.user_id != user.id and not deck.public) do
      conn
      |> put_flash(:error, "Clone deck failed!")
      |> redirect(to: "/decks")
    else
      params = from_struct(deck)
               |> Map.merge(%{
                 "user_id" => user.id,
                 "source_id" => deck.id,
               })
      case Decks.create_deck(params) do
        {:ok, %Deck{} = new_deck} ->
          for note <- Notes.list_notes(deck.id) do
            params = from_struct(note)
                     |> Map.merge(%{
                       "options" => Enum.map(note.options, fn o -> from_struct(o) end),
                       "deck_id" => new_deck.id,
                       "user_id" => user.id,
                     })

            Notes.create_note_with_card_transaction(params)
            |> Memoet.Repo.transaction()
          end

          conn
          |> put_flash(:info, "Clone deck success!")
          |> redirect(to: "/decks/" <> new_deck.id)

        {:error, _changeset} ->
          conn
          |> put_flash(:error, "Clone deck failed!")
          |> redirect(to: "/decks")
      end
    end
  end

  defp from_struct(struct) do
    Map.from_struct(struct)
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
    |> Enum.into(%{})
  end

  @spec update(Plug.Conn.t(), map) :: Plug.Conn.t()
  def update(conn, %{"id" => id} = deck_params) do
    user = Pow.Plug.current_user(conn)
    deck = Decks.get_deck!(id, user.id)

    case Decks.update_deck(deck, deck_params) do
      {:ok, %Deck{} = deck} ->
        conn
        |> put_flash(:info, "Update deck success!")
        |> redirect(to: "/decks/" <> deck.id)

      {:error, changeset} ->
        conn
        |> render("edit.html", changeset: changeset)
    end
  end

  @spec due(Plug.Conn.t(), map) :: Plug.Conn.t()
  def due(conn, %{"id" => deck_id} = _params) do
    user = Pow.Plug.current_user(conn)
    deck = Decks.get_deck!(deck_id, user.id)
    due_cards = Cards.due_cards(user.id, %{deck_id: deck_id})

    case due_cards do
      [] ->
        conn
        |> render("review.html", card: nil, deck: deck)

      [card | _] ->
        conn
        |> render("review.html", card: card, deck: deck)
    end
  end

  @spec review(Plug.Conn.t(), map) :: Plug.Conn.t()
  def review(conn, %{"id" => _deck_id, "card_id" => card_id, "answer" => choice} = _params) do
    user = Pow.Plug.current_user(conn)
    card = Cards.get_card!(card_id, user.id)

    Cards.answer_card(card, choice)

    conn
    |> redirect(to: Routes.review_card_path(conn, :due, %Deck{id: card.deck_id}))
  end
end
