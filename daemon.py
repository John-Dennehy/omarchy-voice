# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "websockets>=12.0",
# ]
# ///

import os
import sys
import json
import base64
import asyncio
import subprocess
from pathlib import Path

# Setup environment & PATH
MISE_SHIMS = Path.home() / ".local/share/mise/shims"
USER_BIN = Path.home() / ".local/bin"
os.environ["PATH"] = f"{MISE_SHIMS}:{USER_BIN}:/usr/local/bin:/usr/bin:{os.environ.get('PATH', '')}"

# Storage directories
CONFIG_DIR = Path.home() / ".config/omarchy/voice"
STATE_DIR = Path.home() / ".local/state/omarchy/voice"
CONFIG_DIR.mkdir(parents=True, exist_ok=True)
STATE_DIR.mkdir(parents=True, exist_ok=True)

CONFIG_FILE = CONFIG_DIR / "config.json"
ENV_FILE = CONFIG_DIR / "env"
PARKING_LOT_FILE = STATE_DIR / "parking-lot.json"

# API Key resolution:
# 1. GEMINI_API_KEY environment variable
# 2. ~/.config/omarchy/voice/env
# 3. Fallback to local .env (development only)
API_KEY = os.environ.get("GEMINI_API_KEY")
if not API_KEY and ENV_FILE.exists():
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "GEMINI_API_KEY=" in line:
            API_KEY = line.split("GEMINI_API_KEY=", 1)[1].strip().strip('"').strip("'")
            break

if not API_KEY:
    local_env = Path(__file__).parent / ".env"
    if local_env.exists():
        for line in local_env.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "GEMINI_API_KEY=" in line:
                API_KEY = line.split("GEMINI_API_KEY=", 1)[1].strip().strip('"').strip("'")
                break

if not API_KEY:
    sys.stdout.write(json.dumps({
        "event": "error",
        "message": "GEMINI_API_KEY not found. Set it in environment or ~/.config/omarchy/voice/env"
    }) + "\n")
    sys.stdout.flush()
    sys.exit(1)

WS_URL = f"wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key={API_KEY}"

def run_cmd(cmd, timeout=30):
    res = subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=timeout)
    return res.stdout.strip(), res.stderr.strip(), res.returncode

# 1. Dynamic User Identity
def resolve_user_identity():
    login = os.environ.get("USER", "developer")
    name = "Developer"
    stdout, _, code = run_cmd("gh api user --jq '{login: .login, name: .name}'", timeout=5)
    if code == 0 and stdout:
        try:
            data = json.loads(stdout)
            login = data.get("login") or login
            name = data.get("name") or login
        except:
            pass
    else:
        git_name, _, git_code = run_cmd("git config user.name", timeout=3)
        if git_code == 0 and git_name:
            name = git_name
    return login, name

GITHUB_USER, USER_NAME = resolve_user_identity()

# 2. Dynamic Repository Discovery
def discover_user_repos():
    repos = []
    # Fetch from GitHub CLI
    stdout, _, code = run_cmd("gh repo list --limit 25 --json name,description", timeout=8)
    if code == 0 and stdout:
        try:
            data = json.loads(stdout)
            for r in data:
                repos.append({
                    "name": r["name"],
                    "desc": r.get("description") or "Repository"
                })
        except:
            pass

    # Fallback to scanning ~/Projects if gh is not authenticated
    if not repos:
        projects_dir = Path.home() / "Projects"
        if projects_dir.exists():
            for p in projects_dir.iterdir():
                if p.is_dir() and (p / ".git").exists():
                    repos.append({"name": p.name, "desc": "Local project"})
    return repos

DISCOVERED_REPOS = discover_user_repos()

# 3. Load User Preferences from config.json
user_config = {}
if CONFIG_FILE.exists():
    try:
        user_config = json.loads(CONFIG_FILE.read_text())
    except:
        pass

preferred_voice = user_config.get("voice", {}).get("name", "Charon")
preferred_accent = user_config.get("voice", {}).get("accent", "british")
user_style = user_config.get("user", {}).get("style", "AuDHD pair programming, thinking out loud, low executive load")
custom_principles = user_config.get("principles", [
    "1 fork: limit active work-in-progress to one branch",
    "eat the frog: tackle highest-friction blockers first",
    "bang for buck: evaluate tasks by highest leverage"
])

# State variables
active_project = DISCOVERED_REPOS[0]["name"] if DISCOVERED_REPOS else "main"
is_muted = False
is_ready = False
current_speaker = None
current_mic = None

def get_parking_lot_data():
    if PARKING_LOT_FILE.exists():
        try:
            return json.loads(PARKING_LOT_FILE.read_text())
        except:
            return []
    return []

def save_parking_lot_data(data):
    PARKING_LOT_FILE.write_text(json.dumps(data, indent=2))

def emit(event, **kwargs):
    payload = {"event": event, **kwargs}
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()

# Tool implementations
def tool_list_repos(args=None):
    return {"repos": DISCOVERED_REPOS}

def tool_switch_project(args):
    global active_project
    repo = args.get("repo", "").strip()
    if repo:
        active_project = repo.replace(f"{GITHUB_USER}/", "")
        emit("project", active=active_project, repos=DISCOVERED_REPOS, user=GITHUB_USER)
        return {"success": True, "active_project": active_project, "message": f"Switched active context to {active_project}"}
    return {"error": "No repository specified"}

def tool_list_issues(args):
    target_repo = args.get("repo") or active_project
    repo = target_repo if "/" in target_repo else f"{GITHUB_USER}/{target_repo}"
    limit = args.get("limit", 5)
    stdout, stderr, code = run_cmd(f"gh issue list --repo '{repo}' --limit {limit} --json number,title,state,url")
    if code == 0:
        try:
            issues = json.loads(stdout)
            return {"repo": repo, "count": len(issues), "issues": issues}
        except:
            return {"repo": repo, "raw": stdout}
    return {"error": stderr or "Failed to list issues", "repo": repo}

def tool_create_issue(args):
    target_repo = args.get("repo") or active_project
    repo = target_repo if "/" in target_repo else f"{GITHUB_USER}/{target_repo}"
    title = args.get("title", "")
    body = args.get("body", "Created via Voice Assistant")
    cmd = f"gh issue create --repo '{repo}' --title {json.dumps(title)} --body {json.dumps(body)}"
    stdout, stderr, code = run_cmd(cmd)
    if code == 0:
        url = stdout.strip()
        emit("tool_created_issue", repo=repo, title=title, url=url)
        return {"success": True, "url": url, "repo": repo, "message": f"Created issue in {repo}: {url}"}
    return {"error": stderr or "Failed to create issue"}

def tool_get_summary(args):
    target_repo = args.get("repo") or active_project
    repo = target_repo if "/" in target_repo else f"{GITHUB_USER}/{target_repo}"
    stdout, _, _ = run_cmd(f"gh repo view '{repo}'")
    return {"repo": repo, "summary": stdout[:1500]}

def tool_create_or_update_file(args):
    target_repo = args.get("repo") or active_project
    repo = target_repo if "/" in target_repo else f"{GITHUB_USER}/{target_repo}"
    path = args.get("path", "").lstrip("/")
    content = args.get("content", "")
    message = args.get("commit_message", f"Update {path}")
    
    content_b64 = base64.b64encode(content.encode("utf-8")).decode("utf-8")
    existing_sha, _, _ = run_cmd(f"gh api repos/{repo}/contents/{path} --jq .sha")
    
    cmd = f"gh api --method PUT repos/{repo}/contents/{path} -f message={json.dumps(message)} -f content={json.dumps(content_b64)}"
    if existing_sha:
        cmd += f" -f sha={json.dumps(existing_sha)}"
    
    stdout, stderr, code = run_cmd(cmd)
    if code == 0:
        try:
            res = json.loads(stdout)
            url = res.get("content", {}).get("html_url", f"https://github.com/{repo}/blob/main/{path}")
            return {"success": True, "file": path, "repo": repo, "url": url}
        except:
            return {"success": True, "file": path, "repo": repo}
    return {"error": stderr or "Failed to commit file"}

def tool_park_idea(args):
    thought = args.get("thought", "").strip()
    target_repo = args.get("repo") or active_project
    if not thought:
        return {"error": "No thought provided"}
    
    items = get_parking_lot_data()
    item = {
        "id": len(items) + 1,
        "thought": thought,
        "repo": target_repo,
        "created_at": subprocess.getoutput("date -Iseconds")
    }
    items.append(item)
    save_parking_lot_data(items)
    emit("parking_lot", items=items)
    return {"success": True, "parked": item, "message": f"Safely parked idea for {target_repo}: '{thought}'"}

def tool_get_parking_lot(args=None):
    items = get_parking_lot_data()
    return {"count": len(items), "items": items}

def get_desktop_context():
    try:
        out = subprocess.getoutput("hyprctl activewindow -j")
        win = json.loads(out)
        pid = win.get("pid")
        cwd = ""
        repo = None
        if pid:
            try:
                cwd = os.readlink(f"/proc/{pid}/cwd")
                children = subprocess.getoutput(f"pgrep -P {pid}").split()
                if children:
                    cwd = os.readlink(f"/proc/{children[-1]}/cwd")
            except:
                pass
        if cwd and (Path(cwd) / ".git").exists():
            repo = Path(cwd).name
        elif win.get("title"):
            title = win["title"].lower()
            for r in DISCOVERED_REPOS:
                if r["name"].lower() in title:
                    repo = r["name"]
                    break
        return {
            "title": win.get("title", ""),
            "class": win.get("class", ""),
            "cwd": cwd,
            "detected_repo": repo
        }
    except:
        return {}

def tool_get_desktop_context(args=None):
    return get_desktop_context()

def tool_ask_agent(args):
    task = args.get("task", "")
    # Check default agent
    default_agent, _, _ = run_cmd("omarchy-default-agent", timeout=3)
    default_agent = default_agent or "agy"
    
    if default_agent == "agy":
        cmd = f"agy --dangerously-skip-permissions -p {json.dumps(task)}"
    elif default_agent == "claude":
        cmd = f"claude --permission-mode auto -p {json.dumps(task)}"
    elif default_agent == "codex":
        cmd = f"codex --approve-for-me -p {json.dumps(task)}"
    else:
        cmd = f"omarchy-agent --inline --prompt {json.dumps(task)}"
        
    stdout, stderr, code = run_cmd(cmd, timeout=60)
    return {"agent": default_agent, "task": task, "response": (stdout or stderr)[:2000]}

TOOLS_MAP = {
    "get_desktop_context": tool_get_desktop_context,
    "list_my_repos": tool_list_repos,
    "switch_project": tool_switch_project,
    "list_github_issues": tool_list_issues,
    "create_github_issue": tool_create_issue,
    "get_repo_summary": tool_get_summary,
    "create_or_update_file": tool_create_or_update_file,
    "park_idea": tool_park_idea,
    "get_parking_lot": tool_get_parking_lot,
    "ask_agent": tool_ask_agent,
}

TOOL_DECLARATIONS = [
    {
        "name": "switch_project",
        "description": "Switches the active project context to another repository.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "repo": {"type": "STRING", "description": "Repository name"}
            },
            "required": ["repo"]
        }
    },
    {
        "name": "list_my_repos",
        "description": "Lists the user's available repositories and descriptions.",
        "parameters": {"type": "OBJECT", "properties": {}}
    },
    {
        "name": "list_github_issues",
        "description": "Lists open issues in a repository.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "repo": {"type": "STRING", "description": "Repository name (defaults to active project)"},
                "limit": {"type": "INTEGER", "description": "Max number of issues"}
            }
        }
    },
    {
        "name": "create_github_issue",
        "description": "Creates a new issue in a GitHub repository without requiring manual copy-pasting.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "repo": {"type": "STRING", "description": "Target repository (defaults to active project)"},
                "title": {"type": "STRING", "description": "Title of the issue"},
                "body": {"type": "STRING", "description": "Details / description"}
            },
            "required": ["title"]
        }
    },
    {
        "name": "get_repo_summary",
        "description": "Gets details and README summary of a repository.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "repo": {"type": "STRING", "description": "Repository name"}
            }
        }
    },
    {
        "name": "create_or_update_file",
        "description": "Creates or updates a file directly in a GitHub repository and commits it.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "repo": {"type": "STRING", "description": "Target repository"},
                "path": {"type": "STRING", "description": "Relative file path"},
                "content": {"type": "STRING", "description": "File content"},
                "commit_message": {"type": "STRING", "description": "Commit message"}
            },
            "required": ["path", "content"]
        }
    },
    {
        "name": "park_idea",
        "description": "Stashes a spontaneous tangent or idea into the session parking lot so it is never lost.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "thought": {"type": "STRING", "description": "The idea or insight to park"},
                "repo": {"type": "STRING", "description": "Which project it relates to"}
            },
            "required": ["thought"]
        }
    },
    {
        "name": "get_parking_lot",
        "description": "Retrieves the list of parked ideas captured during the session.",
        "parameters": {"type": "OBJECT", "properties": {}}
    },
    {
        "name": "get_desktop_context",
        "description": "Returns real-time desktop context: active window title, application class, working directory, and detected git repo.",
        "parameters": {"type": "OBJECT", "properties": {}}
    },
    {
        "name": "ask_agent",
        "description": "Delegates a deep code analysis, search, or refactor to the system default AI agent.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "task": {"type": "STRING", "description": "Instruction for the AI agent"}
            },
            "required": ["task"]
        }
    }
]

# Build dynamic system instruction
repo_catalog_summary = "\n".join([f"- {r['name']}: {r['desc']}" for r in DISCOVERED_REPOS[:15]])
principles_summary = "\n".join([f"- {p}" for p in custom_principles])

SYSTEM_INSTRUCTION = f"""You are an empathetic, proactive Technical Lead and executive function partner for {USER_NAME} (@{GITHUB_USER}).
You speak with a naturally deep, warm, low-pitched British accent (Standard Southern British / RP, Charon voice) with natural British developer cadence ("Right, let's have a look", "Sorted", "All done", "No worries", "Cheers"). Always maintain a calm, relaxed, low baritone voice.

### User Working Style:
{user_style}

### User Core Principles & Heuristics:
{principles_summary}

### Discovered Repositories:
{repo_catalog_summary}

### Prime Directives:
1. Autonomous Capture:
- When {USER_NAME} verbalizes an idea, principle, architectural decision, bug, or feature, DO NOT ask for permission or prompt for formatting.
- Take autonomous initiative: immediately call `create_github_issue` or `park_idea`.
- Formulate a crisp, professional title and concise body from spoken words.
- Confirm with a single punchy sentence: e.g. "Sorted. Logged an issue on {active_project} for that."

2. Automatic Semantic Domain Routing:
- Classify ideas to the appropriate repository automatically based on the user's repo catalog.
- If a tangent relates to another project, route the capture to that repo and seamlessly note it.

3. Situational Awareness:
- Use `get_desktop_context` when needed to see what window, application, or repo {USER_NAME} is looking at on screen.

4. Executive Function Support & Tangent Grounding:
- Tangents are creative sparks. Catch them immediately via `park_idea` or `create_github_issue`, then gently ground {USER_NAME} back to the main thread.
- If {USER_NAME} feels overwhelmed or paralyzed by options, apply the core principles to narrow down to ONE single bite-sized step.

5. Voice Economy:
- Keep spoken turns to 1–3 natural, punchy sentences. Never recite long lists or read raw code aloud."""

def stop_speaker():
    global current_speaker
    if current_speaker:
        try:
            current_speaker.stdin.close()
        except:
            pass
        try:
            current_speaker.terminate()
        except:
            pass
        current_speaker = None

def get_speaker():
    global current_speaker
    if current_speaker is None or current_speaker.poll() is not None:
        current_speaker = subprocess.Popen(
            ["pw-cat", "-p", "--raw", "--rate", "24000", "--channels", "1", "--format", "s16", "-"],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
    return current_speaker

async def audio_mic_loop(ws):
    global is_ready, is_muted, current_mic
    proc = await asyncio.create_subprocess_exec(
        "pw-cat", "-r", "--raw", "--rate", "16000", "--channels", "1", "--format", "s16", "-",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL
    )
    current_mic = proc
    try:
        while True:
            chunk = await proc.stdout.read(1024)
            if not chunk:
                break
            if is_ready and not is_muted:
                b64_data = base64.b64encode(chunk).decode("utf-8")
                msg = {
                    "realtimeInput": {
                        "mediaChunks": [
                            {"mimeType": "audio/pcm;rate=16000", "data": b64_data}
                        ]
                    }
                }
                await ws.send(json.dumps(msg))
    except asyncio.CancelledError:
        pass
    finally:
        try:
            proc.terminate()
        except:
            pass
        current_mic = None

async def control_reader_loop(ws):
    global is_muted, active_project
    loop = asyncio.get_event_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)
    
    cmd_file = Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")) / "voice-assistant.cmd"

    while True:
        try:
            line = await asyncio.wait_for(reader.readline(), timeout=0.5)
            line = line.decode().strip()
            if line:
                if line == "toggle_mute":
                    is_muted = not is_muted
                    emit("muted", isMuted=is_muted)
                elif line.startswith("switch_project "):
                    p = line.split(" ", 1)[1].strip()
                    tool_switch_project({"repo": p})
                elif line.startswith("park_idea "):
                    thought = line.split(" ", 1)[1].strip()
                    tool_park_idea({"thought": thought})
                elif line == "quit":
                    sys.exit(0)
        except asyncio.TimeoutError:
            pass
        
        if cmd_file.exists():
            try:
                cmd = cmd_file.read_text().strip()
                cmd_file.unlink(missing_ok=True)
                if cmd == "toggle_mute":
                    is_muted = not is_muted
                    emit("muted", isMuted=is_muted)
                elif cmd.startswith("switch_project "):
                    p = cmd.split(" ", 1)[1].strip()
                    tool_switch_project({"repo": p})
                elif cmd.startswith("park_idea "):
                    thought = cmd.split(" ", 1)[1].strip()
                    tool_park_idea({"thought": thought})
            except:
                pass

async def main():
    global is_ready, active_project
    import websockets

    # Check initial desktop context
    dt = get_desktop_context()
    if dt.get("detected_repo"):
        active_project = dt["detected_repo"]

    emit("status", state="connecting", title="Connecting...", sub="Initiating native Gemini Live session...")
    
    async with websockets.connect(WS_URL) as ws:
        setup_msg = {
            "setup": {
                "model": "models/gemini-2.5-flash-native-audio-latest",
                "generationConfig": {
                    "responseModalities": ["AUDIO"],
                    "speechConfig": {
                        "voiceConfig": {
                            "prebuiltVoiceConfig": {
                                "voiceName": preferred_voice
                            }
                        }
                    }
                },
                "systemInstruction": {
                    "parts": [{"text": SYSTEM_INSTRUCTION}]
                },
                "tools": [
                    {"functionDeclarations": TOOL_DECLARATIONS}
                ]
            }
        }
        await ws.send(json.dumps(setup_msg))
        
        mic_task = asyncio.create_task(audio_mic_loop(ws))
        ctrl_task = asyncio.create_task(control_reader_loop(ws))
        
        emit("project", active=active_project, repos=DISCOVERED_REPOS, user=GITHUB_USER)
        emit("parking_lot", items=get_parking_lot_data())

        try:
            async for raw in ws:
                data = json.loads(raw)
                
                if "setupComplete" in data:
                    is_ready = True
                    emit("ready", state="listening", title="Listening", sub="Speak freely anytime", activeProject=active_project, user=GITHUB_USER)
                
                if "serverContent" in data:
                    sc = data["serverContent"]
                    if sc.get("interrupted"):
                        stop_speaker()
                        emit("status", state="listening", title="Listening", sub="Speak freely anytime")
                    
                    if "modelTurn" in sc:
                        for part in sc["modelTurn"].get("parts", []):
                            if "text" in part:
                                emit("transcript", role="assistant", text=part["text"])
                            if "inlineData" in part:
                                emit("status", state="speaking", title="Speaking...", sub="Assistant speaking")
                                pcm_bytes = base64.b64decode(part["inlineData"]["data"])
                                spk = get_speaker()
                                if spk and spk.stdin:
                                    try:
                                        spk.stdin.write(pcm_bytes)
                                        spk.stdin.flush()
                                    except:
                                        pass
                    
                    if sc.get("turnComplete"):
                        emit("status", state="listening", title="Listening", sub="Speak freely anytime")
                
                if "toolCall" in data:
                    tc = data["toolCall"]
                    responses = []
                    for call in tc.get("functionCalls", []):
                        call_id = call.get("id")
                        name = call.get("name")
                        args = call.get("args", {})
                        
                        emit("tool", status="running", name=name, detail=str(args))
                        handler = TOOLS_MAP.get(name)
                        if handler:
                            try:
                                result = handler(args)
                            except Exception as e:
                                result = {"error": str(e)}
                        else:
                            result = {"error": f"Tool {name} not found"}
                        
                        emit("tool", status="done", name=name, result=result)
                        if name == "create_github_issue" and result.get("success"):
                            emit("transcript", role="tool", text=f"Created issue in {result.get('repo')}: {result.get('url')}")
                        elif name == "switch_project" and result.get("success"):
                            emit("transcript", role="tool", text=f"Switched active context to: {result.get('active_project')}")
                        elif name == "park_idea" and result.get("success"):
                            emit("transcript", role="tool", text=f"Parked thought for {result.get('parked', {}).get('repo')}: '{result.get('parked', {}).get('thought')}'")
                        
                        responses.append({
                            "id": call_id,
                            "response": {"output": result}
                        })
                    
                    resp_msg = {
                        "toolResponse": {
                            "functionResponses": responses
                        }
                    }
                    await ws.send(json.dumps(resp_msg))
                    
        except asyncio.CancelledError:
            pass
        finally:
            mic_task.cancel()
            ctrl_task.cancel()
            stop_speaker()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
    except Exception as e:
        emit("error", message=str(e))
