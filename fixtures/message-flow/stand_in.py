"""Stand-in for the Claude harness in persona-test's message-flow scenario.

This is NOT Claude and witnesses nothing about Claude. It lets the scenario's
own logic run without the living's login: it draws enough of a Claude screen
for Herdr to see an idle Claude agent, reports its session to Herdr as
Herdr's Claude hook does, and writes a transcript in the shape Claude Code
writes (as Flow 0.17.4's observer and its tests describe that shape).

Its behaviour is chosen by PERSONA_TEST_STAND_IN_BEHAVIOUR; see
lib/components/claude-stand-in.nix.
"""

import json
import os
import re
import select
import socket
import sys
import termios
import time
import tty
import uuid

FOOTER = (
    " When every skill has loaded, reply once with exactly "
    "FLOW_LAUNCH_RECEIPT_V2 and nothing else."
)
RECEIPT = "FLOW_LAUNCH_RECEIPT_V2"
OTHER_MODEL = "claude-sonnet-5"
PASTE_START = b"\x1b[200~"
PASTE_END = b"\x1b[201~"


class Arguments:
    def __init__(self, argv):
        self.model = None
        self.effort = None
        self.system_prompt_file = None
        index = 0
        while index < len(argv):
            name = argv[index]
            value = argv[index + 1] if index + 1 < len(argv) else None
            if name == "--model":
                self.model = value
                index += 2
            elif name == "--effort":
                self.effort = value
                index += 2
            elif name == "--system-prompt-file":
                self.system_prompt_file = value
                index += 2
            elif name in ("--settings", "--remote-control"):
                index += 2
            else:
                index += 1


class Transcript:
    """Appends one JSON record per line, the way Claude Code does."""

    def __init__(self, session_id):
        configuration = os.environ["CLAUDE_CONFIG_DIR"]
        project = re.sub(r"[^A-Za-z0-9]", "-", os.getcwd())
        directory = os.path.join(configuration, "projects", project)
        os.makedirs(directory, exist_ok=True)
        self.path = os.path.join(directory, session_id + ".jsonl")
        self.session_id = session_id

    def append(self, record):
        record.setdefault("sessionId", self.session_id)
        record.setdefault("uuid", str(uuid.uuid4()))
        record.setdefault("timestamp", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
        with open(self.path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
            handle.flush()
            os.fsync(handle.fileno())

    def user_text(self, text, **extra):
        self.append(dict(type="user", message=dict(role="user", content=text), **extra))

    def user_parts(self, parts, **extra):
        self.append(dict(type="user", message=dict(role="user", content=parts), **extra))

    def assistant(self, model, effort, parts):
        self.append(
            dict(
                type="assistant",
                effort=effort,
                message=dict(role="assistant", model=model, content=parts),
            )
        )


class Skills:
    """Resolves and expands a skill as Claude Code does for Flow."""

    @staticmethod
    def path(name):
        for root in (
            os.path.join(os.environ["CLAUDE_CONFIG_DIR"], "skills"),
            os.path.join(os.getcwd(), ".claude", "skills"),
        ):
            candidate = os.path.join(root, name, "SKILL.md")
            if os.path.isfile(candidate):
                return os.path.realpath(candidate)
        return None

    @staticmethod
    def expansion(path):
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        body = source
        if source.startswith("---\n"):
            closing = source.index("\n---\n", 4)
            body = source[closing + len("\n---\n"):].lstrip("\n")
        return "Base directory for this skill: %s\n\n%s" % (os.path.dirname(path), body)


class Screen:
    """Draws the part of a Claude screen Herdr reads to judge its state."""

    def __init__(self):
        self.title = "Claude Code"

    def write(self, data):
        os.write(sys.stdout.fileno(), data.encode("utf-8"))

    def idle(self):
        self.write("\x1b]0;✳ %s\x07" % self.title)
        rule = "─" * 40
        self.write("\r\n%s\r\n❯ \r\n%s\r\n" % (rule, rule))


class StandIn:
    def __init__(self, argv):
        self.arguments = Arguments(argv)
        self.behaviour = os.environ.get("PERSONA_TEST_STAND_IN_BEHAVIOUR", "faithful")
        self.session_id = str(uuid.uuid4())
        self.transcript = Transcript(self.session_id)
        self.screen = Screen()
        self.first_prompt_seen = False

    def report_session(self):
        """The request Herdr's Claude SessionStart hook sends."""
        socket_path = os.environ.get("HERDR_SOCKET_PATH")
        pane_id = os.environ.get("HERDR_PANE_ID")
        if not socket_path or not pane_id:
            return
        request = {
            "id": "herdr:claude:%d" % int(time.time() * 1000),
            "method": "pane.report_agent_session",
            "params": {
                "pane_id": pane_id,
                "source": "herdr:claude",
                "agent": "claude",
                "seq": time.time_ns(),
                "agent_session_id": self.session_id,
                "agent_session_path": self.transcript.path,
                "session_start_source": "startup",
            },
        }
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.settimeout(0.5)
            client.connect(socket_path)
            client.sendall((json.dumps(request) + "\n").encode())
            try:
                client.recv(4096)
            except OSError:
                pass
            client.close()
        except OSError:
            pass

    def recorded(self, typed):
        if self.behaviour == "footer-dropped" and typed.endswith(FOOTER):
            return typed[: -len(FOOTER)]
        if self.behaviour == "body-altered" and typed.endswith(FOOTER):
            body = typed[: -len(FOOTER)]
            last = "Y" if body[-1:] != "Y" else "Z"
            return body[:-1] + last + FOOTER
        return typed

    def model(self):
        if self.behaviour == "other-model":
            return OTHER_MODEL
        return self.arguments.model

    @staticmethod
    def wrapped(text):
        """Claude Code's pasted-content rule for one submitted block."""
        lines = text.split("\n")
        units = len(text.encode("utf-16-le")) // 2
        if len(lines) == 1:
            return units > 800
        if len(lines) >= 4:
            return True
        return units >= 900

    def load_by_tool(self, name):
        tool_id = "toolu_" + uuid.uuid4().hex[:24]
        self.transcript.assistant(
            self.model(),
            self.arguments.effort,
            [dict(type="tool_use", id=tool_id, name="Skill", input=dict(skill=name))],
        )
        path = Skills.path(name)
        self.transcript.user_parts(
            [dict(type="tool_result", tool_use_id=tool_id, content="Launching skill: " + name)],
            toolUseResult=dict(success=path is not None, commandName=name),
        )
        if path is None:
            return False
        self.transcript.user_parts(
            [dict(type="text", text=Skills.expansion(path))],
            isMeta=True,
            turnCompanion=True,
            sourceToolUseID=tool_id,
        )
        return True

    def first_turn(self, typed):
        text = self.recorded(typed)
        head = re.match(r"^((?:/[a-z0-9-]+ )+)", text)
        if head:
            names = [name[1:] for name in head.group(1).split()][:5]
            argument = text[len(" ".join("/" + name for name in names)) + 1:]
            for name in names:
                record = "<command-message>%s</command-message>\n<command-name>/%s</command-name>" % (
                    name,
                    name,
                )
                if argument:
                    record += "\n<command-args>%s</command-args>" % argument
                self.transcript.user_text(record)
                path = Skills.path(name)
                if path is None:
                    return
                expansion = Skills.expansion(path)
                if argument:
                    expansion += "\n\nARGUMENTS: " + argument
                self.transcript.user_parts(
                    [dict(type="text", text=expansion)], isMeta=True, turnCompanion=True
                )
        else:
            if self.wrapped(text):
                self.transcript.user_text("<pasted_content>\n%s\n</pasted_content>" % text)
            else:
                self.transcript.user_text(text)
            order = re.search(r"through the Skill tool in this order: ([a-z0-9, -]+)\. Then: ", text)
            for name in (order.group(1).split(", ") if order else []):
                if not self.load_by_tool(name):
                    return
        self.transcript.assistant(
            self.model(), self.arguments.effort, [dict(type="text", text=RECEIPT)]
        )

    def submit(self, typed):
        if typed.startswith("/rename "):
            self.screen.title = typed[len("/rename "):]
            self.transcript.append(
                dict(type="custom-title", customTitle=self.screen.title)
            )
        elif not self.first_prompt_seen:
            self.first_prompt_seen = True
            self.first_turn(typed)
        else:
            self.transcript.user_text(typed)
            self.transcript.assistant(
                self.model(), self.arguments.effort, [dict(type="text", text="Noted.")]
            )
        self.screen.idle()

    def run(self):
        descriptor = sys.stdin.fileno()
        saved = termios.tcgetattr(descriptor)
        tty.setraw(descriptor)
        try:
            self.screen.write("\x1b[?2004h")
            self.screen.idle()
            buffer = b""
            pending = b""
            in_paste = False
            reports_left = 20
            while True:
                ready, _, _ = select.select([descriptor], [], [], 0.25)
                if reports_left > 0:
                    self.report_session()
                    reports_left -= 1
                if not ready:
                    continue
                chunk = os.read(descriptor, 65536)
                if not chunk:
                    return
                pending += chunk
                while pending:
                    if in_paste:
                        end = pending.find(PASTE_END)
                        if end < 0:
                            buffer += pending
                            pending = b""
                            break
                        buffer += pending[:end]
                        pending = pending[end + len(PASTE_END):]
                        in_paste = False
                    elif pending.startswith(PASTE_START):
                        pending = pending[len(PASTE_START):]
                        in_paste = True
                    elif PASTE_START.startswith(pending):
                        break
                    elif pending[:1] in (b"\r", b"\n"):
                        pending = pending[1:]
                        typed = buffer.decode("utf-8", "replace")
                        buffer = b""
                        if typed:
                            self.submit(typed)
                    elif pending[:1] == b"\x03":
                        return
                    else:
                        buffer += pending[:1]
                        pending = pending[1:]
        finally:
            termios.tcsetattr(descriptor, termios.TCSADRAIN, saved)


if __name__ == "__main__":
    StandIn(sys.argv[1:]).run()
