-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.idle_breadcrumbs` -- `breadcrumbs` with more room
--- while the editor is idle. Built on `ui.statusline.utils.idle` (covered on
--- its own in TESTS/idle_spec.lua). The symbol chain is pinned through
--- `my.nvim`'s provider seam (`my.hl_config.breadcrumbs.ctx.providers.
--- lsp_symbols`, faked here), so the assertions are about width, not about
--- what an LSP or a Tree-sitter parser happens to answer.

local CHAIN = "Outer → Middle → Inner → handle_request()"
local PROVIDER = "my.hl_config.breadcrumbs.ctx.providers.lsp_symbols"

---@return fun(opts?: table): string
local function fresh_module()
  package.loaded["ui.statusline.utils.idle"] = nil
  package.loaded["ui.statusline.modules.idle_breadcrumbs"] = nil
  local mod = require("ui.statusline.modules.idle_breadcrumbs")
  -- First render registers the idle autocmds (see TESTS/idle_clock_spec.lua).
  mod()
  return mod
end

---@param event string
local function fire(event)
  vim.api.nvim_exec_autocmds(event, {})
end

--- Displayed text of a rendered statusline string: highlight and click
--- items stripped, `%%` unescaped.
---@param s string
---@return string
local function visible(s)
  return (s:gsub("%%#[^#]*#", ""):gsub("%%%*", ""):gsub("%%%%", "%%"))
end

describe("ui.statusline.modules.idle_breadcrumbs", function()
  local saved_columns
  local cfg = require("ui.statusline.modules.lsp.config")
  local saved_cfg

  before_each(function()
    saved_columns = vim.o.columns
    saved_cfg = cfg.get_cfg()
    vim.o.columns = 160
    -- No debounce: every render recomputes, so nothing cached by an earlier
    -- test leaks into this one.
    cfg.set("debounce_ms", 0)
    package.loaded[PROVIDER] = {
      context = function()
        return CHAIN
      end,
    }
    local deep = vim.fs.normalize(vim.fn.tempname())
      .. "/alpha/bravo/charlie/delta/echo/foxtrot/golf/hotel/india"
    vim.fn.mkdir(deep, "p")
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, deep .. "/juliett_kilo_lima.lua")
    vim.api.nvim_set_current_buf(buf)
    vim.g.statusline_winid = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    vim.o.columns = saved_columns
    cfg.update(saved_cfg)
    package.loaded[PROVIDER] = nil
    vim.g.statusline_winid = nil
  end)

  it("renders exactly what breadcrumbs renders while active", function()
    local mod = fresh_module()
    local lsp = require("ui.statusline.modules.lsp")
    local band = lsp.mode_band_group()
    local plain = lsp.hl_open(band) .. lsp.render_breadcrumbs_inherit_lspfirst(band)
    assert.equals(plain, mod())
  end)

  it("shortens less while idle: the full chain and more of the path", function()
    local mod = fresh_module()
    local active = visible(mod())

    fire("CursorHold")
    local idle_out = visible(mod())

    assert.is_true(
      vim.fn.strdisplaywidth(idle_out) > vim.fn.strdisplaywidth(active),
      ("idle (%q) must be wider than active (%q)"):format(idle_out, active)
    )
    assert.is_truthy(idle_out:find(CHAIN, 1, true), idle_out)
    assert.is_truthy(idle_out:find("juliett_kilo_lima.lua", 1, true), idle_out)
  end)

  it("shrinks back on the next keystroke", function()
    local mod = fresh_module()
    local active = mod()
    fire("CursorHold")
    assert.are_not.equals(active, mod())
    fire("CursorMoved")
    assert.equals(active, mod())
  end)

  it("never touches the shared lsp config other segments read", function()
    local before = cfg.get_cfg()
    local mod = fresh_module()
    fire("CursorHold")
    mod()
    mod({ idle_width_frac = 1 })
    assert.same(before, cfg.get_cfg())
  end)

  it("lifts the fixed path cap, not just the budget", function()
    -- Same budget both times: only `overrides` differs. Without them the
    -- configured `path_max_chars` (45) cuts the path even though the
    -- budget has room for all of it.
    local formatters = require("ui.statusline.modules.formatters")
    local rel = "alpha/bravo/charlie/delta/echo/foxtrot/golf/hotel/india/juliett_kilo_lima.lua"
    local capped = formatters.compact_breadcrumb_line(rel, "fn()", " > ", 140)
    local lifted = formatters.compact_breadcrumb_line(
      rel,
      "fn()",
      " > ",
      140,
      { path_max_chars = false, path_max_frac = 1.0 }
    )
    assert.are_not.equals(rel .. " > fn()", capped)
    assert.equals(rel .. " > fn()", lifted)
    assert.equals(45, cfg.get("path_max_chars"), "the override is per call only")
  end)

  it("never gets narrower than the active budget, whatever idle_width_frac says", function()
    local mod = fresh_module()
    local active = visible(mod())
    fire("CursorHold")
    local tiny = visible(mod({ idle_width_frac = 0.05 }))
    assert.is_true(vim.fn.strdisplaywidth(tiny) >= vim.fn.strdisplaywidth(active))
    -- An invalid value falls back to the default instead of throwing.
    assert.equals(visible(mod()), visible(mod({ idle_width_frac = "wide" })))
  end)
end)
