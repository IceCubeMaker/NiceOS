from lupa import LuaRuntime
from datetime import datetime
from typing import Dict, List, Optional
import random
import logging

log = logging.getLogger("taskcli")

class LuaSandbox:
    def __init__(self, all_tasks_dbs, vars_dict, answers_dict, today_date, events, state_mgr):
        """
        all_tasks_dbs: dict of {list_name: {task_id: Task}}
                       The default list (first key, or "tasks") is used by
                       the legacy single-list functions.
        """
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.all_tasks_dbs = all_tasks_dbs  # {list_name: tasks_dict}
        # Default db for legacy functions = first list
        self.tasks_db = next(iter(all_tasks_dbs.values())) if all_tasks_dbs else {}
        self.vars = vars_dict
        self.answers = answers_dict
        self.today_date = today_date
        self.events = events
        self.state_mgr = state_mgr
        self.generated_items = []
        log.debug("LuaSandbox init — loaded lists: %s", list(all_tasks_dbs.keys()))
        for name, db in all_tasks_dbs.items():
            log.debug("  list '%s': %d tasks — %s", name, len(db),
                      [t.text for t in db.values()])
        self._expose_functions()

    def _expose_functions(self):
        lua = self.lua
        # ── Display ───────────────────────────────────────────────────────────
        lua.globals().add_task        = self._add_task
        lua.globals().add_question    = self._add_question
        lua.globals().add_event       = self._add_event
        lua.globals().add_separator   = self._add_separator
        lua.globals().end_group       = self._end_group
        lua.globals().add_mood        = self._add_mood
        lua.globals().add_journal     = self._add_journal
        lua.globals().condition       = self._add_condition
        # ── State ─────────────────────────────────────────────────────────────
        lua.globals().get_var         = self._get_var
        lua.globals().set_var         = self._set_var
        lua.globals().get_answer      = self._get_answer
        lua.globals().task_done       = self._task_done
        lua.globals().is_event_active = self._is_event_active
        # ── Query: legacy single-list ─────────────────────────────────────────
        lua.globals().pick_task        = self._pick_task
        lua.globals().pick_random_task = self._pick_random_task
        # ── Query: multi-list flexible API ───────────────────────────────────
        # tasks_from(list, filter_fn, sort_by, count) → lua table of task ids
        #   list     : string name of the task list file (without .md)
        #   filter_fn: Lua function(t) → bool, or nil to include all undone tasks
        #   sort_by  : one of "priority", "due", "random", "name", nil (=original order)
        #   count    : max number to return, nil = all matching
        lua.globals().tasks_from      = self._tasks_from
        # add_tasks_from(list, filter_fn, sort_by, count) — query + add_task each
        lua.globals().add_tasks_from  = self._add_tasks_from
        # ── Context ───────────────────────────────────────────────────────────
        lua.globals().check_weather   = self._check_weather
        lua.globals().check_location  = self._check_location
        lua.globals().time_of_day     = self._time_of_day
        lua.globals().day_of_week     = self._day_of_week
        lua.globals().date            = self._date
        lua.globals().current_date    = self._current_date

    # ── Internal helpers ──────────────────────────────────────────────────────

    def _get_db(self, list_name=None):
        """Return the tasks dict for a named list, or the default."""
        if list_name is None:
            log.debug("_get_db: no list_name, returning default (%d tasks)", len(self.tasks_db))
            return self.tasks_db
        # Accept with or without .md extension
        name = list_name.replace(".md", "")
        for key in self.all_tasks_dbs:
            if key.replace(".md", "") == name:
                db = self.all_tasks_dbs[key]
                log.debug("_get_db: '%s' matched key '%s' (%d tasks)", name, key, len(db))
                return db
        log.warning("_get_db: list '%s' not found — available: %s", name, list(self.all_tasks_dbs.keys()))
        return {}

    def _task_to_lua_ctx(self, task):
        ctx = self.lua.table()
        ctx.done      = task.done
        ctx.due_date  = task.due_date or ""
        ctx.do_date   = task.do_date or ""
        ctx.priority  = task.priority
        ctx.text      = task.text
        ctx.is_daily  = task.is_daily
        # hashtags as a Lua table {1="tag1", 2="tag2"}
        ht = self.lua.table()
        for i, h in enumerate(task.hashtags, 1):
            ht[i] = h
        ctx.hashtags = ht
        # deps: list of task name strings this task depends on
        dt = self.lua.table()
        for i, d in enumerate(task.deps, 1):
            dt[i] = d
        ctx.deps = dt
        # blocked: true if any named dependency task is not yet done
        blocked = False
        if task.deps:
            for dep_name in task.deps:
                for db in self.all_tasks_dbs.values():
                    for t in db.values():
                        if t.text == dep_name and not t.done:
                            blocked = True
        ctx.blocked = blocked
        return ctx

    def _filter_tasks(self, db, filter_fn):
        """Return list of (tid, task) passing filter_fn (or undone+unblocked if nil)."""
        results = []
        for tid, task in db.items():
            if filter_fn is None:
                if not task.done and not self._is_blocked(task):
                    results.append((tid, task))
            else:
                ctx = self._task_to_lua_ctx(task)
                try:
                    result = filter_fn(ctx)
                    if result is not None and result is not False and result != 0:
                        results.append((tid, task))
                except Exception as e:
                    raise RuntimeError(
                        f"Error in Lua filter function while processing task '{task.text}': {e}"
                    ) from e
        log.debug("_filter_tasks: %d/%d tasks passed (filter_fn=%s)",
                  len(results), len(db), "None" if filter_fn is None else "fn")
        return results

    def _is_blocked(self, task):
        """Return True if any of this task's deps are not yet done."""
        if not task.deps:
            return False
        for dep_name in task.deps:
            for db in self.all_tasks_dbs.values():
                for t in db.values():
                    if t.text == dep_name and not t.done:
                        return True
        return False

    def _sort_tasks(self, pairs, sort_by):
        if sort_by is None or sort_by == "none":
            return pairs
        if sort_by == "priority":
            return sorted(pairs, key=lambda p: -p[1].priority)
        if sort_by == "due":
            def due_key(p):
                d = p[1].due_date
                return d if d else "9999-99-99"
            return sorted(pairs, key=due_key)
        if sort_by == "random":
            lst = list(pairs)
            random.shuffle(lst)
            return lst
        if sort_by == "name":
            return sorted(pairs, key=lambda p: p[1].text.lower())
        return pairs

    # ── Display functions ─────────────────────────────────────────────────────

    def _add_task(self, task_id):
        # Search across all lists
        for db in self.all_tasks_dbs.values():
            if task_id in db:
                task = db[task_id]
                self.generated_items.append(("task", task_id, task.text, task.done))
                return
            for tid, task in db.items():
                if task.text == task_id:
                    self.generated_items.append(("task", tid, task.text, task.done))
                    return
        self.generated_items.append(("task", task_id, task_id, False))

    def _add_question(self, qid, text, options):
        # lupa passes Lua tables as an object with .items() yielding (key, value)
        try:
            opts = [str(v) for _, v in options.items()]
        except AttributeError:
            opts = [str(v) for v in options]
        self.generated_items.append(("question", qid, text, opts))

    def _add_event(self, event_name):
        self.generated_items.append(("event", event_name))

    def _add_separator(self):
        self.generated_items.append(("separator",))

    def _end_group(self):
        """Signal that a conditional block has ended; resets colour grouping without drawing a line."""
        self.generated_items.append(("end_group",))

    def _add_mood(self, prompt="How are you feeling?"):
        self.generated_items.append(("mood", prompt))

    def _add_journal(self, jid, prompt="What's on your mind?"):
        self.generated_items.append(("journal", jid, prompt))

    def _add_condition(self, description, yes_block, no_block):
        self.generated_items.append(("condition", description, yes_block, no_block))

    # ── State functions ───────────────────────────────────────────────────────

    def _get_var(self, name):
        return self.vars.get(name)

    def _set_var(self, name, value):
        self.vars[name] = value

    def _get_answer(self, qid):
        return self.answers.get(qid)

    def _task_done(self, task_id):
        for db in self.all_tasks_dbs.values():
            if task_id in db:
                return db[task_id].done
        return False

    def _is_event_active(self, name):
        now = datetime.now()
        for ev in self.events:
            if ev.get("name") == name:
                if ev.get("once"):
                    return ev.get("date") == self.today_date
                else:
                    start = ev.get("start")
                    end   = ev.get("end")
                    if start and end:
                        tnow = now.time()
                        return start <= tnow <= end
        return False

    # ── Legacy query functions ────────────────────────────────────────────────

    def _pick_task(self, hashtag, condition_expr):
        candidates = []
        for tid, task in self.tasks_db.items():
            if hashtag not in task.hashtags:
                continue
            ctx  = self._task_to_lua_ctx(task)
            func = self.lua.eval(f"return ({condition_expr})")
            if func(ctx):
                candidates.append(tid)
        return candidates[0] if candidates else None

    def _pick_random_task(self, hashtag, condition_expr):
        candidates = []
        for tid, task in self.tasks_db.items():
            if hashtag not in task.hashtags:
                continue
            ctx  = self._task_to_lua_ctx(task)
            func = self.lua.eval(f"return ({condition_expr})")
            if func(ctx):
                candidates.append(tid)
        return random.choice(candidates) if candidates else None

    # ── Flexible multi-list query functions ───────────────────────────────────

    def _normalize_query_args(self, filter_fn, sort_by, count):
        """
        Lupa drops Lua nil arguments entirely instead of passing None, causing
        subsequent args to shift left. For example, Lua:
            add_tasks_from("list", nil, "due", 2)
        arrives in Python as:
            filter_fn="due", sort_by=2, count=None
        We detect this by checking whether filter_fn is a string (which can only
        mean it was actually the sort_by arg that shifted in) or a number, and
        re-map accordingly.
        """
        log.debug("_normalize_query_args IN: filter_fn=%r (type=%s), sort_by=%r (type=%s), count=%r",
                  filter_fn, type(filter_fn).__name__, sort_by, type(sort_by).__name__, count)

        SORT_KEYS = {"priority", "due", "random", "name", "none"}

        if isinstance(filter_fn, str):
            count    = sort_by
            sort_by  = filter_fn
            filter_fn = None
        elif filter_fn is not None and not callable(filter_fn):
            count    = filter_fn
            sort_by  = None
            filter_fn = None
        elif sort_by is not None and not isinstance(sort_by, str):
            count   = sort_by
            sort_by = None

        result = filter_fn, sort_by, (int(count) if count is not None else None)
        log.debug("_normalize_query_args OUT: filter_fn=%r, sort_by=%r, count=%r", *result)
        return result

    def _tasks_from(self, list_name, filter_fn=None, sort_by=None, count=None):
        """
        Query tasks from a named list. Returns a Lua table of task IDs.

        Lua usage:
          -- All undone work tasks by priority, top 3:
          local ids = tasks_from("work", function(t) return not t.done end, "priority", 3)
          for i = 1, #ids do add_task(ids[i]) end

          -- Random undone errand (nil filter is fine):
          local ids = tasks_from("errands", nil, "random", 1)

          -- All overdue tasks:
          local ids = tasks_from("tasks", function(t)
              return not t.done and t.due_date ~= "" and t.due_date < current_date()
          end, "due", nil)
        """
        filter_fn, sort_by, count = self._normalize_query_args(filter_fn, sort_by, count)
        db     = self._get_db(list_name)
        pairs  = self._filter_tasks(db, filter_fn)
        pairs  = self._sort_tasks(pairs, sort_by)
        if count is not None:
            pairs = pairs[:count]
        result = self.lua.table()
        for i, (tid, _) in enumerate(pairs, 1):
            result[i] = tid
        return result

    def _add_tasks_from(self, list_name, filter_fn=None, sort_by=None, count=None):
        """
        Convenience: query and immediately add_task each result.
        """
        log.debug("_add_tasks_from CALLED: list_name=%r, filter_fn=%r, sort_by=%r, count=%r",
                  list_name, type(filter_fn).__name__, sort_by, count)
        filter_fn, sort_by, count = self._normalize_query_args(filter_fn, sort_by, count)
        db     = self._get_db(list_name)
        pairs  = self._filter_tasks(db, filter_fn)
        pairs  = self._sort_tasks(pairs, sort_by)
        if count is not None:
            pairs = pairs[:count]
        log.debug("_add_tasks_from: adding %d tasks from '%s'", len(pairs), list_name)
        for tid, task in pairs:
            log.debug("  + task %s: '%s' (done=%s)", tid, task.text, task.done)
            self.generated_items.append(("task", tid, task.text, task.done))

    # ── Context functions ─────────────────────────────────────────────────────

    def _check_weather(self, location=None):
        return "clear"

    def _check_location(self):
        return {"lat": 0.0, "lng": 0.0}

    def _time_of_day(self):
        now = datetime.now()
        return now.hour * 60 + now.minute

    def _day_of_week(self):
        return datetime.now().strftime("%A")

    def _date(self):
        return datetime.now().strftime("%Y-%m-%d")

    def _current_date(self):
        return self.today_date

    def run_script(self, script_path):
        log.debug("run_script: loading %s", script_path)
        with open(script_path) as f:
            code = f.read()
        code = code.replace("routine", "function")
        try:
            self.lua.execute(code)
        except Exception as e:
            log.error("run_script: Lua compile error: %s", e)
            self.generated_items.append(("lua_error", str(e)))
            return self.generated_items
        main = self.lua.globals().today
        if main is None:
            log.error("run_script: 'today' function not found in Lua globals")
            self.generated_items.append(("lua_error", "'today' function not found in routine.lua"))
            return self.generated_items
        log.debug("run_script: calling today()")
        try:
            main()
        except Exception as e:
            log.error("run_script: error during today(): %s", e)
            self.generated_items.append(("lua_error", str(e)))
        log.debug("run_script: done — %d raw items generated: %s",
                  len(self.generated_items),
                  [(r[0], r[1] if len(r) > 1 else "") for r in self.generated_items])
        return self.generated_items
