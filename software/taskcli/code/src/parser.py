import re
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional


class Task:
    __slots__ = ("id", "text", "done", "parent_id", "hashtags", "due_date",
                 "do_date", "priority", "is_daily", "line_num", "raw_line", "deps")

    def __init__(self, id: str, text: str, done: bool, parent_id: Optional[str],
                 hashtags: List[str], due_date: Optional[str] = None,
                 do_date: Optional[str] = None, priority: int = 0,
                 is_daily: bool = False, line_num: int = 0, raw_line: str = "",
                 deps: Optional[List[str]] = None):
        self.id = id
        self.text = text
        self.done = done
        self.parent_id = parent_id
        self.hashtags = hashtags
        self.due_date = due_date
        self.do_date = do_date
        self.priority = priority
        self.is_daily = is_daily
        self.line_num = line_num
        self.raw_line = raw_line
        self.deps = deps or []   # list of task name strings that must be done first


class TaskParser:
    def __init__(self, file_path: Path):
        self.file_path = file_path
        self.tasks: Dict[str, Task] = {}
        self.root_tasks: List[str] = []

    def parse(self):
        if not self.file_path.exists():
            return
        lines = self.file_path.read_text().splitlines()
        stack = []
        id_counter = 0
        self.tasks = {}
        self.root_tasks = []

        for line_num, raw_line in enumerate(lines, 1):
            stripped = raw_line.strip()
            if not stripped or not stripped.startswith("- [") or stripped[3] not in " x":
                continue
            indent = len(raw_line) - len(raw_line.lstrip())
            while stack and indent <= stack[-1][0]:
                stack.pop()
            parent_id = stack[-1][1] if stack else None
            done = stripped[3] == "x"
            text_part = stripped[5:].strip()
            hashtags = []
            due_date = None
            do_date = None
            priority = 0
            is_daily = False
            deps = []
            if "!daily" in text_part:
                is_daily = True
                text_part = text_part.replace("!daily", "").strip()
            for word in text_part.split():
                if word.startswith("#") and len(word) > 1:
                    hashtags.append(word[1:])
            for h in hashtags:
                text_part = text_part.replace(f"#{h}", "").strip()
            due_match = re.search(r"due:(\d{4}-\d{2}-\d{2})", text_part)
            if due_match:
                due_date = due_match.group(1)
                text_part = text_part.replace(due_match.group(0), "").strip()
            do_match = re.search(r"do:(\d{4}-\d{2}-\d{2})", text_part)
            if do_match:
                do_date = do_match.group(1)
                text_part = text_part.replace(do_match.group(0), "").strip()
            prio_match = re.search(r"priority:(\d+)", text_part)
            if prio_match:
                priority = int(prio_match.group(1))
                text_part = text_part.replace(prio_match.group(0), "").strip()
            # dep:"Task name" — task is blocked until named task is done
            for dep_match in re.finditer(r'dep:"([^"]+)"', text_part):
                deps.append(dep_match.group(1))
            text_part = re.sub(r'dep:"[^"]+"', "", text_part).strip()
            text = re.sub(r"\s+", " ", text_part).strip()
            task_id = f"task_{id_counter}"
            id_counter += 1
            task = Task(task_id, text, done, parent_id, hashtags, due_date,
                        do_date, priority, is_daily, line_num, raw_line, deps)
            self.tasks[task_id] = task
            if parent_id is None:
                self.root_tasks.append(task_id)
            stack.append((indent, task_id))
        self.root_tasks.sort(key=lambda tid: self.tasks[tid].line_num)

    def rewrite_task(self, task_id: str, done: bool):
        if task_id not in self.tasks:
            return
        task = self.tasks[task_id]
        if task.is_daily:
            return
        lines = self.file_path.read_text().splitlines()
        old_line = lines[task.line_num - 1]
        if done:
            new_line = old_line.replace("- [ ]", "- [x]", 1)
        else:
            new_line = old_line.replace("- [x]", "- [ ]", 1)
        lines[task.line_num - 1] = new_line
        self.file_path.write_text("\n".join(lines))
        task.done = done



class TaskParser:
    def __init__(self, file_path: Path):
        self.file_path = file_path
        self.tasks: Dict[str, Task] = {}
        self.root_tasks: List[str] = []

    def parse(self):
        if not self.file_path.exists():
            return
        lines = self.file_path.read_text().splitlines()
        stack = []
        id_counter = 0
        self.tasks = {}
        self.root_tasks = []

        for line_num, raw_line in enumerate(lines, 1):
            stripped = raw_line.strip()
            if not stripped or not stripped.startswith("- [") or stripped[3] not in " x":
                continue
            indent = len(raw_line) - len(raw_line.lstrip())
            while stack and indent <= stack[-1][0]:
                stack.pop()
            parent_id = stack[-1][1] if stack else None
            done = stripped[3] == "x"
            text_part = stripped[5:].strip()
            hashtags = []
            due_date = None
            do_date = None
            priority = 0
            is_daily = False
            if "!daily" in text_part:
                is_daily = True
                text_part = text_part.replace("!daily", "").strip()
            for word in text_part.split():
                if word.startswith("#") and len(word) > 1:
                    hashtags.append(word[1:])
            for h in hashtags:
                text_part = text_part.replace(f"#{h}", "").strip()
            due_match = re.search(r"due:(\d{4}-\d{2}-\d{2})", text_part)
            if due_match:
                due_date = due_match.group(1)
                text_part = text_part.replace(due_match.group(0), "").strip()
            do_match = re.search(r"do:(\d{4}-\d{2}-\d{2})", text_part)
            if do_match:
                do_date = do_match.group(1)
                text_part = text_part.replace(do_match.group(0), "").strip()
            prio_match = re.search(r"priority:(\d+)", text_part)
            if prio_match:
                priority = int(prio_match.group(1))
                text_part = text_part.replace(prio_match.group(0), "").strip()
            text = re.sub(r"\s+", " ", text_part).strip()
            task_id = f"task_{id_counter}"
            id_counter += 1
            task = Task(task_id, text, done, parent_id, hashtags, due_date,
                        do_date, priority, is_daily, line_num, raw_line)
            self.tasks[task_id] = task
            if parent_id is None:
                self.root_tasks.append(task_id)
            stack.append((indent, task_id))
        self.root_tasks.sort(key=lambda tid: self.tasks[tid].line_num)

    def rewrite_task(self, task_id: str, done: bool):
        if task_id not in self.tasks:
            return
        task = self.tasks[task_id]
        if task.is_daily:
            return
        lines = self.file_path.read_text().splitlines()
        old_line = lines[task.line_num - 1]
        if done:
            new_line = old_line.replace("- [ ]", "- [x]", 1)
        else:
            new_line = old_line.replace("- [x]", "- [ ]", 1)
        lines[task.line_num - 1] = new_line
        self.file_path.write_text("\n".join(lines))
        task.done = done
