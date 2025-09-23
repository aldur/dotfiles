local title

-- Set title from level 1 headers, unless it has been set before.
local function first_header_as_title (header)

  if header.level >= 2 then
    return header
  end

  if not title then
    title = header.content
    return {}
  end

  local msg = '[WARNING] title already set; discarding header "%s"\n'
  io.stderr:write(msg:format(pandoc.utils.stringify(header)))
  return {}
end

return {
  {Meta = function (meta) title = meta.title end}, -- init title
  {Header = first_header_as_title},
  {Meta = function (meta) meta.title = title; return meta end}, -- set title
}
