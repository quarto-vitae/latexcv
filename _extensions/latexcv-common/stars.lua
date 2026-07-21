--[[
  `stars` -- a star rating, written as content rather than as a field.

    {{< stars 4 >}}       four filled stars out of five
    {{< stars 8/10 >}}    eight out of ten, as upstream's `sidebar` rates its
                          fields

  Usable anywhere text is: a cell of an entries table, a sidebar item, a
  sentence. That is the point of making it a shortcode. A rating is a way of
  writing a value, so binding it to a named column of a listing would mean
  every style had to agree on which column that was, and a document could then
  only rate the one thing that column was for.

  The drawing itself is \cvstars in latexcv-preamble.tex, so a style can
  recolour a rating without this filter knowing anything about the palette.
]]

local DEFAULT_TOTAL = 5

--- Read "8/10", "8 / 10" or "8" into filled and total.
---
--- Returns nil when the argument is not a rating, so the caller can leave the
--- shortcode alone and let the author see what they wrote.
local function parse(text)
  local filled, total = text:match("^%s*(%d+)%s*/%s*(%d+)%s*$")
  if filled then
    return tonumber(filled), tonumber(total)
  end

  filled = text:match("^%s*(%d+)%s*$")
  if filled then
    return tonumber(filled), DEFAULT_TOTAL
  end
end

return {
  -- `context` is "inline", "block" or "text". The first two take a pandoc
  -- element, so a rating is returned as a RawInline and a non-LaTeX render
  -- still has something to work with. "text" is where Quarto can only
  -- substitute a string, and there the LaTeX is returned as one.
  ["stars"] = function(args, kwargs, meta, raw_args, context)
    local function nothing()
      if context == "text" then return "" end
      return pandoc.Null()
    end

    if #args == 0 then
      quarto.log.warning("stars: no rating given, expected {{< stars 4 >}} or {{< stars 8/10 >}}")
      return nothing()
    end

    local text = pandoc.utils.stringify(args[1])
    local filled, total = parse(text)

    if not filled then
      quarto.log.warning("stars: cannot read '" .. text ..
        "' as a rating, expected a count like 4 or a fraction like 8/10")
      return nothing()
    end

    -- A rating of more than its own total is a typo rather than an intent, but
    -- drawing it would loop past the end of the run and print nothing at all.
    if filled > total then
      quarto.log.warning("stars: " .. text .. " is more than its total; showing " .. total)
      filled = total
    end

    if quarto.doc.is_format("latex") then
      local latex = "\\cvstars{" .. filled .. "}{" .. total .. "}"
      if context == "text" then return latex end
      return pandoc.RawInline("latex", latex)
    end

    -- Every latexcv style is a pdf format, so this is only reached when a
    -- document is rendered to something else for a quick look. Unicode stars
    -- keep it readable without pulling in any styling.
    local unicode = string.rep("★", filled) .. string.rep("☆", total - filled)
    if context == "text" then return unicode end
    return pandoc.Str(unicode)
  end,
}
