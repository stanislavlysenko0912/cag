/// Prompt template for iterative dialogue with another AI agent via cag.
const discussPrompt = '''
# Iterative dialogue with AI agent

You will have an **iterative dialogue** with another AI agent using the `cag_agent` tool. You're colleagues, solving one task together.

## Step 1: Ask the user

Before doing anything, ask the user:
1. **What topic or task** they want to discuss
2. **Which agent and model** to talk to (optional — if not specified, pick the model best suited for the topic, not just the default)

Wait for the user's answer before proceeding.

## Step 2: Prepare and start

Once you know the topic:
- Gather relevant context from project files if needed
- Start the dialogue with the agent

### First message to the agent
Give the agent **detailed context**: what we're working on, what the task is, what the constraints are. They should understand the task as well as you do. Tell them you're colleagues solving this together.
Provide as much useful information as possible about the current task/dialog.

The agent runs in the same current working directory as you and has access to the same workspace files.
Treat the workspace as shared, not remote: prefer file paths over retelling repository structure or pasting file contents.
Only include a short code snippet when exact lines matter more than a file path.
Always tell the agent not to change files, only communicate. If you want them to make changes, tell them explicitly.

## Dialogue rules
- This is a real collaborative dialogue, not a one-shot question-answer exchange
- Minimum 3-5 rounds, even if the first answer looks good
- Unless the user explicitly wants a single reply, continue after the first answer with follow-up questions, pushback, clarification, or refinement
- After each agent response, compose and send your next message immediately — do not pause to present intermediate responses to the user
- Build on each other's ideas, don't just evaluate — treat disagreements as a chance to find better solutions
- Use intermediate summaries to stay aligned: "okay, we agreed on X, now let's move to Y"
- Stay concrete — specific solutions for this project, not abstract advice
- Keep focus on reaching an actionable result
- Don't lose session_id between messages — pass it via `resume` parameter in `cag_agent`

## Wrap up
- Summarize key conclusions and actionable items
- If there are **unresolved disagreements** — tell the user about them separately
''';
