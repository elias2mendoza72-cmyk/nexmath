from flask import Flask, request, jsonify, render_template, Response, stream_with_context
from anthropic import Anthropic
from dotenv import load_dotenv
from system_prompt import get_system_prompt, get_mode_instruction, get_explain_followup_instruction
import os
import uuid
import re
import subprocess
import sys
import tempfile
import base64
import json

load_dotenv()

app = Flask(__name__)

# In-memory conversation storage
conversations = {}

# Initialize Anthropic client
client = Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))

# Model configuration
MODEL = os.environ.get("CLAUDE_MODEL", "claude-sonnet-4-20250514")
MAX_TOKENS = 4096
MAX_MESSAGES = 40
_PLOT_PYTHON = None


def trim_conversation(messages):
    """Keep conversation within context limits."""
    if len(messages) <= MAX_MESSAGES:
        return messages
    # Keep the first exchange for context + most recent messages
    return messages[:2] + messages[-(MAX_MESSAGES - 2):]


def execute_python_code(code):
    """
    Execute Python matplotlib code and return base64-encoded PNG.
    Returns None if execution fails.
    """
    try:
        # Create a wrapper script that saves the plot
        # Remove any blocking show() calls to avoid timeouts
        sanitized_code = re.sub(r'^\s*plt\.show\(\)\s*$', '', code, flags=re.MULTILINE)

        wrapper = f"""
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
import matplotlib.pyplot as plt
import numpy as np

# User code
{sanitized_code}

# Save the figure
plt.savefig('plot.png', dpi=100, bbox_inches='tight')
plt.close()
"""

        # Create temporary directory for execution
        with tempfile.TemporaryDirectory() as tmpdir:
            script_path = os.path.join(tmpdir, 'script.py')
            plot_path = os.path.join(tmpdir, 'plot.png')

            # Write script
            with open(script_path, 'w') as f:
                f.write(wrapper)

            # Execute with timeout (5 seconds)
            result = subprocess.run(
                [_get_plot_python(), script_path],
                cwd=tmpdir,
                capture_output=True,
                timeout=15,
                text=True
            )

            # Check if plot was created
            if os.path.exists(plot_path):
                with open(plot_path, 'rb') as f:
                    img_data = base64.b64encode(f.read()).decode('utf-8')
                return img_data5

            if result.stderr:
                print(f"Plot stderr: {result.stderr}")
            if result.stdout:
                print(f"Plot stdout: {result.stdout}")
            if result.returncode != 0:
                print(f"Plot process exited with code {result.returncode}")
            else:
                print("Plot execution completed but no plot was generated.")
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
                capture_output=True,
                text=True,
                timeout=5
            )
            if check.returncode == 0:
                _PLOT_PYTHON = candidate
                return _PLOT_PYTHON
        except Exception:
            continue

    _PLOT_PYTHON = sys.executable
    return _PLOT_PYTHON


def process_response_with_plots(text, allow_plots=True):
    """
    Find Python code blocks in the response, execute them, and replace with images.
    """
    if not allow_plots:
        return text
    # Pattern to match any fenced code block (handle CRLF)
    pattern = r'```[^\n]*\r?\n(.*?)```'

    def replace_code_block(match):
        code = match.group(1)

        # Only execute if it contains matplotlib usage
        if 'matplotlib' in code or 'plt.' in code:
            img_base64 = execute_python_code(code)

            if img_base64:
                # Replace with image only (no code block shown)
                return f'''<div class="plot-container">
<img src="data:image/png;base64,{img_base64}" alt="Plot" class="matplotlib-plot">
</div>'''

        # If execution failed or no matplotlib, keep original code block
        return match.group(0)

    processed = re.sub(pattern, replace_code_block, text, flags=re.DOTALL)

    # Fallback: if no fenced blocks matched but matplotlib code appears, try to extract it
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
                    # Stop when we hit a clear prose line after code started
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


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/chat", methods=["POST"])
def chat():
    data = request.json

    user_text = data.get("message", "").strip()
    image_data = data.get("image")  # base64 string or None
    image_type = data.get("image_type")  # e.g., "image/jpeg"
    mode = data.get("mode", "solve")
    session_id = data.get("session_id")
    explain_action = data.get("explain_action")  # "deeper", "differently", "verify", "review"
    original_concept = data.get("original_concept")  # Track concept being explained
    plot_mode = data.get("plot_mode", "on_demand")  # "auto" or "on_demand"
    show_steps = data.get("show_steps", True)
    explain_style = data.get("explain_style", "intuition")

    # Need either text or image
    if not user_text and not image_data:
        return jsonify({"error": "Please provide a message or image."}), 400

    # Default text when only an image is sent
    if not user_text and image_data:
        user_text = (
            "Please analyze this calculus problem and help me "
            "understand how to approach it."
        )

    # Apply mode instruction (or follow-up instruction for Explain mode)
    if mode == "explain" and explain_action:
        prefixed_text = get_explain_followup_instruction(
            explain_action, user_text, original_concept
        )
    else:
        prefixed_text = get_mode_instruction(mode, user_text)
        if mode == "solve" and not show_steps:
            prefixed_text += "\n\nKeep the response concise. Do not show step-by-step work; provide only the final answer with a brief justification."
    if mode == "explain":
        if explain_style == "equation":
            prefixed_text += "\n\nStart with the formal definition/equation first, then provide intuition and examples."
        else:
            prefixed_text += "\n\nStart with intuition first, then introduce formal definitions/equations."
    if mode in ("solve", "explain"):
        prefixed_text += "\n\nEnd with a short 'Key takeaway' section (1–2 sentences)."

    # Session management
    if not session_id or session_id not in conversations:
        session_id = str(uuid.uuid4())
        conversations[session_id] = []

    # Build content blocks for Claude API
    content = []
    if image_data:
        content.append(
            {
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": image_type,
                    "data": image_data,
                },
            }
        )
    content.append({"type": "text", "text": prefixed_text})

    # Add user message to history
    conversations[session_id].append({"role": "user", "content": content})

    # Trim if needed
    conversations[session_id] = trim_conversation(conversations[session_id])

    try:
        response = client.messages.create(
            model=MODEL,
            max_tokens=MAX_TOKENS,
            system=get_system_prompt(),
            messages=conversations[session_id],
        )

        assistant_text = response.content[0].text

        # Process Python code blocks and execute matplotlib plots
        allow_plots = plot_mode == "auto" or _user_asked_for_plot(user_text)
        processed_text = process_response_with_plots(assistant_text, allow_plots=allow_plots)

        # Store assistant response (original text for conversation history)
        conversations[session_id].append(
            {"role": "assistant", "content": assistant_text}
        )

        return jsonify({"response": processed_text, "session_id": session_id})

    except Exception as e:
        # Remove the failed user message from history
        conversations[session_id].pop()
        return jsonify({"error": str(e)}), 500


@app.route("/api/chat-stream", methods=["POST"])
def chat_stream():
    data = request.json

    user_text = data.get("message", "").strip()
    image_data = data.get("image")  # base64 string or None
    image_type = data.get("image_type")  # e.g., "image/jpeg"
    mode = data.get("mode", "solve")
    session_id = data.get("session_id")
    explain_action = data.get("explain_action")  # "deeper", "differently", "verify", "review"
    original_concept = data.get("original_concept")  # Track concept being explained
    plot_mode = data.get("plot_mode", "on_demand")  # "auto" or "on_demand"
    show_steps = data.get("show_steps", True)
    explain_style = data.get("explain_style", "intuition")

    # Need either text or image
    if not user_text and not image_data:
        return jsonify({"error": "Please provide a message or image."}), 400

    # Default text when only an image is sent
    if not user_text and image_data:
        user_text = (
            "Please analyze this calculus problem and help me "
            "understand how to approach it."
        )

    # Apply mode instruction (or follow-up instruction for Explain mode)
    if mode == "explain" and explain_action:
        prefixed_text = get_explain_followup_instruction(
            explain_action, user_text, original_concept
        )
    else:
        prefixed_text = get_mode_instruction(mode, user_text)
        if mode == "solve" and not show_steps:
            prefixed_text += "\n\nKeep the response concise. Do not show step-by-step work; provide only the final answer with a brief justification."
    if mode == "explain":
        if explain_style == "equation":
            prefixed_text += "\n\nStart with the formal definition/equation first, then provide intuition and examples."
        else:
            prefixed_text += "\n\nStart with intuition first, then introduce formal definitions/equations."
    if mode in ("solve", "explain"):
        prefixed_text += "\n\nEnd with a short 'Key takeaway' section (1–2 sentences)."

    # Session management
    if not session_id or session_id not in conversations:
        session_id = str(uuid.uuid4())
        conversations[session_id] = []

    # Build content blocks for Claude API
    content = []
    if image_data:
        content.append(
            {
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": image_type,
                    "data": image_data,
                },
            }
        )
    content.append({"type": "text", "text": prefixed_text})

    # Add user message to history
    conversations[session_id].append({"role": "user", "content": content})

    # Trim if needed
    conversations[session_id] = trim_conversation(conversations[session_id])

    def generate():
        assistant_text_parts = []
        try:
            with client.messages.stream(
                model=MODEL,
                max_tokens=MAX_TOKENS,
                system=get_system_prompt(),
                messages=conversations[session_id],
            ) as stream:
                for text in stream.text_stream:
                    if not text:
                        continue
                    assistant_text_parts.append(text)
                    payload = {"type": "delta", "text": text}
                    yield f"data: {json.dumps(payload)}\n\n"

            assistant_text = "".join(assistant_text_parts)
            allow_plots = plot_mode == "auto" or _user_asked_for_plot(user_text)
            processed_text = process_response_with_plots(assistant_text, allow_plots=allow_plots)

            conversations[session_id].append(
                {"role": "assistant", "content": assistant_text}
            )

            done_payload = {
                "type": "done",
                "response": processed_text,
                "session_id": session_id,
            }
            yield f"data: {json.dumps(done_payload)}\n\n"
        except Exception as e:
            if conversations.get(session_id):
                conversations[session_id].pop()
            error_payload = {"type": "error", "error": str(e)}
            yield f"data: {json.dumps(error_payload)}\n\n"

    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache"},
    )


@app.route("/api/new-session", methods=["POST"])
def new_session():
    session_id = str(uuid.uuid4())
    conversations[session_id] = []
    return jsonify({"session_id": session_id})


@app.route("/api/health", methods=["GET"])
def health():
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return (
            jsonify(
                {"status": "error", "message": "ANTHROPIC_API_KEY not set in .env"}
            ),
            500,
        )
    return jsonify({"status": "ok", "model": MODEL})


# Allow Flask to work behind ngrok proxy
from werkzeug.middleware.proxy_fix import ProxyFix
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)


if __name__ == "__main__":
    print("Starting NexMath...")
    print("Open http://localhost:5001 in your browser")
    app.run(debug=True, port=5001, host='0.0.0.0')
