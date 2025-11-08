defmodule Kadi.TelemetryTest do
  use Kadi.DataCase

  alias Kadi.CardGames
  alias Kadi.AccountsFixtures

  setup do
    test_pid = self()

    # Attach telemetry handler that sends events to test process
    :telemetry.attach_many(
      "test-king-telemetry",
      [
        [:kadi, :king, :direction_change],
        [:kadi, :king, :cardless_entered],
        [:kadi, :king, :anomaly_skip]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    # Clean up handler after test
    on_exit(fn -> :telemetry.detach("test-king-telemetry") end)

    :ok
  end

  describe "cardless telemetry events" do
    @tag :phase6
    @tag :telemetry
    test "T043: emits cardless_entered event when player plays King as last card" do
      # 1. Setup game with 2 players
      player1 = AccountsFixtures.player_fixture()
      player2 = AccountsFixtures.player_fixture(%{email: "telemetry@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "telemetry-cardless"})

      CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      # 2. Setup: Make current player have only 1 card (a King matching top card)
      current_player_id = game_session.current_turn_player_id

      game_session =
        Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      top_card = game_session.top_card

      # Find King matching top card suit
      king_deck_card =
        Enum.find(game_session.deck.deck_cards, fn dc ->
          dc.card.rank == "king" and dc.card.suit == top_card.suit
        end)

      king_card = king_deck_card.card

      # Get all player's cards
      player_cards =
        game_session.deck.deck_cards
        |> Enum.filter(&(&1.location_type == "player_hand" and &1.player_id == current_player_id))

      # Remove all cards except the King
      cards_to_remove =
        player_cards
        |> Enum.reject(&(&1.id == king_deck_card.id))

      cards_to_remove
      |> Enum.with_index()
      |> Enum.each(fn {dc, idx} ->
        Repo.update!(
          Ecto.Changeset.change(dc, %{
            location_type: "deck",
            player_id: nil,
            order_index: 900 + idx
          })
        )
      end)

      # Ensure the King is in player's hand
      Repo.update!(
        Ecto.Changeset.change(king_deck_card, %{
          location_type: "player_hand",
          player_id: current_player_id,
          order_index: nil
        })
      )

      # Reload to get fresh state
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # 3. Play the King (last card) - this should emit telemetry
      {:ok, _updated_game} =
        CardGames.play_cards(game_session, current_player_id, [king_card.id])

      # 4. Assert telemetry event was received
      assert_receive {:telemetry_event, [:kadi, :king, :cardless_entered], _measurements,
                      metadata}

      # 5. Verify metadata contents
      assert metadata.game_id == game_session.id
      assert metadata.player_id == current_player_id
      assert metadata.reason == "king_last_card"
      assert metadata.card_id == king_card.id
      assert %DateTime{} = metadata.timestamp

      IO.puts("✓ T043: Telemetry event emitted when player becomes cardless")
    end
  end

  describe "direction change telemetry events" do
    @tag :phase5
    @tag :telemetry
    test "T018: emits direction_change event when King is played" do
      # 1. Setup game with 3 players
      player1 = AccountsFixtures.player_fixture()
      player2 = AccountsFixtures.player_fixture(%{email: "player2@example.com"})
      player3 = AccountsFixtures.player_fixture(%{email: "player3@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "telemetry-direction"})

      CardGames.join_game_session(player2, game_session.id)
      CardGames.join_game_session(player3, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      # Verify initial direction
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)
      initial_direction = game_session.direction
      assert initial_direction == "clockwise"

      # 2. Setup: Give current player a King matching top card
      current_player_id = game_session.current_turn_player_id

      game_session =
        Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      top_card = game_session.top_card

      # Find King matching top card
      king_deck_card =
        Enum.find(game_session.deck.deck_cards, fn dc ->
          dc.card.rank == "king" and dc.card.suit == top_card.suit
        end)

      # Move King to current player's hand if not already there
      if king_deck_card.player_id != current_player_id do
        Repo.update!(
          Ecto.Changeset.change(king_deck_card, %{
            location_type: "player_hand",
            player_id: current_player_id,
            order_index: nil
          })
        )
      end

      king_card = king_deck_card.card

      # Reload
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # 3. Play the King - should emit direction_change event
      {:ok, updated_game} =
        CardGames.play_cards(game_session, current_player_id, [king_card.id])

      # 4. Assert telemetry event was received
      assert_receive {:telemetry_event, [:kadi, :king, :direction_change], _measurements,
                      metadata}

      # 5. Verify metadata contents
      assert metadata.game_id == game_session.id
      assert metadata.player_id == current_player_id
      assert metadata.previous_direction == "clockwise"
      assert metadata.new_direction == "counter_clockwise"
      assert metadata.card_id == king_card.id
      assert is_boolean(metadata.neutral)
      assert metadata.neutral == false

      # Verify direction actually changed
      assert updated_game.direction == "counter_clockwise"

      IO.puts("✓ T018: Telemetry event emitted on direction change")
    end

    @tag :phase5
    @tag :telemetry
    test "T018b: direction_change event marks 2-player games as neutral" do
      # 1. Setup 2-player game
      player1 = AccountsFixtures.player_fixture()
      player2 = AccountsFixtures.player_fixture(%{email: "player2-neutral@example.com"})

      {:ok, game_session} =
        CardGames.create_game_session(player1, %{short_code: "telemetry-neutral"})

      CardGames.join_game_session(player2, game_session.id)
      {:ok, game_session} = CardGames.start_game(game_session)

      # 2. Setup: Give current player a King
      current_player_id = game_session.current_turn_player_id

      game_session =
        Repo.preload(game_session, [:top_card, deck: [deck_cards: :card]], force: true)

      top_card = game_session.top_card

      king_deck_card =
        Enum.find(game_session.deck.deck_cards, fn dc ->
          dc.card.rank == "king" and dc.card.suit == top_card.suit
        end)

      if king_deck_card.player_id != current_player_id do
        Repo.update!(
          Ecto.Changeset.change(king_deck_card, %{
            location_type: "player_hand",
            player_id: current_player_id,
            order_index: nil
          })
        )
      end

      king_card = king_deck_card.card
      game_session = Repo.get!(Kadi.Games.GameSession, game_session.id)

      # 3. Play the King in 2-player game
      {:ok, _updated_game} =
        CardGames.play_cards(game_session, current_player_id, [king_card.id])

      # 4. Assert event marks as neutral (direction change has no effect in 2-player)
      assert_receive {:telemetry_event, [:kadi, :king, :direction_change], _measurements,
                      metadata}

      assert metadata.neutral == true

      IO.puts("✓ T018b: Telemetry event marks 2-player game as neutral")
    end
  end
end
