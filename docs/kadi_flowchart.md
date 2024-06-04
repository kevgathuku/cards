```
flowchart TD
    Start[*] --> |init| Lobby
    Lobby --> |add_player| Lobby
    Lobby --> |add_player| AwaitingDeck
    AwaitingDeck --> |add_deck| AwaitingPlayerCards
    AwaitingPlayerCards --> |deal_player_cards| AwaitingStartCard
    AwaitingStartCard --> |deal_start_card| Live
    Live --> |play_valid_hand| Live
    Live --> |play_ask_card| Ask
    Ask --> |play_requested_card| Live
    Ask --> |draw| Pick[awaiting_pick]
    Ask --> |play_ace| Live
    Live --> |play_2_or_3| EnforcePick
    EnforcePick --> |accept| Pick
    EnforcePick --> |block| Live
    EnforcePick --> |play_2_or_3| EnforcePick
    Pick --> |pick_cards| Live
    Pick --> |block| Live
    Live --> |play_hand| Kadi
    Live --> |play_question| Pick
    Kadi --> |accept_2_or_3| Pick
    Kadi --> |play_finish_card| End[*]

```

[![](https://mermaid.ink/img/pako:eNqNk8FuwjAMhl-lynGCy3brYRIanLZJSOw0iiqTuDRqm3RJCkKUd1_SFBo2Vq0nx_78267lE6GSIYlJVsoDzUGZ6GOeiMh-K2Nf64dNNJ0-Ry0X3LTRm9xujz7cmT4GjKV1CUdU_yFmB-CGi90caeHB0DPwzL4Getllv4Bi-jYpCPhchlD2xVLq3ININ5JDbyWu7kBAO1-Xb2fie-xHspaHXIF0DyVnaQ5iDAJd9DozfRlYFwGg8KtBbZD9KnflmIJDGy05LdbQN53W9rW5pwcUR9p5TKVKn9poITKpKDpNzwWOfgmUYm182T-QbSndkoZiv4jxmgFnrcu6BrmRSj_G8kt4Bcbvhrs_zKUIp3FwOOm1zXtIp5LZK9B5v6aFYPY6EkEmpEJVAWf2jE4uLyEmxwoTEluTYQZNaRKSiLNFoTFydRSUxEY1OCFNzcDgnMNOQUXiDEptvci4kerdn2Z3oRNSg_iU8sKcvwEsEkDd?type=png)](https://mermaid.live/edit#pako:eNqNk8FuwjAMhl-lynGCy3brYRIanLZJSOw0iiqTuDRqm3RJCkKUd1_SFBo2Vq0nx_78267lE6GSIYlJVsoDzUGZ6GOeiMh-K2Nf64dNNJ0-Ry0X3LTRm9xujz7cmT4GjKV1CUdU_yFmB-CGi90caeHB0DPwzL4Getllv4Bi-jYpCPhchlD2xVLq3ININ5JDbyWu7kBAO1-Xb2fie-xHspaHXIF0DyVnaQ5iDAJd9DozfRlYFwGg8KtBbZD9KnflmIJDGy05LdbQN53W9rW5pwcUR9p5TKVKn9poITKpKDpNzwWOfgmUYm182T-QbSndkoZiv4jxmgFnrcu6BrmRSj_G8kt4Bcbvhrs_zKUIp3FwOOm1zXtIp5LZK9B5v6aFYPY6EkEmpEJVAWf2jE4uLyEmxwoTEluTYQZNaRKSiLNFoTFydRSUxEY1OCFNzcDgnMNOQUXiDEptvci4kerdn2Z3oRNSg_iU8sKcvwEsEkDd)