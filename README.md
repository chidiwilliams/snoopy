# Snoopy

Snoopy helps you execute tasks in the background by watching your notifications while you work. When an actionable request appears, Snoopy hands it to Codex, keeps you updated in Slack, and sends you the result when the work is done.

Built with Codex for [Agents Everywhere: Beyond the Chatbot](https://nyc.aitinkerers.org/p/agents-everywhere-beyond-the-chatbot-global-hackathon-with-openai) in New York City on September 12, 2026.

## Build and run

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "outputs/Snoopy.app"
```

Use the bell icon in the menu bar to grant Screen Recording permission, configure Codex's working directory and additional instruction, and send a test notification. Each test rotates to a different impatient coworker and research request.

Snoopy writes activity to `~/Library/Logs/Snoopy/snoopy.log`. Choose **Open Logs Dashboard** from the menu to view the live log at `http://127.0.0.1:8765`; the server listens only on the local loopback interface.

The app invokes `codex --search exec` with GPT-5.6 Luna at low reasoning using the installed Codex CLI and Slack plugin. Screenshot crops and CLI output are placed in a temporary directory only while Codex is processing them, then deleted.
