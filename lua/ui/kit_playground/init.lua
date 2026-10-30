---@module 'ui.kit_playground'
---@brief Interactive tour of every `ui.kit` primitive: one demo per component.
---@description
--- `:UI kit-playground` opens a `kit.shortlist` of demos (the list itself is a shortlist with
--- `number_keys`, so `1`..`9` start the first nine); the preview pane says what the highlighted
--- demo shows and which keys to try. `:UI kit-playground <id>` starts one demo directly.
---
--- Key responsibilities:
--- - one entry per kit primitive (`entries()`), each naming the kit modules it covers
--- - `run(id)` opens a demo and returns a function that closes everything it opened
--- - answers of a dialog are shown in a toast, so a demo shows what the caller would get
---
--- Demo code only: nothing here is used by the rest of ui.nvim, and nothing changes a global
--- setting (a preset is shown per call through `theme = name`; `:UI kit-preset` switches it).
--- `:KitPreview` (the live theme editor, `ui.kit.preview`) is one of the demos, not replaced by
--- this. The kit code lives in lib.nvim (`lib.nvim.ui.kit`); this module only calls it.

local api = vim.api

local M = {}

---What a demo is handed: `track` registers a cleanup, so the closer `run` returns undoes
---exactly what the demo opened (in reverse order).
---@class Ui.KitPlayground.Ctx
---@field track fun(cleanup: fun())

---@class Ui.KitPlayground.Entry
---@field id string               # the word for `:UI kit-playground <id>`
---@field label string            # the row in the playground list
---@field covers string[]         # the kit modules (file names under ui/kit/) it shows
---@field desc string[]           # preview pane text: what it shows, which keys to try
---@field open fun(ctx: Ui.KitPlayground.Ctx)

---The kit modules no demo shows, with the reason; `TESTS/kit_playground_spec.lua` checks that
---every other `ui.kit` module of ui.nvim (the re-exports under `lua/ui/kit/`) is covered by an
---entry. Names may be modules of lib.nvim only (`hook` has no ui.nvim re-export).
---@type table<string, string>
M.NOT_DEMOED = {
  hook = "test hook that answers dialogs without a window; nothing to look at",
  config = "the static default preset name, read by theme",
}

---@return table
local function kit()
  return require("ui.kit")
end

---Show what a dialog answered, the way a caller would receive it.
---@param what string
---@param value any
---@return nil
local function report(what, value)
  kit().toast({ title = "kit playground", message = ("%s -> %s"):format(what, vim.inspect(value)) })
end

---Close a surface-like handle (`:close()` method) if it is still open.
---@param handle table|nil
---@return fun()
local function closer_of(handle)
  return function()
    if not handle then
      return
    end
    if type(handle.is_valid) == "function" and not handle:is_valid() then
      return
    end
    pcall(handle.close, handle)
  end
end

---@return integer[]
local function float_wins()
  local out = {}
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(win).relative ~= "" then
      out[#out + 1] = win
    end
  end
  return out
end

---A cleanup for a demo whose windows are not handed back (`kit.async`, `kit.progress`): close
---the floats that were not there when the demo started.
---@return fun()
local function close_new_floats()
  local before = {}
  for _, win in ipairs(float_wins()) do
    before[win] = true
  end
  return function()
    for _, win in ipairs(float_wins()) do
      if not before[win] then
        pcall(api.nvim_win_close, win, true)
      end
    end
  end
end

---@param n integer
---@return string[]
local function sample_files(n)
  local out = {}
  local names = {
    "lua/ui/init.lua",
    "lua/ui/statusline/render.lua",
    "lua/ui/tabline/styles.lua",
    "doc/ui.txt",
    "README.md",
    "docs/BINDINGS.md",
    "TESTS/kit_playground_spec.lua",
    "CHANGELOG.md",
    "lua/ui/zen/init.lua",
    "lua/ui/kit/README.md",
    "scripts/test.sh",
  }
  for i = 1, math.min(n, #names) do
    out[i] = names[i]
  end
  return out
end

---Fake file content for a preview pane.
---@param name string
---@return string[]
local function fake_content(name)
  return {
    "-- " .. name,
    "",
    ("local M = {} -- %d bytes of demo text"):format(#name * 37),
    "",
    "function M.setup(opts)",
    "  return opts",
    "end",
    "",
    "return M",
  }
end

-- ---------------------------------------------------------------- the demos

---@type Ui.KitPlayground.Entry[]
local ENTRIES = {
  {
    id = "presets",
    label = "Theme presets",
    covers = { "theme" },
    desc = {
      "kit.theme: every popup resolves a preset (border + colours).",
      "Pick one: a note opens with `theme = <name>` for that one call.",
      "The global default stays as it is (:UI kit-preset switches it).",
    },
    open = function(ctx)
      local theme = kit().theme
      kit().select({
        title = "Kit presets (active: " .. theme.default() .. ")",
        items = theme.presets(),
        relative = "editor",
        on_select = function(name)
          local surf = kit().note({
            title = name,
            message = { "This note uses the preset", ("  theme = %q"):format(name), "", "q closes" },
            theme = name,
          })
          ctx.track(closer_of(surf))
        end,
      })
      ctx.track(function()
        kit().chooser.close()
      end)
    end,
  },
  {
    id = "status-tokens",
    label = "Status tokens KitOk/KitWarn/KitInfo/KitDim",
    covers = { "theme", "viewer" },
    desc = {
      "kit.theme status tokens: ok, warn, info, dim.",
      "A list whose rows have a state links KitOk/KitWarn/KitInfo/KitDim",
      "instead of groups of its own; a preset may restyle them.",
    },
    open = function(ctx)
      local ns = api.nvim_create_namespace("ui_kit_playground_status")
      local rows = {
        { "  ok    KitOk    tests passed", "KitOk" },
        { "  warn  KitWarn  2 specs skipped", "KitWarn" },
        { "  info  KitInfo  cache rebuilt", "KitInfo" },
        { "  dim   KitDim   last run 3 min ago", "KitDim" },
      }
      local lines = {}
      for i, row in ipairs(rows) do
        lines[i] = row[1]
      end
      kit().theme.materialize(kit().theme.resolve())
      local surf = kit().viewer({
        title = "Status tokens",
        lines = lines,
        on_lines = function(bufnr)
          api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
          for i, row in ipairs(rows) do
            api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, { end_col = #row[1], hl_group = row[2] })
          end
        end,
      })
      ctx.track(closer_of(surf))
    end,
  },
  {
    id = "surface",
    label = "Surface (the bare float)",
    covers = { "surface" },
    desc = {
      "kit.surface.open: one themed float plus a handle",
      "(set_lines, set_title, focus, on_close, close).",
      "Every other component is built on it. q closes.",
    },
    open = function(ctx)
      local surf = kit().surface.open({
        lines = { "A bare kit.surface.", "", "s:set_lines / s:set_title / s:close", "q closes" },
        title = "Surface",
        width = 44,
        height = 4,
        enter = true,
        nice_quit = true,
      })
      ctx.track(closer_of(surf))
    end,
  },
  {
    id = "note",
    label = "Note (kit.popup front door)",
    covers = { "note", "init" },
    desc = {
      "kit.popup({ type = 'note', ... }): the dispatching front door,",
      "here with its default type, a centred title + message.",
      "q closes.",
    },
    open = function(ctx)
      local surf = kit().popup({
        type = "note",
        title = "Saved",
        message = { "Wrote 3 files", "", "kit.popup dispatches on opts.type" },
      })
      ctx.track(closer_of(surf))
    end,
  },
  {
    id = "viewer",
    label = "Viewer with keys and a cheatsheet",
    covers = { "viewer", "viewer_keys" },
    desc = {
      "kit.viewer: read-only panel, closes on q/<Esc> or focus loss.",
      "keys = { ... } adds the winbar legend and the ? cheatsheet.",
      "Try r (refresh) and ?.",
    },
    open = function(ctx)
      local refreshed = 0
      local function body()
        return {
          "name   kit_playground",
          "kind   viewer",
          ("hits   %d refresh(es)"):format(refreshed),
        }
      end
      local surf = kit().viewer({
        title = " Report ",
        lines = body(),
        table_view = true,
        desc_prefix = "kit playground",
        keys = {
          {
            lhs = "r",
            desc = "Refresh the report",
            legend = "Refresh",
            run = function(view)
              refreshed = refreshed + 1
              view.set_lines(body())
              view.set_title((" Report (%d) "):format(refreshed))
            end,
          },
        },
      })
      ctx.track(closer_of(surf))
    end,
  },
  {
    id = "keys",
    label = "Keys cheatsheet (kit.keys)",
    covers = { "viewer_keys" },
    desc = {
      "kit.keys.cheatsheet: the ? sheet of a view that binds its own keys",
      "(two plain splits, no kit.viewer). Built from one rows table.",
    },
    open = function(ctx)
      local surf = kit().keys.cheatsheet("Kit playground", {
        { lhs = "<CR>", desc = "Start the demo under the cursor" },
        { lhs = "1-9", desc = "Start one of the first nine demos" },
        { lhs = "<Tab>", desc = "Hop into the preview" },
        { lhs = "q", desc = "Close" },
      }, { help_lhs = false })
      ctx.track(closer_of(surf))
    end,
  },
  {
    id = "toast",
    label = "Toasts (stacking corner messages)",
    covers = { "toast" },
    desc = {
      "kit.toast: ephemeral corner message that never takes focus.",
      "Three are opened; they stack and dismiss themselves.",
    },
    open = function(ctx)
      for i = 1, 3 do
        local surf =
          kit().toast({ title = "Toast " .. i, message = ("background job %d done"):format(i) })
        ctx.track(closer_of(surf))
      end
    end,
  },
  {
    id = "chip",
    label = "Chips (persistent corner status, three shapes)",
    covers = { "chip", "presets" },
    desc = {
      "kit.chip: mounted under an id, updated in place, stays until unmounted.",
      "Shown in the three shapes (kit.presets): classic, chip, rounded_chip;",
      "one pulses. They unmount themselves after 6 seconds.",
    },
    open = function(ctx)
      local chip = kit().chip
      local ids = {}
      local placement = {
        { "classic", "top-left", "DiagnosticInfo" },
        { "chip", "top-right", "DiagnosticWarn" },
        { "rounded_chip", "bottom-right", "DiagnosticOk" },
      }
      for _, p in ipairs(placement) do
        local id = "ui_kit_playground_" .. p[1]
        ids[#ids + 1] = id
        chip.mount({ id = id, text = "shape = " .. p[1], shape = p[1], anchor = p[2], color = p[3] })
      end
      chip.pulse(ids[3], { color = "DiagnosticError", duration_ms = 600 })
      local done = false
      local function unmount()
        if done then
          return
        end
        done = true
        for _, id in ipairs(ids) do
          pcall(chip.unmount, id)
        end
      end
      vim.defer_fn(unmount, 6000)
      ctx.track(unmount)
    end,
  },
  {
    id = "message-log",
    label = "Message log (paginated, collapsible)",
    covers = { "message_log" },
    desc = {
      "kit.message_log: time-ordered entries; <CR> folds the one under the",
      "cursor, <C-h>/<C-l> all; <C-j> (or +) loads older ones; ? cheatsheet.",
    },
    open = function(ctx)
      local now = vim.uv.hrtime() / 1e6
      local function entry(age_s, level, content)
        return { time_ms = now - age_s * 1000, level = level, content = content }
      end
      local older_left = true
      local handle = kit().message_log({
        title = "Recent messages",
        entries = {
          entry(40, vim.log.levels.INFO, "build started"),
          entry(30, vim.log.levels.WARN, "2 warnings\nunused variable `x`\nshadowed `opts`"),
          entry(5, vim.log.levels.ERROR, "spec failed: kit_playground_spec.lua"),
          entry(1, vim.log.levels.INFO, "rerun queued"),
        },
        load_more = function(direction)
          if direction ~= "older" or not older_left then
            return {}
          end
          older_left = false
          return { entry(120, vim.log.levels.INFO, "an older entry, loaded on demand") }
        end,
      })
      ctx.track(closer_of(handle))
    end,
  },
  {
    id = "input",
    label = "Input (single line)",
    covers = { "input" },
    desc = { "kit.input: one-line prompt; <CR> submits, <Esc> cancels." },
    open = function(ctx)
      local surf = kit().input({
        prompt = "New name",
        default = "playground",
        on_submit = function(text)
          report("kit.input", text)
        end,
        on_cancel = function()
          report("kit.input", "cancelled")
        end,
      })
      ctx.track(closer_of(surf))
    end,
  },
  {
    id = "input-secret",
    label = "Input, secret (masked)",
    covers = { "input" },
    desc = {
      "kit.input({ secret = true }): masked as you type,",
      "a vim.fn.inputsecret replacement.",
    },
    open = function(ctx)
      local surf = kit().input({
        prompt = "Password (demo, not stored)",
        secret = true,
        on_submit = function(text)
          report("kit.input secret, length", #text)
        end,
      })
      ctx.track(closer_of(surf))
    end,
  },
  {
    id = "input-path",
    label = "Input with file completion",
    covers = { "input" },
    desc = {
      "kit.input({ completion = 'file' }): <Tab> opens the native",
      "completion popup over file names.",
    },
    open = function(ctx)
      local surf = kit().input({
        prompt = "Path",
        completion = "file",
        on_submit = function(text)
          report("kit.input path", text)
        end,
      })
      ctx.track(closer_of(surf))
    end,
  },
  {
    id = "live-input",
    label = "Live input (debounced on_change)",
    covers = { "live_input" },
    desc = {
      "kit.live_input: on_change(query) fires as you type (debounced).",
      "The title counts the characters.",
    },
    open = function(ctx)
      local surf
      surf = kit().live_input({
        prompt = "Filter",
        on_change = function(query)
          if surf and surf:is_valid() then
            surf:set_title(("Filter (%d chars)"):format(#query))
          end
        end,
        on_submit = function(text)
          report("kit.live_input", text)
        end,
      })
      ctx.track(closer_of(surf))
    end,
  },
  {
    id = "form",
    label = "Form (chained prompts, back navigation)",
    covers = { "form", "buttons" },
    desc = {
      "kit.form({ back = true }): one input per field, one keyed result.",
      "<BS> on an empty field / <S-Tab> goes back; the button row is",
      "kit.buttons. <Esc> on the required first field aborts.",
    },
    open = function(ctx)
      local surf = kit().form({
        back = true,
        fields = {
          { name = "image", label = "Image", required = true, default = "alpine" },
          { name = "name", label = "Name" },
          { name = "ports", label = "Ports", default = "8080" },
        },
        on_submit = function(values)
          report("kit.form", values)
        end,
        on_cancel = function()
          report("kit.form", "cancelled")
        end,
      })
      ctx.track(closer_of(surf))
    end,
  },
  {
    id = "sheet",
    label = "Sheet (every field at once)",
    covers = { "sheet" },
    desc = {
      "kit.sheet: all fields in one float, validation under the field,",
      "a select field (h/l cycles), Submit/Cancel buttons. <Tab> moves.",
    },
    open = function(ctx)
      local sheet = kit().sheet({
        title = "New case",
        fields = {
          {
            name = "number",
            label = "Case number",
            required = true,
            live = true,
            validate = function(v)
              if v:match("^%d+$") then
                return true
              end
              return false, "digits only"
            end,
          },
          { name = "area", label = "Area", kind = "select", choices = { "EMEA", "APAC", "AMER" } },
          { name = "title", label = "Title" },
        },
        submit_label = "Create",
        on_submit = function(values)
          report("kit.sheet", values)
        end,
        on_cancel = function()
          report("kit.sheet", "cancelled")
        end,
      })
      ctx.track(function()
        if sheet and sheet:is_valid() then
          pcall(sheet.cancel, sheet)
        end
      end)
    end,
  },
  {
    id = "select",
    label = "Select (multi, <Tab> marks)",
    covers = { "select" },
    desc = { "kit.select({ multi = true }): j/k move, <Tab> marks, <CR> picks." },
    open = function(ctx)
      kit().select({
        title = "Pick fruit",
        items = { "apple", "banana", "cherry", "date" },
        multi = true,
        relative = "editor",
        on_select = function(picked)
          report("kit.select", picked)
        end,
      })
      ctx.track(function()
        kit().chooser.close()
      end)
    end,
  },
  {
    id = "chooser",
    label = "Chooser (low level, extra key)",
    covers = { "chooser" },
    desc = {
      "kit.chooser: the list under kit.select, for a caller with its own keys.",
      "p reports the highlighted item without closing (current_item()).",
    },
    open = function(ctx)
      local chooser = kit().chooser
      local surf = chooser.open({
        title = "Chooser (p peeks)",
        items = { "first", "second", "third" },
        relative = "editor",
        on_select = function(item)
          report("kit.chooser", item)
        end,
      })
      if surf then
        vim.keymap.set("n", "p", function()
          report("chooser.current_item()", chooser.current_item())
        end, { buffer = surf.bufnr, nowait = true, desc = "kit playground: peek" })
      end
      ctx.track(function()
        chooser.close()
      end)
    end,
  },
  {
    id = "prompt",
    label = "Prompt (confirm as a list)",
    covers = { "prompt" },
    desc = {
      "kit.prompt({ answer_type = 'confirm' }): yes/no as a list -> boolean.",
      "answer_type = 'text' is a kit.input.",
    },
    open = function(ctx)
      kit().prompt({
        question = "Keep the playground open?",
        answer_type = "confirm",
        on_answer = function(yes)
          report("kit.prompt", yes)
        end,
      })
      ctx.track(function()
        kit().chooser.close()
      end)
    end,
  },
  {
    id = "confirm",
    label = "Confirm (buttons, hotkeys)",
    covers = { "confirm", "buttons" },
    desc = {
      "kit.confirm: h/l move, <CR> confirms, s/d/c are the & hotkeys,",
      "kind = 'warn' colours the frame, legend = true adds a key legend.",
    },
    open = function(ctx)
      kit().confirm({
        question = "Unsaved changes in 2 buffers.",
        choices = "&Save\n&Discard\n&Cancel",
        kind = "warn",
        legend = true,
        on_answer = function(choice)
          report("kit.confirm", choice)
        end,
      })
      ctx.track(function()
        require("ui.kit.confirm").close()
      end)
    end,
  },
  {
    id = "ask",
    label = "Ask (waits for a free moment)",
    covers = { "confirm", "modal" },
    desc = {
      "kit.ask: a yes/no that waits until no modal kit dialog (kit.modal)",
      "is open, and always answers (false when it cannot).",
    },
    open = function(ctx)
      local dropped = false
      kit().ask({
        question = "File the answer?",
        abandoned = function()
          return dropped
        end,
        on_answer = function(yes)
          report("kit.ask", yes)
        end,
      })
      ctx.track(function()
        dropped = true
        require("ui.kit.confirm").close()
      end)
    end,
  },
  {
    id = "async",
    label = "Async (linear code over dialogs)",
    covers = { "async" },
    desc = {
      "kit.async.run: input, then confirm, written top to bottom;",
      "the editor keeps running while each dialog waits.",
    },
    open = function(ctx)
      ctx.track(close_new_floats())
      kit().async.run(function()
        local name = kit().async.input({ prompt = "Name" })
        if not name then
          report("kit.async", "cancelled at the input")
          return
        end
        local yes = kit().async.confirm({ question = ("Create %s?"):format(name) })
        report("kit.async", { name = name, create = yes })
      end)
    end,
  },
  {
    id = "menu",
    label = "Menu (columns, groups, drill-down)",
    covers = { "menu" },
    desc = {
      "kit.menu: action list with icon/label/hint columns, separators and a",
      "nested level (drill-down, <BS> or Back returns). Picks flash first.",
    },
    open = function(ctx)
      kit().menu({
        items = {
          {
            name = "Format buffer",
            rtxt = "<leader>f",
            cmd = function()
              report("kit.menu", "Format buffer")
            end,
          },
          {
            name = "Rename",
            rtxt = "<leader>r",
            cmd = function()
              report("kit.menu", "Rename")
            end,
          },
          { name = "separator" },
          {
            name = "Git",
            items = {
              {
                name = "Stage hunk",
                cmd = function()
                  report("kit.menu", "Git > Stage hunk")
                end,
              },
              {
                name = "Blame line",
                cmd = function()
                  report("kit.menu", "Git > Blame line")
                end,
              },
            },
          },
        },
      })
      ctx.track(function()
        require("ui.kit.menu").close()
      end)
    end,
  },
  {
    id = "picker",
    label = "Picker (prompt, marks, preview)",
    covers = { "picker", "layout" },
    desc = {
      "kit.picker in item mode: typing filters, <C-n>/<C-p> move,",
      "<Tab> marks, the preview follows; <CR> submits, <Esc> closes.",
    },
    open = function(ctx)
      local items = {}
      for i, name in ipairs(sample_files(11)) do
        items[i] = { text = name }
      end
      local handle = kit().picker({
        items = items,
        title = "Files",
        format = function(item)
          return { { item.text, "Normal" } }
        end,
        preview = function(item, surface)
          surface:set_lines(fake_content(item.text))
        end,
        on_submit = function(_, _, item)
          report("kit.picker", item and item.text)
        end,
      })
      ctx.track(function()
        if handle and not (handle.is_closed and handle.is_closed()) then
          pcall(handle.close)
        end
      end)
    end,
  },
  {
    id = "shortlist",
    label = "Shortlist (number keys, preview)",
    covers = { "shortlist" },
    desc = {
      "kit.shortlist({ number_keys = true }): no prompt, preview above the",
      "list; 1-9 open an entry, <Tab> hops into the preview, <C-f> scrolls.",
      "(This playground list is a shortlist, too.)",
    },
    open = function(ctx)
      local handle = kit().shortlist({
        items = sample_files(5),
        number_keys = true,
        format_item = function(item)
          return item
        end,
        render = function(item, surface)
          surface:set_lines(fake_content(item))
        end,
        preview_bo = { modifiable = false },
        on_submit = function(item, idx)
          report("kit.shortlist", { item = item, idx = idx })
        end,
      })
      ctx.track(closer_of(handle))
    end,
  },
  {
    id = "compare",
    label = "Compare (pick two, side by side)",
    covers = { "compare" },
    desc = {
      "kit.compare: <CR> (or <M-c>) marks the first pick, <CR> on a second",
      "shows both side by side; q/<Esc> closes the whole thing.",
    },
    open = function(ctx)
      local handle = kit().compare({
        items = sample_files(6),
        render = function(item, surface)
          surface:set_lines(fake_content(item))
        end,
        on_close = function(a, b)
          report("kit.compare", { a = a, b = b })
        end,
      })
      ctx.track(closer_of(handle))
    end,
  },
  {
    id = "layout",
    label = "Layout template (three aligned floats)",
    covers = { "layout" },
    desc = {
      "kit.layout.template('picker'): prompt, results and preview slots as",
      "three aligned floats, filled by hand. q or <Esc> closes the group.",
    },
    open = function(ctx)
      local group = kit().layout.template("picker", {})
      if not group then
        return
      end
      group.slots.prompt:set_lines({ "> (a bare template: nothing is wired)" })
      group.slots.results:set_lines(sample_files(6))
      group.slots.preview:set_lines(fake_content("lua/ui/init.lua"))
      for _, slot in pairs(group.slots) do
        for _, lhs in ipairs({ "q", "<Esc>" }) do
          vim.keymap.set(
            "n",
            lhs,
            group.close,
            { buffer = slot.bufnr, nowait = true, desc = "kit playground: close" }
          )
        end
      end
      group.slots.results:focus()
      ctx.track(group.close)
    end,
  },
  {
    id = "history",
    label = "History (back/forward trail)",
    covers = { "history" },
    desc = {
      "kit.history: the data behind a Back/Forward pair, no UI of its own.",
      "Here in a viewer: n moves on, b goes back, f forward,",
      "c clears the `fn` field with history.CLEAR.",
    },
    open = function(ctx)
      local history = kit().history
      local st = { id = "root", fn = nil }
      local h = history.new({ state = st, keys = { "id", "fn" } })
      local step = 0
      local function lines()
        local out = { ("now: id=%s fn=%s"):format(st.id, tostring(st.fn)), "" }
        for i, e in ipairs(h:entries()) do
          local mark = i == h:index() and "> " or "  "
          out[#out + 1] = ("%s%d  id=%s fn=%s"):format(mark, i, e.id, tostring(e.fn))
        end
        return out
      end
      local function key(lhs, desc, fn)
        return {
          lhs = lhs,
          desc = desc,
          legend = desc,
          run = function(view)
            fn()
            view.set_lines(lines())
          end,
        }
      end
      local surf = kit().viewer({
        title = " kit.history ",
        lines = lines(),
        width = 50,
        height = 14,
        keys = {
          key("n", "Next", function()
            step = step + 1
            h:go(st, { id = "node" .. step, fn = "fn" .. step })
          end),
          key("b", "Back", function()
            h:back(st)
          end),
          key("f", "Forward", function()
            h:forward(st)
          end),
          key("c", "Clear fn", function()
            h:go(st, { fn = history.CLEAR })
          end),
        },
      })
      ctx.track(closer_of(surf))
    end,
  },
  {
    id = "progress",
    label = "Progress (kit.progress, float style)",
    covers = { "init" },
    desc = {
      "kit.progress: a passthrough to lib.nvim.progress (update/finish/cancel).",
      "Counts to 10 in a float, then finishes.",
    },
    open = function(ctx)
      ctx.track(close_new_floats())
      local handle = kit().progress({ title = "[kit playground]", style = "float", delay_ms = 0 })
      local n = 0
      local timer = vim.uv.new_timer()
      local function stop()
        if timer then
          timer:stop()
          pcall(timer.close, timer)
          timer = nil
        end
      end
      handle:update({ text = "counting", current = 0, total = 10 })
      if timer then
        timer:start(
          300,
          300,
          vim.schedule_wrap(function()
            if not timer then
              return
            end
            n = n + 1
            if n >= 10 then
              stop()
              handle:finish("counted to 10")
            else
              handle:update({ text = "counting", current = n, total = 10 })
            end
          end)
        )
      end
      ctx.track(function()
        if timer then
          stop()
          handle:cancel("closed")
        end
      end)
    end,
  },
  {
    id = "preview",
    label = "Live theme editor (:KitPreview)",
    covers = { "preview" },
    desc = {
      "kit.preview: a new tab with an editable theme on the left and a",
      "gallery of every widget on the right; <Tab> cycles presets, q closes.",
    },
    open = function(ctx)
      kit().preview()
      local tab = api.nvim_get_current_tabpage()
      ctx.track(function()
        if api.nvim_tabpage_is_valid(tab) and #api.nvim_list_tabpages() > 1 then
          pcall(vim.cmd.tabclose, api.nvim_tabpage_get_number(tab))
        end
      end)
    end,
  },
}

-- ---------------------------------------------------------------- public API

---Every demo, in the order the playground lists them.
---@return Ui.KitPlayground.Entry[]
function M.entries()
  return ENTRIES
end

---The ids of every demo (completion of `:UI kit-playground`).
---@return string[]
function M.ids()
  local out = {}
  for i, entry in ipairs(ENTRIES) do
    out[i] = entry.id
  end
  return out
end

---@param id string
---@return Ui.KitPlayground.Entry|nil
function M.get(id)
  for _, entry in ipairs(ENTRIES) do
    if entry.id == id then
      return entry
    end
  end
  return nil
end

---Open one demo.
---@param id string
---@return fun()|nil close  # closes everything the demo opened; nil when `id` is unknown
---@return string|nil err
function M.run(id)
  local entry = M.get(id)
  if not entry then
    return nil,
      ("unknown kit playground demo %q (one of: %s)"):format(
        tostring(id),
        table.concat(M.ids(), ", ")
      )
  end
  ---@type fun()[]
  local cleanups = {}
  entry.open({
    track = function(cleanup)
      cleanups[#cleanups + 1] = cleanup
    end,
  })
  return function()
    for i = #cleanups, 1, -1 do
      pcall(cleanups[i])
    end
    cleanups = {}
  end
end

---Open the playground: a shortlist of every demo; `<CR>` (or `1`..`9`) starts one.
---@return table|nil handle  # the `kit.shortlist` handle
function M.open()
  return kit().shortlist({
    items = ENTRIES,
    number_keys = true,
    format_item = function(entry, width)
      local text = ("%-14s %s"):format(entry.id, entry.label)
      return vim.fn.strcharpart(text, 0, width)
    end,
    render = function(entry, surface)
      local lines = { entry.label, "" }
      vim.list_extend(lines, entry.desc)
      lines[#lines + 1] = ""
      lines[#lines + 1] = "covers: ui.kit." .. table.concat(entry.covers, ", ui.kit.")
      lines[#lines + 1] = "direct: :UI kit-playground " .. entry.id
      surface:set_lines(lines)
    end,
    preview_bo = { modifiable = false },
    on_submit = function(entry)
      local _, err = M.run(entry.id)
      if err then
        vim.notify(err, vim.log.levels.ERROR)
      end
    end,
  })
end

return M
