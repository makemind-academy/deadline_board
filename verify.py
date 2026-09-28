#!/usr/bin/env python3
"""deadline-board: not one due date is stored. Rules compute them, and a weekend shift says so on screen."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
from appplayer import AppPlayer  # noqa: E402
from mcpclient import Server  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "deadline_server")
CAP = os.path.join(HERE, "captures")
SERVER_ID = "com.makemind.sample.deadlines"

with Server(["dart", "run", "bin/server.dart"], cwd=SERVER) as s:
    board = s.call("board.today")
    assert board["rowCount"] == 6, board
    assert all(r["rule"] for r in board["rows"]), "every row must say which rule produced it"
    assert any("fell on" in r["rule"] for r in board["rows"]), "a weekend shift must be marked in the rule"
    one = s.call("board.client", {"client": "Brightwater"})
    assert one["rowCount"] < board["rowCount"]

ap = AppPlayer()
ap.register_server(SERVER_ID, "Deadline board", cwd=SERVER)
ap.restart()
ap.open_server(SERVER_ID)
ap.wait_text("6 duties")        # the count the rules produced, not the empty state
ap.expect_aligned(" d", min_rows=6)
ap.shot(f"{CAP}/01_board.png")
ap.tap("Brightwater")
ap.wait_text("2 duties")
ap.shot(f"{CAP}/02_one_client.png")
print("deadline-board: 6 duties from rules, narrowed to one client on screen")
