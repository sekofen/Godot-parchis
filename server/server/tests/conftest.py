import random

import pytest

from parques_server.rooms import RoomManager


class FakeClient:
    def __init__(self):
        self.inbox: list[dict] = []
        self.closed = False
        self.member = None

    def send(self, message):
        self.inbox.append(message)

    def close(self):
        self.closed = True

    def last(self, type_):
        return next((m for m in reversed(self.inbox) if m["type"] == type_), None)


@pytest.fixture
def manager():
    return RoomManager(grace_seconds=0.05, autoplay_delay=0.0, rng=random.Random(7))


def new_player(manager):
    client = FakeClient()
    member = manager.connect(client)
    client.member = member
    return client, member


@pytest.fixture
def make_player(manager):
    return lambda: new_player(manager)
