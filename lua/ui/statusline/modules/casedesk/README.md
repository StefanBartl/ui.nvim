# ui.statusline.modules.casedesk

Statusline segment: current case's short number + company + how many files
sit in its `Replies/` folder, plus an SLA badge when a P1/P2 clock is
urgent. Empty string whenever the focused buffer isn't inside a known case.
