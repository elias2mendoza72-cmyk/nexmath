from firebase_functions import https_fn, options
from firebase_admin import initialize_app, firestore
from anthropic import Anthropic
from system_prompt import get_system_prompt, get_mode_instruction, get_explain_followup_instruction
import os
import uuid
import re
import subprocess
import sys
import tempfile
import base64
import json
import time

initialize_app()

# Model configuration
MODEL = os.environ.get("CLAUDE_MODEL", "claude-sonnet-4-20250514")
MAX_TOKENS = 4096
MAX_MESSAGES = 40
_PLOT_PYTHON = None


def trim_conversation(messages):
    """Keep conversation within context limits."""
    if len(messages) <= MAX_MESSAGES:
        return messages
    return messages[:2] + messages[-(MAX_MESSAGES - 2):]


def execute_python_code(code):
    """Execute Python matplotlib code and return base64-encoded PNG."""
    try:
        def _sanitize_code(raw):
            lines = raw.splitlines()
            cleaned = []
            code_like = re.compile(
                r'^\s*(#|import |from |plt\.|np\.|matplotlib|sns\.|ax\.|fig\.|'
                r'for |if |elif |else:|while |def |class |with |try:|except |return|'
                r'pass|break|continue|[A-Za-z_][A-Za-z0-9_]*(\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*\s*=|'
                r'[A-Za-z_][A-Za-z0-9_]*\s*\(|[\]\)\}])'
            )
            for line in lines:
                if "```" in line:
                    continue
                if line.strip() == "":
                    cleaned.append(line)
                    continue
                if code_like.search(line):
                    cleaned.append(line)
                else:
                    cleaned.append("# " + line)
            return "\n".join(cleaned)

        sanitized_code = re.sub(r'^\s*plt\.show\(\)\s*$', '', code, flags=re.MULTILINE)
        sanitized_code = _sanitize_code(sanitized_code)

        wrapper = f"""
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

# User code
{sanitized_code}

# Save the figure
plt.savefig('plot.png', dpi=100, bbox_inches='tight')
plt.close()
"""
        with tempfile.TemporaryDirectory() as tmpdir:
            script_path = os.path.join(tmpdir, 'script.py')
            plot_path = os.path.join(tmpdir, 'plot.png')

            with open(script_path, 'w') as f:
                f.write(wrapper)

            result = subprocess.run(
                [_get_plot_python(), script_path],
                cwd=tmpdir,
                capture_output=True,
                timeout=15,
                text=True
            )

            if os.path.exists(plot_path):
                with open(plot_path, 'rb') as f:
                    img_data = base64.b64encode(f.read()).decode('utf-8')
                return img_data

            if result.stderr:
                print(f"Plot stderr: {result.stderr}")
            if result.returncode != 0:
                print(f"Plot process exited with code {result.returncode}")
            return None

    except Exception as e:
        print(f"Code execution error: {e}")
        return None


def _get_plot_python():
    """Pick a Python interpreter with matplotlib installed."""
    global _PLOT_PYTHON
    if _PLOT_PYTHON:
        return _PLOT_PYTHON

    for candidate in (sys.executable, "python3"):
        try:
            check = subprocess.run(
                [candidate, "-c", "import matplotlib, numpy"],
                capture_output=True, text=True, timeout=5
            )
            if check.returncode == 0:
                _PLOT_PYTHON = candidate
                return _PLOT_PYTHON
        except Exception:
            continue

    _PLOT_PYTHON = sys.executable
    return _PLOT_PYTHON


def process_response_with_plots(text, allow_plots=True):
    """Find Python code blocks in the response, execute them, and replace with images."""
    if not allow_plots:
        return text

    pattern = r'```[^\n]*\r?\n(.*?)```'

    def replace_code_block(match):
        code = match.group(1)
        if 'matplotlib' in code or 'plt.' in code:
            img_base64 = execute_python_code(code)
            if img_base64:
                return f'''<div class="plot-container">
<img src="data:image/png;base64,{img_base64}" alt="Plot" class="matplotlib-plot">
</div>'''
        return match.group(0)

    processed = re.sub(pattern, replace_code_block, text, flags=re.DOTALL)

    if processed == text and ("matplotlib" in text or "plt." in text):
        lines = text.splitlines()
        start_idx = None
        code_line_re = re.compile(
            r'^\s*(#|import |from |plt\.|np\.|[A-Za-z_][A-Za-z0-9_]*\s*=|[A-Za-z_][A-Za-z0-9_]*\s*\()'
        )

        for i, line in enumerate(lines):
            if re.search(r'^\s*(import matplotlib|from matplotlib|import numpy|import matplotlib\.pyplot)', line) or "plt." in line:
                start_idx = i
                break

        if start_idx is not None:
            end_idx = None
            for i in range(start_idx, len(lines)):
                if code_line_re.search(lines[i]) or lines[i].strip() == "":
                    end_idx = i
                else:
                    if end_idx is not None and i > end_idx + 1:
                        break

            if end_idx is not None:
                code = "\n".join(lines[start_idx:end_idx + 1])
                img_base64 = execute_python_code(code)
                if img_base64:
                    image_html = (
                        f'<div class="plot-container">'
                        f'<img src="data:image/png;base64,{img_base64}" alt="Plot" class="matplotlib-plot">'
                        f'</div>'
                    )
                    before = "\n".join(lines[:start_idx])
                    after = "\n".join(lines[end_idx + 1:])
                    return "\n".join([before, image_html, after]).strip()

    return processed


def _user_asked_for_plot(text):
    if not text:
        return False
    return re.search(r"\b(plot|graph|visual|visualize|chart|draw)\b", text, re.IGNORECASE) is not None


def _build_prefixed_text(mode, user_text, explain_action, original_concept, show_steps, explain_style, exam_answer, image_data):
    """Build the prefixed text for the Claude API request."""
    if mode == "exam" and exam_answer:
        prefixed_text = (
            "Exam grading mode. The student is answering the previous exam problem. "
            "Grade strictly and briefly: state whether it is correct, list 1-2 key errors "
            "or confirmations, and give the final answer. Keep a formal, time-pressured tone.\n\n"
            f"Student answer: {user_text}"
        )
    elif mode == "explain" and explain_action:
        prefixed_text = get_explain_followup_instruction(
            explain_action, user_text, original_concept
        )
    else:
        prefixed_text = get_mode_instruction(mode, user_text)
        if mode == "solve" and not show_steps:
            prefixed_text += "\n\nKeep the response concise. Do not show step-by-step work; provide only the final answer with a brief justification."
        if mode == "solve":
            prefixed_text += "\n\nInclude a 1-2 sentence real-world application."
    if mode == "explain":
        if explain_style == "equation":
            prefixed_text += "\n\nStart with the formal definition/equation first, then provide intuition and examples."
        else:
            prefixed_text += "\n\nStart with intuition first, then introduce formal definitions/equations."
    if mode in ("solve", "explain"):
        prefixed_text += "\n\nEnd with a short 'Key takeaway' section (1-2 sentences)."

    if image_data:
        prefixed_text += "\n\nIf an image is provided, first transcribe the problem clearly before solving."

    return prefixed_text


def _make_cors_headers():
    """Return CORS headers for the response."""
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
    }


@https_fn.on_request(
    memory=options.MemoryOption.GB_1,
    timeout_sec=120,
    secrets=["ANTHROPIC_API_KEY"],
)
def chat(req: https_fn.Request) -> https_fn.Response:
    """Main chat endpoint — replaces /api/chat from Flask."""

    # Handle CORS preflight
    if req.method == "OPTIONS":
        return https_fn.Response("", status=204, headers=_make_cors_headers())

    if req.method != "POST":
        return https_fn.Response(
            json.dumps({"error": "Method not allowed"}),
            status=405,
            headers={**_make_cors_headers(), "Content-Type": "application/json"},
        )

    data = req.get_json(silent=True) or {}

    user_text = data.get("message", "").strip()
    image_data = data.get("image")
    image_type = data.get("image_type")
    mode = data.get("mode", "solve")
    session_id = data.get("session_id")
    explain_action = data.get("explain_action")
    original_concept = data.get("original_concept")
    plot_mode = data.get("plot_mode", "on_demand")
    show_steps = data.get("show_steps", True)
    explain_style = data.get("explain_style", "intuition")
    exam_answer = data.get("exam_answer", False)

    if not user_text and not image_data:
        return https_fn.Response(
            json.dumps({"error": "Please provide a message or image."}),
            status=400,
            headers={**_make_cors_headers(), "Content-Type": "application/json"},
        )

    if not user_text and image_data:
        user_text = "Please analyze this calculus problem and help me understand how to approach it."

    # Build the prefixed message
    prefixed_text = _build_prefixed_text(
        mode, user_text, explain_action, original_concept,
        show_steps, explain_style, exam_answer, image_data
    )

    # Firestore for conversation persistence
    db = firestore.client()

    if not session_id:
        session_id = str(uuid.uuid4())

    conv_ref = db.collection("conversations").document(session_id)
    conv_doc = conv_ref.get()

    if conv_doc.exists:
        messages = conv_doc.to_dict().get("messages", [])
    else:
        messages = []

    # Build content blocks for Claude API
    content = []
    if image_data:
        content.append({
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": image_type,
                "data": image_data,
            },
        })
    content.append({"type": "text", "text": prefixed_text})

    messages.append({"role": "user", "content": content})
    messages = trim_conversation(messages)

    try:
        client = Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))

        response = client.messages.create(
            model=MODEL,
            max_tokens=MAX_TOKENS,
            system=get_system_prompt(),
            messages=messages,
        )

        assistant_text = response.content[0].text

        # Process matplotlib plots
        allow_plots = plot_mode == "auto" or _user_asked_for_plot(user_text)
        processed_text = process_response_with_plots(assistant_text, allow_plots=allow_plots)

        # Store assistant response (original text for conversation history)
        messages.append({"role": "assistant", "content": assistant_text})

        # Save to Firestore
        conv_ref.set({
            "messages": messages,
            "last_accessed": time.time(),
        })

        return https_fn.Response(
            json.dumps({"response": processed_text, "session_id": session_id}),
            status=200,
            headers={**_make_cors_headers(), "Content-Type": "application/json"},
        )

    except Exception as e:
        # Remove failed user message
        if messages and messages[-1].get("role") == "user":
            messages.pop()
        print(f"Chat error: {e}")
        return https_fn.Response(
            json.dumps({"error": str(e)}),
            status=500,
            headers={**_make_cors_headers(), "Content-Type": "application/json"},
        )


@https_fn.on_request(
    memory=options.MemoryOption.MB_256,
    timeout_sec=10,
)
def health(req: https_fn.Request) -> https_fn.Response:
    """Health check endpoint."""
    if req.method == "OPTIONS":
        return https_fn.Response("", status=204, headers=_make_cors_headers())

    return https_fn.Response(
        json.dumps({"status": "ok", "model": MODEL}),
        status=200,
        headers={**_make_cors_headers(), "Content-Type": "application/json"},
    )
