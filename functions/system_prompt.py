import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def _read_file(relative_path):
    """Read a file relative to the functions directory."""
    filepath = os.path.join(BASE_DIR, relative_path)
    with open(filepath, "r", encoding="utf-8") as f:
        return f.read()


def get_system_prompt():
    """Compile all tutoring rules into a single system prompt."""

    claude_md = _read_file("CLAUDE.md")
    teaching = _read_file(os.path.join("rules", "teaching-methodology.md"))
    problem_solving = _read_file(os.path.join("rules", "problem-solving.md"))
    common_mistakes = _read_file(os.path.join("rules", "common-mistakes.md"))

    web_instructions = """
## Web Interface Instructions

- Format all mathematical expressions using LaTeX notation:
  - Use $...$ for inline math (e.g., $f'(x) = 2x$)
  - Use $$...$$ for display math (e.g., $$\\int_0^1 x^2 \\, dx = \\frac{1}{3}$$)
- Use standard Markdown for all formatting (headers, bold, lists, code blocks).
- **IMPORTANT: Python/matplotlib visualizations will be automatically executed and displayed.**
  When you want to show a visualization:
  - Write complete, self-contained Python code in a ```python code block
  - Use matplotlib.pyplot as plt and numpy as np (these are available)
  - Include plt.show() at the end (the backend will handle rendering)
  - Add clear labels, titles, and legends to all plots
  - The plot will automatically render as an image inline (the code will be hidden in a collapsible section)
  - After the code block, briefly explain what the visualization shows
- Do not attempt to read PDF files or reference file paths. Instead, cite textbooks
  by name and section (e.g., "See Stewart Section 3.4" or "See OpenStax Section 3.3").
- Keep responses well-structured. Use headers (##) to organize long responses.
- When showing step-by-step solutions, number each step clearly.
"""

    return f"""{claude_md}

---

{teaching}

---

{problem_solving}

---

{common_mistakes}

---

{web_instructions}"""


def get_mode_instruction(mode, user_text):
    """Prepend mode-specific instruction to the user's message."""

    if mode == "explain":
        return (
            "Explain the following calculus concept to help students build deep conceptual "
            "understanding. Focus on getting them unstuck and seeing the big picture. "
            "Use this structure: "
            "(1) Intuition First with a simple real-world analogy, "
            "(2) Visual Representation \u2014 describe or provide a matplotlib code block, "
            "(3) Formal Definition with proper notation, "
            "(4) Simple Worked Example step-by-step, "
            "(5) Common Mistakes to avoid. "
            "Include one real-world application in 1\u20132 sentences. "
            "End with 1\u20132 near-miss practice questions (no solutions). "
            "Keep the initial explanation clear but not exhaustive\u2014students will have buttons "
            "to go deeper or request a different explanation if needed. Use very simple terms when "
            "explaining foundational ideas.\n\n"
            f"Concept/Question: {user_text}"
        )

    elif mode == "solve":
        return (
            "Solve the following calculus problem using Polya's 4-step method: "
            "(1) Understand \u2014 restate and identify given/asked, "
            "(2) Plan \u2014 identify technique and outline strategy, "
            "(3) Execute \u2014 step-by-step with explicit rule citations, "
            "(4) Verify \u2014 check the answer, "
            "(5) Extend \u2014 suggest 1\u20132 related near-miss practice problems (no solutions).\n\n"
            f"Problem: {user_text}"
        )

    elif mode == "quiz":
        return (
            "Generate a quiz on the following topic. Create 5 practice problems "
            "arranged in increasing difficulty (Basic, Basic+, Intermediate, "
            "Intermediate+, Challenge). For computational problems (derivatives, "
            "integrals, limits, algebraic manipulations), provide 4 multiple choice "
            "options labeled A), B), C), D) with exactly one correct answer. Mark "
            "the correct answer using [ANSWER: X] on a new line after the choices "
            "(where X is A, B, C, or D). For conceptual or word problems, omit the "
            "choices and ask for a written explanation. Do NOT reveal solutions or "
            "explanations yet.\n\n"
            f"Topic: {user_text}"
        )

    elif mode == "exam":
        return (
            "Exam mode. Create ONE exam-style problem based on the topic below. "
            "Do NOT solve it yet. Ask the student to respond with their full solution. "
            "When they respond, grade it strictly and briefly: state whether it is correct, "
            "then list 1\u20132 key errors or confirmations and a final answer. Keep a formal, "
            "time-pressured tone.\n\n"
            f"Topic: {user_text}"
        )

    else:
        return user_text


def get_explain_followup_instruction(action, user_text, original_concept=None):
    """Generate instruction for Explain mode follow-up actions."""

    if action == "deeper":
        concept_ref = f" on {original_concept}" if original_concept else ""
        return (
            f"The student wants to go deeper{concept_ref}. Keep the response concise and focused. "
            "Provide at most 4 short bullet points and at most 1 brief example. Prioritize the most "
            "important advanced details, edge cases, or connections; omit extras. Build on the previous explanation.\n\n"
            f"Student request: {user_text}"
        )

    elif action == "differently":
        concept_ref = f": {original_concept}" if original_concept else ""
        return (
            f"The student didn't fully understand the previous explanation{concept_ref}. "
            "Explain it using a COMPLETELY DIFFERENT approach, analogy, or representation. "
            "If the first was algebraic, try visual/graphical. If it was formal, try intuitive. "
            "If it was abstract, use a concrete physical example. Make it simpler and more accessible. "
            "Keep it short: 3\u20135 sentences, at most 1 example, no extra sections.\n\n"
            f"Student request: {user_text}"
        )

    elif action == "verify":
        concept_ref = original_concept if original_concept else "this concept"
        return (
            f"The student feels ready to demonstrate understanding of {concept_ref}. "
            f"Ask them to explain {concept_ref} in their own words. Be encouraging and "
            "specific about what aspects you want them to cover."
        )

    elif action == "review":
        concept_ref = f"{original_concept}" if original_concept else "the concept"
        return (
            f"The student explained {concept_ref} as follows:\n\n\"{user_text}\"\n\n"
            "Review their explanation using this structure:\n"
            "1. **What they got right** \u2014 Affirm correct understanding and good insights\n"
            "2. **Gentle corrections** \u2014 Point out any misconceptions or errors kindly\n"
            "3. **Fill logical gaps** \u2014 Add any important points they missed\n"
            "4. **Next steps** \u2014 If significant gaps remain, offer to re-explain specific "
            "sub-concepts or suggest they practice with an example."
        )

    else:
        return user_text
