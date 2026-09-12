import Foundation
import Network

final class LogServer {
    static let port: UInt16 = 8765
    static let dashboardURL = URL(string: "http://127.0.0.1:\(port)")!

    private let logger: SnoopyLog
    private let queue = DispatchQueue(label: "com.chidiwilliams.snoopy.log-server")
    private var listener: NWListener?

    init(logger: SnoopyLog) {
        self.logger = logger
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: Self.port)!
        )

        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("Log dashboard ready at \(Self.dashboardURL.absoluteString)")
            case .failed(let error):
                self?.logger.error("Log dashboard failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }
            guard error == nil, let data,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let response: Data
            switch path.split(separator: "?").first.map(String.init) ?? path {
            case "/logs":
                response = self.httpResponse(
                    status: "200 OK",
                    contentType: "text/plain; charset=utf-8",
                    body: Data(self.logger.contents().utf8)
                )
            case "/", "/index.html":
                response = self.httpResponse(
                    status: "200 OK",
                    contentType: "text/html; charset=utf-8",
                    body: Data(Self.dashboardHTML.utf8)
                )
            default:
                response = self.httpResponse(
                    status: "404 Not Found",
                    contentType: "text/plain; charset=utf-8",
                    body: Data("Not found".utf8)
                )
            }

            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func httpResponse(status: String, contentType: String, body: Data) -> Data {
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        X-Content-Type-Options: nosniff\r
        \r

        """
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private static let dashboardHTML = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta name="theme-color" content="#080b09">
      <title>Snoopy // Operations Console</title>
      <style>
        :root {
          color-scheme: dark;
          --bg: #080b09;
          --panel: #0d120f;
          --panel-raised: #131a16;
          --border: #27312a;
          --border-strong: #465348;
          --text: #e7eee9;
          --muted: #8d9b91;
          --subtle: #566259;
          --green: #7ce3a1;
          --amber: #e5b766;
          --red: #f07872;
          --blue: #7db8d3;
          --mono: "SFMono-Regular", "SF Mono", ui-monospace, Menlo, Consolas, monospace;
          font-family: var(--mono);
        }
        * { box-sizing: border-box; }
        html { min-width: 320px; background: var(--bg); }
        body {
          margin: 0;
          min-height: 100vh;
          background-color: var(--bg);
          background-image:
            linear-gradient(rgba(124, 227, 161, .025) 1px, transparent 1px),
            linear-gradient(90deg, rgba(124, 227, 161, .025) 1px, transparent 1px);
          background-size: 32px 32px;
          color: var(--text);
        }
        body::after {
          content: "";
          position: fixed;
          inset: 0;
          z-index: 100;
          pointer-events: none;
          background: repeating-linear-gradient(0deg, transparent 0 3px, rgba(0,0,0,.08) 3px 4px);
          opacity: .32;
        }
        button, input { font: inherit; }
        button { color: inherit; }
        button:focus-visible, input:focus-visible {
          outline: 2px solid var(--blue);
          outline-offset: 2px;
        }
        .shell { width: min(1480px, 100%); margin: 0 auto; }
        .topbar {
          position: sticky;
          top: 0;
          z-index: 10;
          display: flex;
          align-items: center;
          min-height: 74px;
          padding: 0 28px;
          background: rgba(8, 11, 9, .92);
          border-bottom: 1px solid var(--border);
          backdrop-filter: blur(18px) saturate(150%);
        }
        .brand { display: flex; align-items: center; gap: 14px; min-width: 0; }
        .mark {
          display: grid;
          place-items: center;
          width: 40px;
          height: 40px;
          border: 1px solid #3b5a46;
          background: #101813;
          box-shadow: inset 0 0 18px rgba(124,227,161,.08), 0 0 24px rgba(0,0,0,.3);
          color: var(--green);
          font-size: 19px;
        }
        h1 { margin: 2px 0 0; font-size: 15px; letter-spacing: .16em; text-transform: uppercase; }
        .eyebrow { color: var(--green); font-size: 9px; letter-spacing: .2em; text-transform: uppercase; }
        .subtitle { margin-top: 4px; color: var(--muted); font-size: 10px; letter-spacing: .08em; text-transform: uppercase; }
        .node-id { color: var(--subtle); }
        .connection {
          display: inline-flex;
          align-items: center;
          gap: 7px;
          margin-left: auto;
          padding: 6px 10px;
          border: 1px solid var(--border);
          border-radius: 2px;
          background: var(--panel);
          color: var(--muted);
          font-size: 10px;
          letter-spacing: .09em;
          text-transform: uppercase;
          font-variant-numeric: tabular-nums;
        }
        .dot { width: 7px; height: 7px; background: var(--amber); }
        .connection.live .dot { background: var(--green); box-shadow: 0 0 0 3px rgba(102,229,154,.12); }
        .connection.offline .dot { background: var(--red); box-shadow: 0 0 0 3px rgba(255,114,114,.12); }
        main { padding: 24px 28px 44px; }
        .summary { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; margin-bottom: 16px; }
        .metric {
          position: relative;
          min-height: 76px;
          padding: 14px 16px;
          border: 1px solid var(--border);
          background: var(--panel);
          box-shadow: inset 0 1px rgba(255,255,255,.02), 0 12px 30px rgba(0,0,0,.12);
        }
        .metric::before { content: ""; position: absolute; top: -1px; left: -1px; width: 12px; border-top: 1px solid var(--green); }
        .metric-label { color: var(--muted); font-size: 9px; letter-spacing: .14em; text-transform: uppercase; }
        .metric-value { margin-top: 9px; color: var(--green); font: 600 21px var(--mono); font-variant-numeric: tabular-nums; }
        .metric-value.errors { color: var(--red); }
        .toolbar {
          display: flex;
          align-items: center;
          gap: 10px;
          flex-wrap: wrap;
          padding: 10px;
          border: 1px solid var(--border);
          border-bottom: 0;
          border-radius: 2px 2px 0 0;
          background: var(--panel);
        }
        .search-wrap { position: relative; flex: 1 1 260px; }
        .search-wrap svg { position: absolute; left: 10px; top: 50%; translate: 0 -50%; color: var(--subtle); pointer-events: none; }
        #search {
          width: 100%;
          height: 34px;
          padding: 0 12px 0 34px;
          border: 1px solid var(--border);
          border-radius: 2px;
          background: #0a0d12;
          color: var(--text);
          font-family: var(--mono);
          font-size: 12px;
        }
        #search::placeholder { color: var(--subtle); }
        .filters { display: flex; gap: 4px; }
        .chip, .action {
          min-height: 34px;
          border: 1px solid var(--border);
          border-radius: 2px;
          background: transparent;
          color: var(--muted);
          cursor: pointer;
          font-family: var(--mono);
          font-size: 10px;
          letter-spacing: .07em;
          text-transform: uppercase;
          transition: background-color .15s, border-color .15s, color .15s;
        }
        .chip { padding: 0 10px; }
        .action { display: inline-flex; align-items: center; gap: 7px; padding: 0 11px; }
        .chip:hover, .action:hover { border-color: var(--border-strong); background: var(--panel-raised); color: var(--text); }
        .chip[aria-pressed="true"] { border-color: #496553; background: #1b2b20; color: var(--green); }
        .actions { display: flex; gap: 6px; margin-left: auto; }
        .log-panel {
          min-height: 430px;
          border: 1px solid var(--border);
          border-radius: 0 0 2px 2px;
          overflow: hidden;
          background: #0b0e13;
          box-shadow: 0 20px 50px rgba(0,0,0,.18);
        }
        #logs { margin: 0; padding: 8px 0; list-style: none; }
        .entry {
          display: grid;
          grid-template-columns: 190px 64px minmax(0, 1fr);
          align-items: start;
          gap: 12px;
          padding: 7px 14px;
          border-left: 2px solid transparent;
          font: 12px/1.55 var(--mono);
          content-visibility: auto;
        }
        .entry:hover { background: rgba(255,255,255,.025); }
        .entry.error { border-left-color: var(--red); background: rgba(255,114,114,.035); }
        .entry.warn { border-left-color: var(--amber); }
        .time { color: var(--subtle); white-space: nowrap; font-variant-numeric: tabular-nums; }
        .level { font-weight: 700; letter-spacing: .04em; }
        .level.info { color: var(--green); }
        .level.warn { color: var(--amber); }
        .level.error { color: var(--red); }
        .message { min-width: 0; color: #c5cec7; white-space: pre-wrap; overflow-wrap: anywhere; }
        .state {
          display: grid;
          place-items: center;
          min-height: 410px;
          padding: 36px;
          text-align: center;
          color: var(--muted);
        }
        .state strong { display: block; margin-bottom: 7px; color: var(--text); font-size: 14px; }
        .state span { font-size: 12px; }
        .hidden { display: none !important; }
        #announcement { position: fixed; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }
        @media (max-width: 720px) {
          .topbar { padding: 0 16px; }
          main { padding: 16px; }
          .summary { grid-template-columns: 1fr 1fr; }
          .metric:last-child { grid-column: 1 / -1; }
          .toolbar { align-items: stretch; }
          .filters { order: 2; overflow-x: auto; }
          .actions { order: 2; margin-left: auto; }
          .entry { grid-template-columns: 1fr auto; gap: 4px 10px; }
          .message { grid-column: 1 / -1; padding-left: 0; }
          .time { overflow: hidden; text-overflow: ellipsis; }
        }
        @media (prefers-reduced-motion: reduce) { * { scroll-behavior: auto !important; transition: none !important; } }
      </style>
    </head>
    <body>
      <div class="shell">
        <header class="topbar">
          <div class="brand">
            <div class="mark" aria-hidden="true">⌖</div>
            <div><div class="eyebrow">Autonomous Research Operations</div><h1 translate="no">Snoopy // Command</h1><div class="subtitle">Observation Node <span class="node-id">SN-01 · Localhost</span></div></div>
          </div>
          <div id="connection" class="connection" role="status"><span class="dot"></span><span id="status">Connecting…</span></div>
        </header>
        <main>
          <section class="summary" aria-label="Log summary">
            <div class="metric"><div class="metric-label">Event Throughput</div><div id="event-count" class="metric-value">—</div></div>
            <div class="metric"><div class="metric-label">System Faults</div><div id="error-count" class="metric-value errors">—</div></div>
            <div class="metric"><div class="metric-label">Last Signal</div><div id="last-activity" class="metric-value">—</div></div>
          </section>
          <section aria-label="Snoopy logs">
            <div class="toolbar">
              <label class="search-wrap" aria-label="Search logs">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="11" cy="11" r="7"></circle><path d="m20 20-4-4"></path></svg>
                <input id="search" type="search" placeholder="QUERY EVENT STREAM…" autocomplete="off" spellcheck="false">
              </label>
              <div class="filters" role="group" aria-label="Filter by level">
                <button class="chip" data-level="ALL" aria-pressed="true">All Signals</button>
                <button class="chip" data-level="INFO" aria-pressed="false">Nominal</button>
                <button class="chip" data-level="WARN" aria-pressed="false">Warnings</button>
                <button class="chip" data-level="ERROR" aria-pressed="false">Faults</button>
              </div>
              <div class="actions">
                <button id="pause" class="action" aria-pressed="false"><span aria-hidden="true">Ⅱ</span><span>Pause</span></button>
                <button id="copy" class="action"><span aria-hidden="true">⧉</span><span>Export Stream</span></button>
              </div>
            </div>
            <div class="log-panel">
              <ol id="logs" aria-label="Log entries"></ol>
              <div id="empty" class="state"><div><strong>Awaiting Signal</strong><span>The event stream is armed and monitoring.</span></div></div>
            </div>
          </section>
        </main>
      </div>
      <div id="announcement" aria-live="polite"></div>
      <script>
        const logs = document.querySelector('#logs');
        const empty = document.querySelector('#empty');
        const status = document.querySelector('#status');
        const connection = document.querySelector('#connection');
        const search = document.querySelector('#search');
        const pause = document.querySelector('#pause');
        const copy = document.querySelector('#copy');
        const announcement = document.querySelector('#announcement');
        const eventCount = document.querySelector('#event-count');
        const errorCount = document.querySelector('#error-count');
        const lastActivity = document.querySelector('#last-activity');
        let raw = '';
        let level = 'ALL';
        let paused = false;

        function parse(text) {
          const entries = [];
          text.split('\n').filter(Boolean).forEach((line) => {
            const match = line.match(/^(\S+) \[(INFO|WARN|ERROR)\] ([\s\S]*)$/);
            if (match) {
              entries.push({ raw: line, timestamp: match[1], level: match[2], message: match[3] });
            } else if (entries.length) {
              const current = entries.at(-1);
              current.raw += '\n' + line;
              current.message += '\n' + line;
            } else {
              entries.push({ raw: line, timestamp: '', level: 'INFO', message: line });
            }
          });
          return entries;
        }

        function formatTime(timestamp) {
          if (!timestamp) return '—';
          const date = new Date(timestamp);
          return Number.isNaN(date.valueOf()) ? timestamp : new Intl.DateTimeFormat(undefined, {
            month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', second: '2-digit'
          }).format(date);
        }

        function render() {
          const entries = parse(raw);
          const query = search.value.trim().toLocaleLowerCase();
          const visible = entries.filter((entry) =>
            (level === 'ALL' || entry.level === level) && (!query || entry.raw.toLocaleLowerCase().includes(query))
          ).reverse();

          eventCount.textContent = new Intl.NumberFormat().format(entries.length);
          errorCount.textContent = new Intl.NumberFormat().format(entries.filter((entry) => entry.level === 'ERROR').length);
          lastActivity.textContent = entries.length ? formatTime(entries.at(-1).timestamp).replace(/^.*?, /, '') : '—';
          logs.replaceChildren();

          const fragment = document.createDocumentFragment();
          visible.forEach((entry) => {
            const row = document.createElement('li');
            row.className = 'entry ' + entry.level.toLowerCase();
            const time = document.createElement('time');
            time.className = 'time';
            time.dateTime = entry.timestamp;
            time.textContent = formatTime(entry.timestamp);
            const badge = document.createElement('span');
            badge.className = 'level ' + entry.level.toLowerCase();
            badge.textContent = entry.level;
            const message = document.createElement('span');
            message.className = 'message';
            message.textContent = entry.message;
            row.append(time, badge, message);
            fragment.append(row);
          });
          logs.append(fragment);

          empty.classList.toggle('hidden', visible.length > 0);
          if (!visible.length) {
            empty.querySelector('strong').textContent = entries.length ? 'No Matching Signals' : 'Awaiting Signal';
            empty.querySelector('span').textContent = entries.length ? 'Adjust the query or event classification.' : 'The event stream is armed and monitoring.';
          }
        }

        document.querySelectorAll('[data-level]').forEach((button) => {
          button.addEventListener('click', () => {
            level = button.dataset.level;
            document.querySelectorAll('[data-level]').forEach((item) => item.setAttribute('aria-pressed', String(item === button)));
            render();
          });
        });
        search.addEventListener('input', render);
        pause.addEventListener('click', () => {
          paused = !paused;
          pause.setAttribute('aria-pressed', String(paused));
          pause.lastElementChild.textContent = paused ? 'Resume' : 'Pause';
          pause.firstElementChild.textContent = paused ? '▶' : 'Ⅱ';
          announcement.textContent = paused ? 'Live updates paused.' : 'Live updates resumed.';
        });
        copy.addEventListener('click', async () => {
          try {
            await navigator.clipboard.writeText(raw);
            announcement.textContent = 'Logs copied to the clipboard.';
            copy.lastElementChild.textContent = 'Copied';
            setTimeout(() => copy.lastElementChild.textContent = 'Export Stream', 1400);
          } catch (_) {
            announcement.textContent = 'Could not copy logs. Select the log text and copy it manually.';
          }
        });

        async function refresh() {
          try {
            const response = await fetch('/logs?t=' + Date.now(), { cache: 'no-store' });
            if (!response.ok) throw new Error('HTTP ' + response.status);
            const text = await response.text();
            if (!paused && text !== raw) {
              raw = text;
              render();
            }
            connection.className = 'connection live';
            status.textContent = 'Link Nominal · ' + new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' });
          } catch (_) {
            connection.className = 'connection offline';
            status.textContent = 'Link Offline';
          }
        }
        refresh();
        setInterval(refresh, 1000);
      </script>
    </body>
    </html>
    """#
}
