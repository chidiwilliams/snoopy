# Snoopy

A native macOS menu-bar prototype that checks the upper-right notification-banner area every two seconds. When that area changes substantially and contains readable text, it sends the cropped image and OCR hint to Codex CLI. Codex immediately acknowledges the request in a Slack self-DM, researches it with current sources, and follows up with the answer. Results stay in the menu and log dashboard rather than generating another notification, which avoids a feedback loop.

Built for [Agents Everywhere: Beyond the Chatbot — Global Hackathon with OpenAI](https://nyc.aitinkerers.org/p/agents-everywhere-beyond-the-chatbot-global-hackathon-with-openai).

## Build and run

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "outputs/Snoopy.app"
```

Use the bell icon in the menu bar to grant Screen Recording permission, configure Codex's working directory and additional instruction, and send a test notification. Each test rotates to a different impatient coworker and research request.

Snoopy writes activity to `~/Library/Logs/Snoopy/snoopy.log`. Choose **Open Logs Dashboard** from the menu to view the live log at `http://127.0.0.1:8765`; the server listens only on the local loopback interface.

The app invokes `codex --search exec` with GPT-5.6 Luna at low reasoning using the installed Codex CLI and Slack plugin. Screenshot crops and CLI output are placed in a temporary directory only while Codex is processing them, then deleted.
