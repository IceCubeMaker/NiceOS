import json
import uuid
from pathlib import Path
from datetime import datetime, date as date_type


class StateManager:
    def __init__(self, data_dir):
        self.data_dir = Path(data_dir)
        self.state_file = self.data_dir / "state.json"
        self.vars_file = self.data_dir / "vars.json"
        self.events_file = self.data_dir / "events.json"
        self.mood_file = self.data_dir / "mood.json"
        self.state = {}
        self.vars = {}
        self.events = []
        self.mood_log = []

    def load(self):
        if self.state_file.exists():
            with open(self.state_file) as f:
                self.state = json.load(f)
        if self.vars_file.exists():
            with open(self.vars_file) as f:
                self.vars = json.load(f)
        if self.events_file.exists():
            with open(self.events_file) as f:
                self.events = json.load(f)
        if self.mood_file.exists():
            with open(self.mood_file) as f:
                self.mood_log = json.load(f)

    def save_state(self):
        with open(self.state_file, "w") as f:
            json.dump(self.state, f, indent=2)

    def save_vars(self):
        with open(self.vars_file, "w") as f:
            json.dump(self.vars, f, indent=2)

    def save_events(self):
        with open(self.events_file, "w") as f:
            json.dump(self.events, f, indent=2)

    def save_mood(self):
        with open(self.mood_file, "w") as f:
            json.dump(self.mood_log, f, indent=2)

    def get_day_state(self, day_str):
        return self.state.get(day_str, {})

    def set_day_state(self, day_str, day_state):
        self.state[day_str] = day_state
        self.save_state()

    # ── Day item snapshot (freeze past days) ──────────────────────────────────

    def freeze_day(self, day_str, items):
        """Persist a serialisable snapshot of generated_items for a past day."""
        safe = []
        for it in items:
            d = {k: v for k, v in it.items()
                 if isinstance(v, (str, int, float, bool, list, dict, type(None)))}
            # task_obj is a Task instance — not JSON-safe, drop it
            d.pop("task_obj", None)
            # Lua function refs are also not JSON-safe
            d.pop("yes_block", None)
            d.pop("no_block", None)
            safe.append(d)
        day = self.state.setdefault(day_str, {})
        day["frozen_items"] = safe
        self.save_state()

    def get_frozen_items(self, day_str):
        """Return the frozen item list for a past day, or None if not yet frozen."""
        return self.state.get(day_str, {}).get("frozen_items")

    def set_answer(self, day_str, qid, answer):
        day = self.state.setdefault(day_str, {})
        answers = day.setdefault("answers", {})
        answers[qid] = answer
        self.save_state()

    def get_answer(self, day_str, qid):
        return self.state.get(day_str, {}).get("answers", {}).get(qid)

    def set_mood_done(self, day_str, mood_key):
        day = self.state.setdefault(day_str, {})
        done = day.setdefault("mood_done", [])
        if mood_key not in done:
            done.append(mood_key)
        self.save_state()

    def is_mood_done(self, day_str, mood_key):
        return mood_key in self.state.get(day_str, {}).get("mood_done", [])

    def set_task_done(self, day_str, task_id, done):
        day = self.state.setdefault(day_str, {})
        done_set = set(day.get("done_tasks", []))
        if done:
            done_set.add(task_id)
        else:
            done_set.discard(task_id)
        day["done_tasks"] = list(done_set)
        self.save_state()

    def is_task_done_today(self, day_str, task_id):
        return task_id in self.state.get(day_str, {}).get("done_tasks", [])

    def get_item_order(self, day_str):
        """Return the saved manual ordering of item keys for this day, or []."""
        return self.state.get(day_str, {}).get("item_order", [])

    def set_item_order(self, day_str, order):
        day = self.state.setdefault(day_str, {})
        day["item_order"] = order
        self.save_state()

    def get_extra_tasks(self, day_str):
        """Return list of {text} dicts for tasks added manually during the day."""
        return self.state.get(day_str, {}).get("extra_tasks", [])

    def add_extra_task(self, day_str, text):
        day = self.state.setdefault(day_str, {})
        extras = day.setdefault("extra_tasks", [])
        key = f"extra:{len(extras)}:{text}"
        extras.append({"key": key, "text": text})
        self.save_state()
        return key


    # ── Calendar events ───────────────────────────────────────────────────────

    def add_calendar_event(self, ev_dict, current_day):
        """Add a new calendar event. Assigns an id and anchors one-off to current_day."""
        ev = dict(ev_dict)
        ev["id"] = str(uuid.uuid4())[:8]
        if ev.get("type", "once") == "once":
            ev["date"] = current_day.isoformat() if hasattr(current_day, "isoformat") else current_day
        elif ev.get("type") == "weekly":
            ev["weekday"] = current_day.weekday() if hasattr(current_day, "weekday") else 0
        elif ev.get("type") == "monthly":
            ev["monthday"] = current_day.day if hasattr(current_day, "day") else 1
        elif ev.get("type") == "yearly":
            ev["month"] = current_day.month if hasattr(current_day, "month") else 1
            ev["monthday"] = current_day.day if hasattr(current_day, "day") else 1
        self.events.append(ev)
        self.save_events()

    def delete_calendar_event(self, event_id):
        self.events = [e for e in self.events if e.get("id") != event_id]
        self.save_events()

    def get_events_for_day(self, day):
        """Return all events that fall on `day` (a date object)."""
        if hasattr(day, "isoformat"):
            day_str = day.isoformat()
            weekday = day.weekday()
            monthday = day.day
            month = day.month
        else:
            # fallback: treat as string
            day_str = str(day)
            weekday = monthday = month = None

        result = []
        for ev in self.events:
            t = ev.get("type", "once")
            if t == "once":
                if ev.get("date") == day_str:
                    result.append(ev)
            elif t == "daily":
                result.append(ev)
            elif t == "weekly":
                if ev.get("weekday") == weekday:
                    result.append(ev)
            elif t == "monthly":
                if ev.get("monthday") == monthday:
                    result.append(ev)
            elif t == "yearly":
                if ev.get("month") == month and ev.get("monthday") == monthday:
                    result.append(ev)
        # Sort by time (None = all-day, sort first)
        result.sort(key=lambda e: e.get("time") or "00:00")
        return result


    # ── Journal entries ───────────────────────────────────────────────────────

    def set_journal_entry(self, day_str, jid, text):
        day = self.state.setdefault(day_str, {})
        journal = day.setdefault("journal", {})
        journal[jid] = text
        self.save_state()

    def get_journal_entry(self, day_str, jid):
        return self.state.get(day_str, {}).get("journal", {}).get(jid, "")

    def get_all_journal_entries(self, day_str):
        """Return {jid: text} dict for a given day."""
        return self.state.get(day_str, {}).get("journal", {})

    def add_mood_entry(self, mood_emoji):
        self.mood_log.append({
            "timestamp": datetime.now().isoformat(),
            "mood": mood_emoji
        })
        self.save_mood()

    def get_mood_stats(self):
        return self.mood_log
