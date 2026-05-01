# shogi.com

```text
Estrutura do projeto 

lib/
├── shogi_web/
│    ├── controllers/
│    ├── channels/
│    └── live/
│
└── shogi/
     ├── accounts/
     │
     ├── game/
     │    ├── server.ex       # GenServer — só estado e ciclo de vida
     │    ├── rules.ex        # lógica pura — movimentos, validações
     │    └── board.ex        # representação do tabuleiro
     │
     ├── matchmaking/
     │    ├── server.ex       # GenServer — fila e pareamento
     │    └── queue.ex        # lógica pura da fila
     │
     ├── supervisor.ex        # supervisiona os servers
     └── repo.ex
```
