import click
import os
import sys
from pathlib import Path

DATA_DIR = Path.home() / ".local/share/taskcli"
TASKS_DIR = DATA_DIR / "tasks"


@click.group()
def cli():
    pass


@cli.command()
def init():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    TASKS_DIR.mkdir(exist_ok=True)
    (TASKS_DIR / "tasks.md").write_text(
        "# Tasks\n"
        "- [ ] Buy milk #errand !daily\n"
        "- [ ] Write report #work due:2025-12-25 priority:10\n"
        "- [x] Call dentist #personal\n"
    )
    (DATA_DIR / "routine.lua").write_text('-- routine.lua — edit freely. Press \'e\' in the TUI to open this file.\n-- ─────────────────────────────────────────────────────────────────────────────\n-- TASK QUERY FUNCTIONS\n-- ─────────────────────────────────────────────────────────────────────────────\n-- add_tasks_from(list, filter_fn, sort_by, count)\n--   Adds tasks from a named list directly to today\'s view.\n--   list      : list filename without .md  (e.g. "tasks", "work", "errands")\n--   filter_fn : function(t) → bool, or nil for all undone\n--               t.done (bool), t.text, t.priority (int), t.due_date (string),\n--               t.do_date, t.is_daily, t.hashtags (table of strings)\n--   sort_by   : "priority" | "due" | "random" | "name" | nil\n--   count     : max number to add, or nil for all matching\n--\n-- tasks_from(list, filter_fn, sort_by, count) → table of task IDs\n--   Same but returns a table so you can loop or inspect before adding:\n--   local ids = tasks_from("work", nil, "priority", 3)\n--   for i = 1, #ids do add_task(ids[i]) end\n--\n-- add_task("Task name or ID")      add a specific task by name\n-- add_separator()                  draw a horizontal divider\n-- end_group()                      end colour grouping (no divider drawn)\n-- add_mood("How are you feeling?") mood check-in (emoji picker)\n-- add_question("id", "text", {"A","B","C"})  multiple choice\n-- condition("Are you X?", function() ... end, function() ... end)  yes/no branch\n--\n-- CONTEXT\n-- day_of_week()   → "Monday" … "Sunday"\n-- time_of_day()   → minutes since midnight  (9:30am = 570)\n-- current_date()  → "YYYY-MM-DD" for the viewed day\n-- get_answer("id")→ last answer to a question, or nil\n-- get_var("k") / set_var("k", v)  persistent variables across days\n-- ─────────────────────────────────────────────────────────────────────────────\n\n-- Helper: true if today matches any of the given day names\nfunction on(...)\n    local today = day_of_week()\n    for _, d in ipairs({...}) do\n        if today == d then return true end\n    end\n    return false\nend\n\n-- Helper: true if current time is within [start_min, end_min] (minutes)\nfunction between(start_min, end_min)\n    local t = time_of_day()\n    return t >= start_min and t <= end_min\nend\n\nroutine today()\n\n    -- Mood check-in at the top of every day\n    add_mood("How are you starting the day?")\n    add_separator()\n\n    -- Morning: surface the single highest-priority undone task\n    if between(0, 719) then\n        add_tasks_from("tasks", function(t) return not t.done end, "priority", 1)\n    end\n    end_group()\n\n    -- Weekdays\n    if on("Monday", "Tuesday", "Wednesday", "Thursday", "Friday") then\n        add_separator()\n\n        -- One random undone task from the work list (create tasks/work.md to use this)\n        add_tasks_from("work", function(t) return not t.done end, "random", 1)\n\n        add_question("focus_area", "What\'s your main focus today?",\n            {"Deep work", "Meetings", "Errands", "Rest"})\n\n        local focus = get_answer("focus_area")\n        if focus == "Deep work" then\n            -- Top 2 high-priority tasks\n            add_tasks_from("tasks", function(t)\n                return not t.done and t.priority >= 5\n            end, "priority", 2)\n        elseif focus == "Errands" then\n            -- Random errand (create tasks/errands.md to use this)\n            add_tasks_from("errands", nil, "random", 1)\n        end\n        end_group()\n    end\n\n    -- Weekends: a random personal task\n    if on("Saturday", "Sunday") then\n        add_separator()\n        add_tasks_from("tasks", function(t)\n            for i = 1, #t.hashtags do\n                if t.hashtags[i] == "personal" then return true end\n            end\n            return false\n        end, "random", 1)\n        end_group()\n    end\n\n    -- Always: surface any overdue tasks\n    add_separator()\n    add_tasks_from("tasks", function(t)\n        return not t.done and t.due_date ~= "" and t.due_date < current_date()\n    end, "due", nil)\n\nend\n')
    (DATA_DIR / "vars.json").write_text("{}")
    (DATA_DIR / "state.json").write_text("{}")
    (DATA_DIR / "events.json").write_text("[]")
    (DATA_DIR / "mood.json").write_text("[]")
    click.echo(f"Initialized {DATA_DIR}")
    click.echo(f"Task lists are in {TASKS_DIR}")


@cli.command()
def edit():
    """Edit the routine script in nvim."""
    os.system(f"nvim {DATA_DIR / 'routine.lua'}")


@cli.command()
@click.argument("list_name", default="tasks")
def tasks(list_name):
    """Edit a task list. Defaults to 'tasks'. Pass a name to edit or create another list."""
    TASKS_DIR.mkdir(exist_ok=True)
    target = TASKS_DIR / f"{list_name}.md"
    if not target.exists():
        target.write_text(f"# {list_name.capitalize()}\n")
        click.echo(f"Created {target}")
    os.system(f"$EDITOR {target}")


@cli.command(name="list")
def list_tasks():
    """List all task list files."""
    TASKS_DIR.mkdir(exist_ok=True)
    files = sorted(TASKS_DIR.glob("*.md"))
    if not files:
        click.echo("No task lists found. Run `taskcli init` first.")
        return
    for f in files:
        import re
        text = f.read_text()
        total = len(re.findall(r"- \[[ x]\]", text))
        done  = len(re.findall(r"- \[x\]", text))
        click.echo(f"  {f.stem:20s}  {done}/{total} done")


@cli.command()
def today():
    """Launch the TUI for today's routine."""
    from .tui_app import TaskListApp
    app = TaskListApp(DATA_DIR)
    app.run()


if __name__ == "__main__":
    cli()
