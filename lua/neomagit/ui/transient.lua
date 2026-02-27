local M = {}

function M.select(prompt, items, cb)
  vim.ui.select(items, {
    prompt = prompt,
    format_item = function(item)
      if type(item) == "table" and item.label then
        return item.label
      end
      return tostring(item)
    end,
  }, function(choice)
    cb(choice)
  end)
end

function M.input(prompt, default, cb)
  vim.ui.input({
    prompt = prompt,
    default = default,
  }, function(value)
    cb(value)
  end)
end

function M.confirm(message, default_yes)
  local default = default_yes and 1 or 2
  return vim.fn.confirm(message, "&Yes\n&No", default) == 1
end

return M
