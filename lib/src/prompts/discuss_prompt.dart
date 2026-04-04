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

Always provide paths to current files related to context — the agent runs in the same directory, so they can see files by themselves. You don't need to duplicate file contents, only maybe a related part of code that can be better than just a file path.
Always tell the agent not to change files, only communicate. If you want them to make changes, tell them explicitly.

## Dialogue rules
- Minimum 3-5 rounds, more if productive
- Build on each other's ideas, don't just evaluate — treat disagreements as a chance to find better solutions
- Use intermediate summaries to stay aligned: "okay, we agreed on X, now let's move to Y"
- Stay concrete — specific solutions for this project, not abstract advice
- Keep focus on reaching an actionable result
- Don't lose session_id between messages — pass it via `resume` parameter in `cag_agent`

## Wrap up
- Summarize key conclusions and actionable items
- If there are **unresolved disagreements** — tell the user about them separately
''';
