---@module 'ui.statusline.modules.neotest_module'
--- Statusline segment: neotest's own running/passed/failed counts, colored
--- per status, empty when nothing has run yet.

--- CDX: unused -- revival target. Unreferenced by all statusline variants
--- (its own README says so). Before wiring it in: `neotest.run.get_status()`
--- (used below) is not a neotest API -- the run consumer exposes
--- run/run_last/stop/attach/adapters/get_last_run only, so it would nil-call.
--- See docs/ROADMAP/CDX/config-cdx-triage.md §2.

return function()
  local ok, neotest = pcall(require, "neotest")
  if not ok then
    return ""
  end

  local status = neotest.run.get_status()

  -- Only render when tests are actually running or results exist
  if not status or (status.passed == 0 and status.failed == 0 and status.running == 0) then
    return ""
  end

  local result = " "

  -- Running tests (blue)
  if status.running > 0 then
    result = result .. "%#St_LspProgress#󱎫 " .. status.running .. " "
  end
  -- Passed tests (green)
  if status.passed > 0 then
    result = result .. "%#St_LspHints#󰄬 " .. status.passed .. " "
  end
  -- Failed tests (red)
  if status.failed > 0 then
    result = result .. "%#St_LspError#󰅖 " .. status.failed .. " "
  end

  return result
end
