import argparse
import asyncio
import logging

from .rooms import RoomManager
from .server import run


def main() -> None:
    parser = argparse.ArgumentParser(description="Servidor de partidas de Parques")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--grace", type=float, default=60.0,
                        help="segundos para reconectarse antes de abandonar la partida")
    parser.add_argument("--autoplay-delay", type=float, default=1.2,
                        help="segundos entre jugadas automaticas de jugadores ausentes")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    manager = RoomManager(grace_seconds=args.grace, autoplay_delay=args.autoplay_delay)
    try:
        asyncio.run(run(args.host, args.port, manager))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
