from textual.app import App
from textual.widgets import Header, ListView, ListItem, Label, Button, Input, Static, TextArea
from textual.containers import Container, Vertical
from textual.screen import ModalScreen
from datetime import datetime, timedelta, date
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from collections import Counter
import pyperclip
import os
import copy
import logging

# Log to ~/.local/share/taskcli/taskcli.log at DEBUG level.
# To tail it: tail -f ~/.local/share/taskcli/taskcli.log
_log_path = Path.home() / ".local/share/taskcli/taskcli.log"
_log_path.parent.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s %(levelname)-7s %(name)s — %(message)s",
    handlers=[logging.FileHandler(_log_path, encoding="utf-8")],
)
log = logging.getLogger("taskcli")
log.info("=== taskcli starting ===")

# ── Popups ────────────────────────────────────────────────────────────────────

class QuestionPopup(ModalScreen):
    def __init__(self, question_text, options):
        super().__init__()
        self.question_text = question_text
        self.options = options

    def compose(self):
        yield Container(
            Label(self.question_text),
            *[Button(opt, variant="primary") for opt in self.options],
            Button("Cancel", variant="default"),
            id="question-dialog"
        )

    def on_button_pressed(self, event):
        label = str(event.button.label)
        if label == "Cancel":
            self.dismiss(None)
            return
        if label in self.options:
            self.dismiss(self.options.index(label))
        else:
            self.dismiss(None)


class MoodPopup(ModalScreen):
    MOODS = ["😊", "🙂", "😐", "😕", "😢"]

    def __init__(self, prompt):
        super().__init__()
        self.prompt = prompt

    def compose(self):
        yield Container(
            Label(self.prompt),
            *[Button(m, variant="primary") for m in self.MOODS],
            Button("Cancel", variant="default"),
            id="mood-dialog"
        )

    def on_button_pressed(self, event):
        label = str(event.button.label)
        if label == "Cancel":
            self.dismiss(None)
        else:
            self.dismiss(label)


class ConditionPopup(ModalScreen):
    def __init__(self, description, yes_block, no_block, lua_runtime):
        super().__init__()
        self.description = description
        self.yes_block = yes_block
        self.no_block = no_block
        self.lua = lua_runtime

    def compose(self):
        yield Container(
            Label(f"Condition: {self.description}"),
            Button("Yes", variant="success"),
            Button("No", variant="error"),
            Button("Cancel", variant="default"),
            id="condition-dialog"
        )

    def on_button_pressed(self, event):
        label = str(event.button.label)
        if label == "Cancel":
            self.dismiss(False)
            return
        if label == "Yes":
            self._execute_block(self.yes_block)
        else:
            self._execute_block(self.no_block)
        self.dismiss(True)

    def _execute_block(self, block):
        if block is None:
            return
        if isinstance(block, str):
            self.lua._add_task(block)
        else:
            block()


class AddTaskPopup(ModalScreen):
    def compose(self):
        yield Container(
            Label("New task:"),
            Input(placeholder="Task description…", id="task-input"),
            Button("Add", variant="primary", id="add-btn"),
            Button("Cancel", variant="default", id="cancel-btn"),
            id="add-task-dialog"
        )

    def on_mount(self):
        self.query_one("#task-input", Input).focus()

    def on_input_submitted(self, event):
        self._submit()

    def on_button_pressed(self, event):
        if event.button.id == "cancel-btn":
            self.dismiss(None)
        elif event.button.id == "add-btn":
            self._submit()

    def _submit(self):
        text = self.query_one("#task-input", Input).value.strip()
        self.dismiss(text if text else None)


class AddEventPopup(ModalScreen):
    """Create a new calendar event (once or recurring)."""

    RECUR_TYPES = ["once", "daily", "weekly", "monthly", "yearly"]

    def compose(self):
        yield Container(
            Label("New event", classes="title"),
            Label("Name:"),
            Input(placeholder="Event name…", id="ev-name"),
            Label("Time (HH:MM, leave blank for all-day):"),
            Input(placeholder="e.g. 14:30", id="ev-time"),
            Label("Recurrence:"),
            Container(
                Button("One-off",  variant="primary", id="t-once"),
                Button("Daily",    variant="default", id="t-daily"),
                Button("Weekly",   variant="default", id="t-weekly"),
                Button("Monthly",  variant="default", id="t-monthly"),
                Button("Yearly",   variant="default", id="t-yearly"),
                id="ev-type-row",
            ),
            Button("Add event", variant="success", id="ev-confirm"),
            Button("Cancel",    variant="default", id="ev-cancel"),
            id="add-event-dialog"
        )

    def on_mount(self):
        self.query_one("#ev-name", Input).focus()
        self._type = "once"

    def on_button_pressed(self, event):
        bid = str(event.button.id)
        if bid.startswith("t-"):
            self._type = bid[2:]
            for b in self.query("#ev-type-row Button"):
                b.variant = "primary" if str(b.id) == bid else "default"
        elif bid == "ev-confirm":
            self._submit()
        elif bid == "ev-cancel":
            self.dismiss(None)

    def on_input_submitted(self, event):
        if event.input.id == "ev-name":
            self.query_one("#ev-time", Input).focus()
        else:
            self._submit()

    def _submit(self):
        import re
        name = self.query_one("#ev-name", Input).value.strip()
        time_val = self.query_one("#ev-time", Input).value.strip()
        if not name:
            return
        if time_val and not re.match(r"^\d{1,2}:\d{2}$", time_val):
            inp = self.query_one("#ev-time", Input)
            inp.value = ""
            inp.placeholder = "Invalid — use HH:MM"
            return
        self.dismiss({"name": name, "time": time_val or None, "type": self._type})


class SelectTaskListPopup(ModalScreen):
    """Pick an existing task list to edit, or create a new one."""

    def __init__(self, lists, data_dir):
        super().__init__()
        self.lists = lists          # list of Path objects
        self.data_dir = Path(data_dir)

    def compose(self):
        buttons = []
        for p in self.lists:
            buttons.append(Button(p.stem, variant="primary", id=f"list-{p.stem}"))
        buttons.append(Button("+ New list", variant="success", id="new-list"))
        buttons.append(Button("Cancel",     variant="default", id="cancel"))
        yield Container(
            Label("Choose a task list:", classes="title"),
            *buttons,
            id="select-list-dialog"
        )

    def on_button_pressed(self, event):
        bid = str(event.button.id)
        if bid == "cancel":
            self.dismiss(None)
        elif bid == "new-list":
            self.dismiss("__new__")
        elif bid.startswith("list-"):
            stem = bid[5:]
            match = next((p for p in self.lists if p.stem == stem), None)
            self.dismiss(match)


class NewTaskListPopup(ModalScreen):
    """Enter a name for a new task list."""

    def compose(self):
        yield Container(
            Label("New task list name:"),
            Input(placeholder="e.g. work, errands, shopping…", id="list-name-input"),
            Button("Create", variant="success", id="create-btn"),
            Button("Cancel", variant="default", id="cancel-btn"),
            id="new-list-dialog"
        )

    def on_mount(self):
        self.query_one("#list-name-input", Input).focus()

    def on_input_submitted(self, event):
        self._submit()

    def on_button_pressed(self, event):
        if str(event.button.id) == "create-btn":
            self._submit()
        else:
            self.dismiss(None)

    def _submit(self):
        name = self.query_one("#list-name-input", Input).value.strip()
        # sanitise to a safe filename stem
        import re
        name = re.sub(r"[^\w\-]", "_", name).strip("_")
        self.dismiss(name if name else None)


class JournalScreen(ModalScreen):
    """Full-screen journal entry editor."""

    CSS = """
    JournalScreen {
        align: center middle;
    }
    #journal-container {
        width: 90%;
        height: 90%;
        background: $surface;
        border: thick $primary;
        padding: 1 2;
    }
    #journal-prompt {
        text-style: bold;
        margin-bottom: 1;
    }
    #journal-area {
        height: 1fr;
        border: tall $panel;
    }
    #journal-hint {
        color: $text-muted;
        margin-top: 1;
    }
    """

    def __init__(self, prompt, existing_text=""):
        super().__init__()
        self.prompt = prompt
        self.existing_text = existing_text

    def compose(self):
        yield Container(
            Label(self.prompt, id="journal-prompt"),
            TextArea(self.existing_text, id="journal-area"),
            Label("  ctrl+s  save    esc  cancel", id="journal-hint"),
            id="journal-container"
        )

    def on_mount(self):
        self.query_one("#journal-area", TextArea).focus()

    def on_key(self, event):
        if event.key == "ctrl+s":
            text = self.query_one("#journal-area", TextArea).text
            self.dismiss(text)
        elif event.key == "escape":
            self.dismiss(None)


class StatisticsPopup(ModalScreen):
    def __init__(self, mood_log, task_stats):
        super().__init__()
        self.mood_log = mood_log
        self.task_stats = task_stats

    def compose(self):
        mood_counts = Counter(entry["mood"] for entry in self.mood_log)
        mood_text = "\n".join([f"{m}: {c}" for m, c in mood_counts.items()])
        yield Container(
            Label("📊 Statistics", classes="title"),
            Label("Mood History:"),
            Label(mood_text if mood_text else "No mood entries yet"),
            Label("\nTask Completion:"),
            Label(f"Total tasks completed: {self.task_stats['total_done']}"),
            Label(f"Completion rate: {self.task_stats['rate']:.1%}"),
            Button("Close", variant="primary", id="close"),
            id="stats-dialog"
        )

    def on_button_pressed(self, event):
        if event.button.id == "close":
            self.dismiss()


# ── Main app ──────────────────────────────────────────────────────────────────

class TaskListApp(App):
    CSS = """
    ListView { height: 1fr; }
    #mood-dialog, #condition-dialog, #stats-dialog, #question-dialog, #add-task-dialog {
        background: $surface;
        border: thick $primary;
        padding: 1 2;
        width: 60;
        height: auto;
    }
    .title { text-style: bold; text-align: center; margin-bottom: 1; }
    .answered { color: #666666; }
    .child-task { padding-left: 3; }
    .cal-event { color: #ffcc66; text-style: bold; }
    .lua-error { color: #ff5555; text-style: bold; }
    #add-event-dialog { width: 64; }
    #select-list-dialog, #new-list-dialog { width: 50; height: auto; background: $surface; border: thick $primary; padding: 1 2; }
    #ev-type-row { height: auto; layout: horizontal; }
    #ev-type-row Button { margin-right: 1; }
    #keybind-bar {
        height: 7;
        background: $panel;
        layout: horizontal;
    }
    .keybind-col {
        width: 1fr;
        color: $text-muted;
        padding: 0 1;
    }
    #date-bar {
        height: 1;
        content-align: center middle;
        text-style: bold;
        background: $primary-darken-2;
        color: $text;
        padding: 0 2;
    }
    """

    BINDINGS = [
        ("n", "add_task", "New task"),
        ("E", "add_event", "New event"),
        ("e", "edit_routine", "Edit routine"),
        ("t", "edit_tasks", "Edit tasks"),
        ("d", "delete_item", "Delete"),
        ("ctrl+z", "undo", "Undo"),
        ("ctrl+r", "redo", "Redo"),
        ("J", "move_down", "Move down"),
        ("K", "move_up", "Move up"),
        ("j", "cursor_down", ""),
        ("k", "cursor_up", ""),
        ("h", "prev_day", ""),
        ("l", "next_day", ""),
        ("left", "prev_day", "Prev day"),
        ("right", "next_day", "Next day"),
        ("r", "refresh", "Refresh"),
        ("q", "quit_app", "Quit"),
    ]

    def __init__(self, data_dir):
        super().__init__()
        self.data_dir = Path(data_dir)
        self.tasks_file = self.data_dir / "tasks.md"
        self.routine_file = self.data_dir / "routine.lua"
        self.current_day = date.today()
        self.generated_items = []   # list of item dicts (see _make_item)
        self.all_parsers = {}
        self.parser = None
        self.state_mgr = None
        self.lua_sandbox = None
        self._undo_stack = []  # list of snapshots
        self._redo_stack = []  # list of snapshots
        self._setup_watcher()

    # Each item is a dict with at minimum:
    #   type: str
    #   key:  str  (stable identity for ordering)
    #   moveable: bool
    #   parent_key: str | None   (anchors this item below its parent)
    # Plus type-specific fields.

    def _make_item(self, type, key, moveable=True, parent_key=None, **kwargs):
        return {"type": type, "key": key, "moveable": moveable,
                "parent_key": parent_key, **kwargs}


    def _keybind_cols(self):
        pairs = [
            ("n",   "New task"),
            ("E",   "New event"),
            ("e",   "Edit routine"),
            ("t",   "Edit tasks"),
            ("d",   "Delete"),
            ("^z",  "Undo"),
            ("^r",  "Redo"),
            ("J/K", "Move up/down"),
            ("←/→", "Prev/next day"),
            ("r",   "Refresh"),
            ("q",   "Quit"),
        ]
        mid = (len(pairs) + 1) // 2
        def fmt(p): return f"\\[{p[0]}] {p[1]}"
        col1 = "\n".join(fmt(p) for p in pairs[:mid])
        col2 = "\n".join(fmt(p) for p in pairs[mid:])
        return col1, col2


    def _format_day_label(self):
        today = date.today()
        delta = (self.current_day - today).days
        dow = self.current_day.strftime("%A")
        date_str = self.current_day.strftime("%d %b %Y")

        if delta == 0:
            rel = "Today"
        elif delta == 1:
            rel = "Tomorrow"
        elif delta == -1:
            rel = "Yesterday"
        elif 2 <= delta <= 6:
            rel = dow
        elif 7 <= delta <= 13:
            rel = f"Next {dow}"
        elif -7 <= delta <= -2:
            rel = f"Last {dow}"
        else:
            rel = None

        if rel:
            return f"  ◀  {date_str}  —  {rel}  ▶  "
        else:
            return f"  ◀  {date_str}  ({dow})  ▶  "

    def _setup_watcher(self):
        class ReloadHandler(FileSystemEventHandler):
            def __init__(self, app):
                self.app = app
            def on_modified(self, event):
                if str(event.src_path) in [str(self.app.tasks_file), str(self.app.routine_file)]:
                    self.app.call_from_thread(self.app.refresh_today)
        self.observer = Observer()
        self.observer.schedule(ReloadHandler(self), str(self.data_dir), recursive=False)

    def compose(self):
        yield Static(self._format_day_label(), id="date-bar")
        yield ListView(id="task-list")
        cols = self._keybind_cols()
        from textual.containers import Horizontal as _H
        yield _H(*[Static(c, classes="keybind-col") for c in cols], id="keybind-bar")

    def on_mount(self):
        self.observer.start()
        self.refresh_today()

    # ── Build item list ───────────────────────────────────────────────────────

    def _load_parsers(self):
        """Load all task list parsers from disk into self.all_parsers / self.parser."""
        from .parser import TaskParser
        self.all_parsers = {}
        tasks_dir = self.data_dir / "tasks"
        tasks_dir.mkdir(exist_ok=True)
        log.debug("_load_parsers: scanning tasks_dir=%s", tasks_dir)
        if self.tasks_file.exists() and not (tasks_dir / "tasks.md").exists():
            import shutil
            shutil.copy(self.tasks_file, tasks_dir / "tasks.md")
            log.debug("_load_parsers: copied legacy tasks.md into tasks/")
        # Primary location: tasks/ subdirectory
        for md in sorted(tasks_dir.glob("*.md")):
            p = TaskParser(md)
            p.parse()
            self.all_parsers[md.stem] = p
            log.debug("_load_parsers: loaded '%s' from tasks/ — %d tasks", md.stem, len(p.tasks))
        # Also pick up any .md files placed directly in data_dir (common mistake).
        for md in sorted(self.data_dir.glob("*.md")):
            if md.stem not in self.all_parsers:
                p = TaskParser(md)
                p.parse()
                self.all_parsers[md.stem] = p
                log.debug("_load_parsers: loaded '%s' from data_dir root — %d tasks", md.stem, len(p.tasks))
            else:
                log.debug("_load_parsers: skipping data_dir root '%s' (already loaded from tasks/)", md.stem)
        if not self.all_parsers and self.tasks_file.exists():
            p = TaskParser(self.tasks_file)
            p.parse()
            self.all_parsers["tasks"] = p
            log.debug("_load_parsers: fallback — loaded legacy tasks.md (%d tasks)", len(p.tasks))
        self.parser = self.all_parsers.get("tasks") or next(iter(self.all_parsers.values()), None)
        if self.parser is None:
            (tasks_dir / "tasks.md").write_text("# Tasks\n")
            p = TaskParser(tasks_dir / "tasks.md")
            p.parse()
            self.all_parsers["tasks"] = p
            self.parser = p
            log.warning("_load_parsers: no task files found — created empty tasks.md")
        log.debug("_load_parsers: final parsers loaded: %s", list(self.all_parsers.keys()))
    def refresh_today(self):
        from .lua_runtime import LuaSandbox
        from .state_manager import StateManager
        from datetime import date as _date

        # ── Always load state first (needed for both paths) ───────────────────
        self.state_mgr = StateManager(self.data_dir)
        self.state_mgr.load()

        day_str = self.current_day.isoformat()
        is_past = self.current_day < _date.today()

        # ── Past day: restore from frozen snapshot if available ───────────────
        if is_past:
            frozen = self.state_mgr.get_frozen_items(day_str)
            if frozen is not None:
                # Rehydrate: task_obj can't be restored, leave as None
                # (toggle/complete still works via state, not task_obj for past days)
                for it in frozen:
                    it.setdefault("task_obj", None)
                self.generated_items = frozen
                # Still need parsers for _resolve_task used by interactions
                self._load_parsers()
                self._rebuild_list_view()
                return

        # ── Load parsers ──────────────────────────────────────────────────────
        self._load_parsers()

        day_state = self.state_mgr.get_day_state(day_str)
        answers = day_state.get("answers", {})
        answers_full = day_state

        all_tasks_dbs = {name: p.tasks for name, p in self.all_parsers.items()}
        self.lua_sandbox = LuaSandbox(
            all_tasks_dbs, self.state_mgr.vars, answers,
            day_str, self.state_mgr.events, self.state_mgr
        )
        raw_items = self.lua_sandbox.run_script(self.routine_file)
        log.debug("refresh_today: run_script returned %d raw items", len(raw_items))

        items = []

        # Calendar events for this day — shown at top, not moveable
        for ev in self.state_mgr.get_events_for_day(self.current_day):
            eid = ev.get("id", ev["name"])
            time_str = f" {ev['time']}" if ev.get("time") else ""
            recur_label = {"daily": " ↻daily", "weekly": " ↻weekly",
                           "monthly": " ↻monthly", "yearly": " ↻yearly"}.get(ev.get("type","once"), "")
            text = f"◆{time_str}  {ev['name']}{recur_label}"
            items.append(self._make_item("cal_event", f"cal:{eid}",
                moveable=True, text=text, event_id=eid))

        # Due/scheduled notices (not moveable, no key needed for ordering)
        for tid, task in self.parser.tasks.items():
            if task.do_date == day_str:
                items.append(self._make_item("notice", f"notice:do:{tid}",
                    moveable=False, text=f"📅 Scheduled: {task.text}"))
            if task.due_date:
                days_left = (datetime.fromisoformat(task.due_date)
                             - datetime.combine(self.current_day, datetime.min.time())).days
                if 0 <= days_left <= 3:
                    urgency = ("today" if days_left == 0
                               else "tomorrow" if days_left == 1
                               else f"in {days_left} days")
                    items.append(self._make_item("notice", f"notice:due:{tid}",
                        moveable=False, text=f"📅 Due {urgency}: {task.text}"))

        # Convert raw Lua output to item dicts
        question_keys_emitted = set()  # qid keys already added as widgets
        for raw in raw_items:
            rtype = raw[0]

            if rtype == "lua_error":
                _, msg = raw
                items.append(self._make_item(
                    "lua_error", "lua_error",
                    moveable=False, message=msg,
                ))
                # Stop processing — the rest of the output is likely garbage
                break

            elif rtype == "task":
                _, task_id, text, done = raw
                real_tid, task_obj = self._resolve_task(task_id, text)
                key = f"task:{real_tid}"
                items.append(self._make_item(
                    "task", key,
                    moveable=True,
                    parent_key=None,
                    task_id=real_tid, text=text, task_obj=task_obj,
                ))

            elif rtype == "mood":
                _, prompt = raw
                mood_key = f"mood:{prompt}"
                done_today = self.state_mgr.is_mood_done(day_str, mood_key)
                items.append(self._make_item(
                    "mood", mood_key,
                    moveable=True,
                    parent_key=None,
                    prompt=prompt, done=done_today,
                ))

            elif rtype == "separator":
                key = f"sep:{len(items)}"
                items.append(self._make_item("separator", key, moveable=True, parent_key=None))

            elif rtype == "question":
                _, qid, text, opts = raw
                answered = answers.get(qid)
                key = f"question:{qid}"
                # Only emit the question widget on first encounter
                if key not in question_keys_emitted:
                    question_keys_emitted.add(key)
                    items.append(self._make_item(
                        "question", key,
                        moveable=True,
                        parent_key=None,
                        qid=qid, text=text, opts=opts, answered=answered,
                    ))

            elif rtype == "event":
                _, name = raw
                items.append(self._make_item("event", f"event:{name}",
                    moveable=False, parent_key=None, name=name))

            elif rtype == "journal":
                _, jid, prompt = raw
                entry = answers_full.get(f"journal:{jid}", "")
                items.append(self._make_item(
                    "journal", f"journal:{jid}",
                    moveable=True,
                    parent_key=None,
                    jid=jid, prompt=prompt, entry=entry,
                ))

            elif rtype == "end_group":
                pass  # no-op now that colour grouping is removed

            elif rtype == "condition":
                _, desc, yes_block, no_block = raw
                key = f"condition:{desc}"
                items.append(self._make_item(
                    "condition", key,
                    moveable=True,
                    parent_key=None,
                    desc=desc, yes_block=yes_block, no_block=no_block,
                ))
                current_qid = None
                current_q_color = None

        # Extra tasks added manually today
        for extra in self.state_mgr.get_extra_tasks(day_str):
            items.append(self._make_item(
                "task", extra["key"],
                moveable=True,
                task_id=extra["key"], text=extra["text"], task_obj=None,
            ))

        items.append(self._make_item("statistics", "statistics", moveable=False))

        # Apply saved ordering, preserving parent anchoring
        items = self._apply_order(items, self.state_mgr.get_item_order(day_str))

        self.generated_items = items
        log.debug("refresh_today: final item list (%d items): %s",
                  len(items), [(it["type"], it.get("text", it.get("key",""))) for it in items])

        # Freeze past days on first build so future loads ignore routine changes
        if is_past:
            self.state_mgr.freeze_day(day_str, items)

        self._rebuild_list_view()

    def _apply_order(self, items, saved_order):
        """Reorder free items according to saved_order, while keeping
        child items immediately after their parent."""
        if not saved_order:
            return items

        by_key = {it["key"]: it for it in items}
        # Separate anchored children from free items
        children_of = {}   # parent_key → [child items in original order]
        free = []
        seen = set()
        for it in items:
            if it["parent_key"]:
                children_of.setdefault(it["parent_key"], []).append(it)
            else:
                free.append(it)

        # Reorder free items by saved_order, appending any new ones at end
        keyed_free = {it["key"]: it for it in free}
        reordered_free = []
        for k in saved_order:
            if k in keyed_free and k not in seen:
                reordered_free.append(keyed_free[k])
                seen.add(k)
        for it in free:
            if it["key"] not in seen:
                reordered_free.append(it)

        # Now interleave: after each parent, insert its children
        result = []
        for it in reordered_free:
            result.append(it)
            for child in children_of.get(it["key"], []):
                result.append(child)

        return result

    # ── Render ────────────────────────────────────────────────────────────────

    def _rebuild_list_view(self):
        list_view = self.query_one("#task-list", ListView)
        idx = list_view.index or 0
        list_view.clear()

        day_str = self.current_day.isoformat()

        for item in self.generated_items:
            t = item["type"]

            if t == "task":
                task_obj = item["task_obj"]
                if task_obj:
                    is_done = task_obj.done
                    if task_obj.is_daily:
                        is_done = self.state_mgr.is_task_done_today(day_str, item["task_id"])
                else:
                    is_done = self.state_mgr.is_task_done_today(day_str, item["task_id"])
                symbol = "✓" if is_done else "□"
                lbl = Label(f"{'[dim]' if is_done else ''}{symbol} {item['text']}{'[/]' if is_done else ''}")
                list_view.append(ListItem(lbl))

            elif t == "question":
                if item["answered"] is not None:
                    answer_text = item["answered"] if isinstance(item["answered"], str) else item["opts"][item["answered"]]
                    lbl = Label(f"[dim]✓ {item['text']}  → {answer_text}[/]")
                else:
                    lbl = Label(f"? {item['text']} ({', '.join(item['opts'])})")
                list_view.append(ListItem(lbl))
            elif t == "mood":
                if item["done"]:
                    # Find today's mood entry to show which was picked
                    last = next((e["mood"] for e in reversed(self.state_mgr.mood_log)
                                 if e.get("prompt", item["prompt"]) == item["prompt"]
                                 or True), None)
                    list_view.append(ListItem(Label(f"✓ {item['prompt']}", classes="answered")))
                else:
                    list_view.append(ListItem(Label(f"😊 {item['prompt']}")))

            elif t == "separator":
                list_view.append(ListItem(Label("─" * 40)))

            elif t == "event":
                list_view.append(ListItem(Label(f"⏰ {item['name']}")))

            elif t == "cal_event":
                list_view.append(ListItem(Label(item["text"], classes="cal-event")))

            elif t == "notice":
                list_view.append(ListItem(Label(item["text"])))

            elif t == "journal":
                entry = item.get("entry", "")
                if entry:
                    preview = entry.replace("\n", " ").strip()
                    if len(preview) > 60:
                        preview = preview[:57] + "…"
                    list_view.append(ListItem(Label(f"✎ {item['prompt']}  → {preview}", classes="answered")))
                else:
                    list_view.append(ListItem(Label(f"✎ {item['prompt']}")))

            elif t == "condition":
                list_view.append(ListItem(Label(f"🔀 {item['desc']}")))

            elif t == "lua_error":
                msg = item.get("message", "Unknown error")
                # Wrap long messages
                lines = ["⚠ routine.lua error — press [e] to edit"] + [
                    f"  {line}" for line in msg.splitlines()
                ]
                list_view.append(ListItem(Label("\n".join(lines), classes="lua-error")))

            elif t == "statistics":
                list_view.append(ListItem(Label("📊 Statistics")))

        # Restore cursor position
        count = len(self.generated_items)
        if count > 0:
            list_view.index = max(0, min(idx, count - 1))

    # ── Task resolution ───────────────────────────────────────────────────────

    def _resolve_task(self, task_id, text):
        for p in self.all_parsers.values():
            task = p.tasks.get(task_id)
            if task is not None:
                return task_id, task
            for tid, t in p.tasks.items():
                if t.text == task_id or t.text == text:
                    return tid, t
        return task_id, None

    # ── Interaction ───────────────────────────────────────────────────────────

    def _current_index(self):
        return self.query_one("#task-list", ListView).index or 0

    def _is_past_day(self):
        from datetime import date as _date
        return self.current_day < _date.today()

    def on_list_view_selected(self, event):
        if event.list_view.id != "task-list":
            return
        idx = event.list_view.index
        if idx is None or idx >= len(self.generated_items):
            return
        item = self.generated_items[idx]
        t = item["type"]
        day_str = self.current_day.isoformat()

        # Past days are read-only — only statistics popup is allowed
        if self._is_past_day() and t != "statistics":
            return

        if t == "task":
            task_obj = item["task_obj"]
            task_id = item["task_id"]
            self._push_undo()
            if task_obj is None:
                # Extra task — toggle via state
                current = self.state_mgr.is_task_done_today(day_str, task_id)
                self.state_mgr.set_task_done(day_str, task_id, not current)
                self.refresh_today()
            elif task_obj.is_daily:
                current = self.state_mgr.is_task_done_today(day_str, task_id)
                self.state_mgr.set_task_done(day_str, task_id, not current)
                self.refresh_today()
            else:
                # Find which parser owns this task
                owner = next(
                    (p for p in self.all_parsers.values() if task_id in p.tasks),
                    self.parser
                )
                owner.rewrite_task(task_id, not task_obj.done)
                self.refresh_today()

        elif t == "question":
            # Allow re-answering to revert
            def on_answer(choice_idx):
                if choice_idx is None:
                    return
                self._push_undo()
                self.state_mgr.set_answer(day_str, item["qid"], item["opts"][choice_idx])
                self.refresh_today()
            self.push_screen(QuestionPopup(item["text"], item["opts"]), callback=on_answer)

        elif t == "mood":
            # Allow re-selecting to revert
            def on_mood(emoji):
                if emoji is None:
                    return
                self._push_undo()
                self.state_mgr.add_mood_entry(str(emoji))
                self.state_mgr.set_mood_done(day_str, item["key"])
                self.refresh_today()
            self.push_screen(MoodPopup(item["prompt"]), callback=on_mood)

        elif t == "journal":
            existing = self.state_mgr.get_journal_entry(day_str, item["jid"])
            def on_journal(text):
                if text is None:
                    return
                self._push_undo()
                self.state_mgr.set_journal_entry(day_str, item["jid"], text)
                self.refresh_today()
            self.push_screen(JournalScreen(item["prompt"], existing or ""), callback=on_journal)

        elif t == "journal":
            existing = self.state_mgr.get_journal_entry(day_str, item["jid"])
            def on_journal(text):
                if text is None:
                    return
                self._push_undo()
                self.state_mgr.set_journal_entry(day_str, item["jid"], text)
                self.refresh_today()
            self.push_screen(JournalScreen(item["prompt"], existing or ""), callback=on_journal)

        elif t == "condition":
            self.push_screen(ConditionPopup(
                item["desc"], item["yes_block"], item["no_block"], self.lua_sandbox
            ))

        elif t == "statistics":
            total = len(self.parser.tasks)
            done = sum(1 for t in self.parser.tasks.values() if t.done)
            self.push_screen(StatisticsPopup(
                self.state_mgr.get_mood_stats(),
                {"total_done": done, "rate": done / total if total else 0}
            ))

    # ── Actions ───────────────────────────────────────────────────────────────

    def action_add_task(self):
        if self._is_past_day():
            return
        def on_text(text):
            if not text:
                return
            self._push_undo()
            self.state_mgr.add_extra_task(self.current_day.isoformat(), text)
            self.refresh_today()
        self.push_screen(AddTaskPopup(), callback=on_text)

    def action_add_event(self):
        if self._is_past_day():
            return
        def on_event(ev):
            if not ev:
                return
            self._push_undo()
            self.state_mgr.add_calendar_event(ev, self.current_day)
            self.refresh_today()
        self.push_screen(AddEventPopup(), callback=on_event)

    def action_move_up(self):
        if self._is_past_day():
            return
        self._move_item(-1)

    def action_move_down(self):
        if self._is_past_day():
            return
        self._move_item(1)

    def _move_item(self, direction):
        self._push_undo()
        idx = self._current_index()
        items = self.generated_items
        if idx < 0 or idx >= len(items):
            return
        item = items[idx]
        if not item["moveable"]:
            return

        is_child = bool(item["parent_key"])

        if is_child:
            self._move_child(idx, direction)
        else:
            self._move_free(idx, direction)

    def _move_child(self, idx, direction):
        """Move a child task within its question group, or out of it."""
        items = self.generated_items
        item = items[idx]
        my_parent = item["parent_key"]

        # Siblings: other children of same parent, in order
        siblings = [i for i, it in enumerate(items) if it["parent_key"] == my_parent]
        my_pos_in_siblings = siblings.index(idx)

        target_sibling_pos = my_pos_in_siblings + direction

        if 0 <= target_sibling_pos < len(siblings):
            # Swap with sibling
            target_idx = siblings[target_sibling_pos]
            items[idx], items[target_idx] = items[target_idx], items[idx]
            new_idx = target_idx
        elif direction == -1 and my_pos_in_siblings == 0:
            # Move out of group upward — become free, insert before parent
            parent_idx = next(i for i, it in enumerate(items) if it["key"] == my_parent)
            item["parent_key"] = None
            items.pop(idx)
            items.insert(parent_idx, item)
            new_idx = parent_idx
        elif direction == 1 and my_pos_in_siblings == len(siblings) - 1:
            # Move out of group downward — become free, insert after last sibling
            item["parent_key"] = None
            items.pop(idx)
            # idx now points to whatever was after; insert there
            new_idx = min(idx, len(items))
            items.insert(new_idx, item)
        else:
            return

        self.generated_items = items
        self._save_order_and_rebuild(new_idx)

    def _move_free(self, idx, direction):
        """Move a free (non-child) item, possibly into a question group."""
        items = self.generated_items
        item = items[idx]
        own_key = item["key"]

        # own_block = this item + its children
        own_block = [item] + [it for it in items if it["parent_key"] == own_key]
        own_keys = {x["key"] for x in own_block}

        # Flat list without own_block
        flat = [it for it in items if it["key"] not in own_keys]

        # Find where this item sits in flat
        flat_idx = next((i for i, it in enumerate(flat) if it["key"] == items[idx + len(own_block) if direction == 1 else idx - 1]["key"] if not it["key"] in own_keys), None)

        # Find the target neighbour: skip own children AND non-moveable items
        scan = idx + direction
        if direction == 1:
            while scan < len(items) and items[scan]["key"] in own_keys:
                scan += 1
        while 0 <= scan < len(items) and not items[scan]["moveable"]:
            scan += direction
        if scan < 0 or scan >= len(items):
            return

        neighbour = items[scan]

        if neighbour["parent_key"]:
            # Neighbour is a child — we'd be moving into that group
            # Find the parent question
            parent_key = neighbour["parent_key"]
            parent_idx = next(i for i, it in enumerate(items) if it["key"] == parent_key)

            if direction == 1:
                # Moving down past a child: adopt that parent, insert at start of group
                item["parent_key"] = parent_key
                items.pop(idx)
                # Find first child of parent in updated list
                first_child_idx = next(i for i, it in enumerate(items) if it["parent_key"] == parent_key)
                items.insert(first_child_idx, item)
                new_idx = first_child_idx
            else:
                # Moving up past a child: adopt that parent, insert at end of group
                item["parent_key"] = parent_key
                items.pop(idx)
                # Find last child of parent
                child_indices = [i for i, it in enumerate(items) if it["parent_key"] == parent_key]
                insert_at = child_indices[-1] + 1
                items.insert(insert_at, item)
                new_idx = insert_at
        else:
            # Simple swap with another free item (+ its children block)
            target_item = neighbour
            target_key = target_item["key"]
            target_block = [target_item] + [it for it in items if it["parent_key"] == target_key]
            target_keys = {x["key"] for x in target_block}

            # Remove own_block, then swap positions with target_block
            remaining = [it for it in items if it["key"] not in own_keys and it["key"] not in target_keys]

            # Find target position in remaining
            tpos = next((i for i, it in enumerate(items)
                         if it["key"] == target_key and it["key"] not in own_keys), None)
            if tpos is None:
                return

            if direction == 1:
                # own_block goes after target_block
                result = []
                for it in items:
                    if it["key"] in own_keys:
                        continue
                    result.append(it)
                    if it["key"] == target_block[-1]["key"]:
                        result.extend(own_block)
            else:
                # own_block goes before target_block
                result = []
                for it in items:
                    if it["key"] in own_keys:
                        continue
                    if it["key"] == target_key:
                        result.extend(own_block)
                    result.append(it)

            items = result
            self.generated_items = items
            new_idx = next((i for i, it in enumerate(items) if it["key"] == own_key), idx)
            self._save_order_and_rebuild(new_idx)
            return

        self.generated_items = items
        new_idx = next((i for i, it in enumerate(items) if it["key"] == own_key), idx)
        self._save_order_and_rebuild(new_idx)

    def _save_order_and_rebuild(self, new_idx):
        free_keys = [it["key"] for it in self.generated_items if not it["parent_key"]]
        self.state_mgr.set_item_order(self.current_day.isoformat(), free_keys)
        self._rebuild_list_view()
        count = len(self.generated_items)
        self.query_one("#task-list", ListView).index = max(0, min(new_idx, count - 1))

    def _update_date_bar(self):
        self.query_one("#date-bar", Static).update(self._format_day_label())


    # ── Undo / redo ───────────────────────────────────────────────────────────

    def _snapshot(self):
        """Capture enough state to fully reverse any mutating action."""
        day_str = self.current_day.isoformat()
        # Deep-copy generated_items (dicts of primitives — no Lua objects)
        items_copy = []
        for it in self.generated_items:
            d = dict(it)
            # Don't copy Lua function refs — they can't be serialised anyway
            d.pop("yes_block", None)
            d.pop("no_block", None)
            items_copy.append(d)
        # Snapshot day state
        day_state = copy.deepcopy(self.state_mgr.get_day_state(day_str))
        # Snapshot all task file contents
        file_snaps = {}
        tasks_dir = self.data_dir / "tasks"
        for md in tasks_dir.glob("*.md"):
            file_snaps[str(md)] = md.read_text()
        return {
            "items": items_copy,
            "day_state": day_state,
            "day_str": day_str,
            "files": file_snaps,
        }

    def _push_undo(self):
        snap = self._snapshot()
        self._undo_stack.append(snap)
        if len(self._undo_stack) > 50:
            self._undo_stack.pop(0)
        self._redo_stack.clear()

    def _restore_snapshot(self, snap):
        day_str = snap["day_str"]
        # Restore file contents
        for path_str, text in snap["files"].items():
            from pathlib import Path as _P
            _P(path_str).write_text(text)
        # Restore day state
        self.state_mgr.state[day_str] = snap["day_state"]
        self.state_mgr.save_state()
        # Rebuild from scratch to get fresh task_obj refs (files may have changed)
        self.refresh_today()

    def action_undo(self):
        if self._is_past_day() or not self._undo_stack:
            return
        self._redo_stack.append(self._snapshot())
        snap = self._undo_stack.pop()
        self._restore_snapshot(snap)

    def action_redo(self):
        if self._is_past_day() or not self._redo_stack:
            return
        self._undo_stack.append(self._snapshot())
        snap = self._redo_stack.pop()
        self._restore_snapshot(snap)

    # ── Delete ────────────────────────────────────────────────────────────────

    def action_delete_item(self):
        if self._is_past_day():
            return
        idx = self._current_index()
        items = self.generated_items
        if idx < 0 or idx >= len(items):
            return
        item = items[idx]
        t = item["type"]
        day_str = self.current_day.isoformat()

        # Don't delete the statistics entry or error banner
        if t in ("statistics", "lua_error"):
            return

        self._push_undo()

        if t == "cal_event":
            self.state_mgr.delete_calendar_event(item["event_id"])

        elif t == "task":
            task_obj = item["task_obj"]
            task_id  = item["task_id"]
            if task_obj is None:
                # Extra task — remove from state
                day = self.state_mgr.state.setdefault(day_str, {})
                extras = day.get("extra_tasks", [])
                day["extra_tasks"] = [e for e in extras if e["key"] != task_id]
                self.state_mgr.save_state()
            else:
                # Real task — remove the line from the .md file
                owner = next(
                    (p for p in self.all_parsers.values() if task_id in p.tasks),
                    self.parser
                )
                lines = owner.file_path.read_text().splitlines()
                line_idx = task_obj.line_num - 1
                if 0 <= line_idx < len(lines):
                    lines.pop(line_idx)
                    owner.file_path.write_text("\n".join(lines))

        elif t == "question":
            qid = item["qid"]
            # Remove answer from state; tasks remain as independent items
            day = self.state_mgr.state.get(day_str, {})
            day.get("answers", {}).pop(qid, None)
            self.state_mgr.save_state()

        elif t == "mood":
            # Remove mood_done flag so it re-appears as unanswered
            day = self.state_mgr.state.get(day_str, {})
            mood_done = day.get("mood_done", [])
            if item["key"] in mood_done:
                mood_done.remove(item["key"])
            self.state_mgr.save_state()

        elif t in ("separator", "event", "notice", "condition"):
            # These are display-only items; just remove from the in-memory list
            # and save the new order (separators are persisted via item_order)
            pass  # handled below by removing from generated_items

        # Remove the item from generated_items
        keys_to_remove = {item["key"]}

        new_items = [it for it in self.generated_items if it["key"] not in keys_to_remove]
        self.generated_items = new_items

        # Persist order
        free_keys = [it["key"] for it in self.generated_items if not it["parent_key"]]
        self.state_mgr.set_item_order(day_str, free_keys)

        # Place cursor sensibly
        new_idx = min(idx, len(self.generated_items) - 1)
        self._rebuild_list_view()
        if new_idx >= 0:
            self.query_one("#task-list", ListView).index = new_idx

    def action_cursor_down(self):
        self.query_one("#task-list", ListView).action_cursor_down()

    def action_cursor_up(self):
        self.query_one("#task-list", ListView).action_cursor_up()

    def _freeze_if_past(self, day):
        """If `day` is before today, persist the current item list as a frozen snapshot."""
        from datetime import date as _date
        if day < _date.today() and self.state_mgr and self.generated_items:
            self.state_mgr.freeze_day(day.isoformat(), self.generated_items)

    def action_prev_day(self):
        self._freeze_if_past(self.current_day)
        self.current_day -= timedelta(days=1)
        self._update_date_bar()
        self.refresh_today()

    def action_next_day(self):
        self._freeze_if_past(self.current_day)
        self.current_day += timedelta(days=1)
        self._update_date_bar()
        self.refresh_today()

    def action_refresh(self):
        self.refresh_today()

    def action_quit_app(self):
        self.exit()

    def action_edit_routine(self):
        os.system(f"kitty nvim {self.routine_file} &")

    def action_edit_tasks(self):
        tasks_dir = self.data_dir / "tasks"
        tasks_dir.mkdir(exist_ok=True)
        lists = sorted(tasks_dir.glob("*.md"))

        def on_list_selected(result):
            if result is None:
                return
            if result == "__new__":
                def on_name(name):
                    if not name:
                        return
                    new_file = tasks_dir / f"{name}.md"
                    if not new_file.exists():
                        new_file.write_text(f"# {name.capitalize()}\n")
                    os.system(f"kitty nvim {new_file} &")
                self.push_screen(NewTaskListPopup(), callback=on_name)
            else:
                os.system(f"kitty nvim {result} &")

        self.push_screen(SelectTaskListPopup(lists, self.data_dir), callback=on_list_selected)
