---@module 'ui.statusline.modules.macro_counter'
--- Live keystroke count for the macro currently being recorded.
--- `vim.fn.reg_recording()` already shows THAT a recording is in progress
--- (most statuslines have that); this adds HOW MANY keys are in it so far --
--- a feel for how "expensive" the macro already is before playing it back
--- for the first time.
---
--- Neovim has no API to read a register's content mid-recording, so this
--- counts a different way: `RecordingEnter`/`RecordingLeave` bracket a
--- `vim.on_key()` hook that increments a counter for every key while it is
--- active. The autocmds are registered once, at first render -- this module
--- is opt-in (not wired into any shipped preset), so nothing should run
--- before a host actually asks for it by requiring this file.

local Autocmd = require("lib.nvim.bindings.autocmd")

local NS = vim.api.nvim_create_namespace("ui_statusline_macro_counter")

---@type integer
local count = 0
local registered = false

--- Register the recording-bracket autocmds once. Idempotent -- safe even if
--- a host somehow ends up requiring this module more than once.
---@return nil
local function ensure_autocmds()
  if registered then
    return
  end
  registered = true

  local group = Autocmd.group("ui_statusline_macro_counter", true)

  Autocmd.create("RecordingEnter", function()
    count = 0
    vim.on_key(function()
      count = count + 1
    end, NS)
  end, {
    group = group,
    desc = "ui.statusline: count keystrokes while a macro is recording",
  })

  Autocmd.create("RecordingLeave", function()
    -- Detaches the hook rather than leaving it running and merely ignoring
    -- its own increments -- every other key in the session would otherwise
    -- keep paying a (tiny but pointless) callback cost between recordings.
    vim.on_key(nil, NS)
  end, {
    group = group,
    desc = "ui.statusline: stop counting once the macro recording ends",
  })
end

---@return string
return function()
  ensure_autocmds()

  local reg = vim.fn.reg_recording()
  if reg == "" then
    return ""
  end

  -- Plain concatenation, not string.format: the literal "%" in "%#Group#"
  -- reads as a (invalid) format directive to Lua's own %-based formatter.
  return " %#St_lspWarning#@" .. reg .. " \xC2\xB7 " .. count .. " "
end
