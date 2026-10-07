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
---@return string|nil
local function refuse(url)
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
    return refuse(slot.url)
  end
  return nil
end

---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return boolean ok
---@return string|nil err
function M.apply(slot, ctx)
  local url, unknown = address(slot, ctx.resolve)
  util.warn_unknown(unknown, "url slot")
  local why = refuse(url)
  if why then
    return false, why
  end
  local _, err = vim.ui.open(url)
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

---@param slot table
---@return Ui.Slots.Preview
function M.preview(slot)
  local host = (slot.url or ""):match("^%a[%w+.%-]*://([^/%?#]+)")
  return { lines = { slot.url or "", "", host and ("host: " .. host) or "" } }
end

return M
