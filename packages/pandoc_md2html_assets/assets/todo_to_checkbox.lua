local list_text_map = {
    ["TODO:"] = "☐",
    ["DONE:"] = "☒",
}

local function replace(e)
    if e.content[1].t ~= 'Str' then return e end

    local mapped = list_text_map[e.content[1].text]
    if mapped ~= nil then e.content[1] = pandoc.Str(mapped) end
    return e
end

local function todo_to_checkbox(elem)
    return pandoc.walk_block(elem, {
        Plain = replace,
        Para = replace,
    })
end

return {
  {
    BulletList = todo_to_checkbox,
    OrderedList = todo_to_checkbox,
  }
}
