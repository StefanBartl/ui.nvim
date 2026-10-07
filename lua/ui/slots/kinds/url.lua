---@module 'ui.slots.kinds.url'
--- Kind `url`: open an address with the system's opener (`vim.ui.open`).
--- `{ kind = "url", url = "https://neovim.io/doc/" }`.
---
--- Only `http`, `https`, `file` and `mailto` are opened. The check runs on the
--- address after the placeholders were put in, so a placeholder at the start
--- (`{clip}`) cannot smuggle in another scheme; substituted values are
--- percent-encoded, and an address with a control character is refused.

local resolve = require("ui.slots.resolve")
local util = require("ui.slots.util")

local M = {}

local SCHEMES = { http = true, https = true, file = true, mailto = true }

--- Why `url` may not be opened, or nil.
---@param url string
---@param trusted boolean|nil  # the slot comes from setup()
---@return string|nil
local function refuse(url, trusted)
  if url:find("[%c]") then
    return "the address contains a control character"
  end
  local scheme = url:match("^(%a[%w+.%-]*):")
  if not scheme then
    return "the address has no scheme (http, https, file or mailto)"
  end
  if not SCHEMES[scheme:lower()] then
    return ("the scheme '%s' is not opened (http, https, file, mailto)"):format(scheme)
  end
  -- A `file:` address is handed to the system's opener, which runs a program
  -- (a script, an executable) as readily as it shows a document -- behind a
  -- label of the slot's choosing. Only a slot the user wrote in setup() may.
  if scheme:lower() == "file" and not trusted then
    return "a file: address can only be set in setup() (use a file slot to open a file)"
  end
  return nil
end

--- A `file:` address does not come from a data file, the editor or the API.
---@param slot table
---@return string|nil
function M.trusted_only(slot)
  if type(slot.url) == "string" and slot.url:match("^%s*[Ff][Ii][Ll][Ee]:") then
    return "a file: address can only be set in setup() (use a file slot to open a file)"
  end
  return nil
end

--- How the address is handed to the system. On Windows `vim.ui.open` would run
--- `cmd.exe /c start "" <url>`, where `&`, `|`, `^` and `%` are cmd syntax: an
--- address with a query string would be cut at the first `&`, and one that comes
--- from a placeholder could run a command. `rundll32 url.dll,FileProtocolHandler`
--- is started without a shell and takes the address as one argument.
---@param is_windows boolean|nil  # default: the platform we run on
---@return { cmd: string[] }|nil
function M.opener(is_windows)
  if is_windows == nil then
    is_windows = vim.fn.has("win32") == 1
  end
  if is_windows then
    return { cmd = { "rundll32", "url.dll,FileProtocolHandler" } }
  end
  return nil
end

--- Placeholders whose value is a path: `/` and `:` stay readable in it.
local PATH_LIKE = { file = true, dir = true, root = true, cwd = true }

--- Percent-encode everything but the unreserved characters (`vim.uri_encode`
--- leaves `&`, `=` and `#` alone, which would let a value add query parameters).
---@param value string
---@param keep string  # extra characters to leave as they are
---@return string
local function encode(value, keep)
  return (
    value:gsub("[^%w%-._~" .. keep .. "]", function(c)
      return ("%%%02X"):format(c:byte())
    end)
  )
end

--- The address of a slot with its placeholders put in. A value is encoded,
--- except when the placeholder is the whole start of the address (`{clip}`,
--- `{clip}/path`): then it is the address itself, and the scheme check on the
--- result is what keeps it honest.
---@param slot table
---@param rctx Ui.Slots.Ctx|nil
---@return string url
---@return string[] unknown
local function address(slot, rctx)
  local leading = slot.url:find("^{%w+}") ~= nil
  local first = true
  return resolve.resolve(slot.url, rctx, {
    escape = function(value, name)
      if first then
        first = false
        if leading then
          return value
        end
      end
      return encode(value, PATH_LIKE[name] and "/:" or "")
    end,
  })
end

---@param slot table
---@return string|nil
function M.validate(slot)
  if type(slot.url) ~= "string" or slot.url == "" then
    return "a url slot needs an address"
  end
  -- Without placeholders the address is known now; with one at the start it is
  -- only known when the slot runs (checked again in apply).
  if not slot.url:find("{", 1, true) then
    return refuse(slot.url, slot.fixed == true)
  end
  return nil
end

--- The address this slot opens, placeholders put in.
---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return string
function M.text(slot, ctx)
  local url, unknown = address(slot, ctx.resolve)
  util.warn_unknown(unknown, "url slot")
  return url
end

---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return boolean ok
---@return string|nil err
function M.apply(slot, ctx)
  local url, unknown = address(slot, ctx.resolve)
  util.warn_unknown(unknown, "url slot")
  local why = refuse(url, slot.fixed == true)
  if why then
    return false, why
  end
  local opener = M.opener()
  if opener then
    -- FileProtocolHandler reads the address through an ANSI entry point: the
    -- bytes of a non-ASCII character are sent as %XX, which browsers read back.
    url = url:gsub("[\128-\255]", function(c)
      return ("%%%02X"):format(c:byte())
    end)
  end
  local _, err = vim.ui.open(url, opener)
  if err then
    return false, tostring(err)
  end
  return true
end

---@param slot table
---@return { label: string, icon: string, hl: string, missing: boolean }
function M.render(slot)
  local host = (slot.url or ""):match("^%a[%w+.%-]*://([^/%?#]+)")
  return {
    label = host or slot.url or "",
    icon = "󰖟",
    hl = "KitAccent",
    missing = false,
  }
end

--- The address and its host, which is all that is known without asking the
--- page.
---@param url string
---@return string[]
local function offline(url)
  local host = url:match("^%a[%w+.%-]*://([^/%?#]+)")
  return { url, "", host and ("host: " .. host) or "" }
end

--- What the page says, asked through hover.nvim: the preview shows the address
--- and "loading ..." first, and the answer replaces it when it arrives (the
--- pane drops an answer that is no longer wanted).
---
--- **Fetching is a request from this machine to that host, so it is opt-in:**
--- `preview.fetch` is off by default, and then (as without hover.nvim, and for
--- `file:` and `mailto:`) the preview is the address and its host. With
--- `preview.fetch = true` the pane fetches the page of the slot under the
--- cursor whenever it is shown -- also while the cursor follows (after `K`, or
--- in `auto` mode) -- so turning it on is the consent for that. The bar never
--- shows a preview.
---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }|nil
---@return Ui.Slots.Preview
function M.preview(slot, ctx)
  local url = M.text(slot, ctx or {})
  if refuse(url, slot.fixed == true) or not url:match("^[Hh][Tt][Tt][Pp][Ss]?://") then
    return { lines = offline(url) }
  end
  -- An address built from placeholders ({clip}, {file}, {word}, ...) puts the
  -- user's own data into a request; that is never done by a cursor passing over
  -- the row. Only an address that is written out is fetched.
  if resolve.has_placeholder(slot.url) then
    return { lines = offline(url) }
  end
  local ok, hover = pcall(require, "hover")
  local cfg = require("ui.slots.config").get().preview
  if not (ok and type(hover) == "table" and type(hover.preview_target) == "function") then
    return { lines = offline(url) }
  end
  local lines = offline(url)
  if not cfg.fetch then
    return { lines = lines }
  end
  return {
    lines = { url, "", "loading ..." },
    later = function(deliver)
      local started, handle = pcall(hover.preview_target, url, function(content)
        local out = type(content) == "table" and content.lines
        if type(out) ~= "table" or #out == 0 then
          deliver({ lines = lines })
          return
        end
        deliver({ lines = out })
      end, { fetch = true, max_lines = 60, max_width = 76 })
      if not started then
        deliver({ lines = vim.list_extend({ "(hover.nvim could not preview this)", "" }, lines) })
        return nil
      end
      return handle
    end,
  }
end

return M
