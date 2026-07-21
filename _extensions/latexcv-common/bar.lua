--[[
  `bar` -- a rating drawn as a filled bar, written as content rather than as a
  field. The companion to `stars`, and read the same way.

    {{< bar 80% >}}   four fifths filled
    {{< bar 0.8 >}}   the same, as a fraction
    {{< bar 8/10 >}}  the same again
    {{< bar 80 >}}    the same: a bare number above 1 is read as a percentage

  Usable anywhere text is: a cell of an entries table, a sidebar item, a
  sentence. That is the point of making it a shortcode. A rating is a way of
  writing a value, so binding it to a named column of a listing would mean every
  style had to agree on which column that was, and a document could then only
  rate the one thing that column was for.

  The drawing itself is \cvbar in latexcv-preamble.tex, so a style can recolour
  a bar, resize it, or give it a line of its own without this filter knowing
  anything about the palette or the page.
]]

--- Read "80%", "0.8", "8/10" or "80" into a fraction between 0 and 1.
---
--- Returns nil when the argument is not a proportion, so the caller can leave
--- the shortcode alone and let the author see what they wrote.
local function parse(text)
  local pct = text:match("^%s*([%d%.]+)%s*%%%s*$")
  if pct then
    local n = tonumber(pct)
    if n then return n / 100 end
    return nil
  end

  local num, den = text:match("^%s*([%d%.]+)%s*/%s*([%d%.]+)%s*$")
  if num then
    num, den = tonumber(num), tonumber(den)
    -- A denominator of nothing is not a rating of everything; it is a typo.
    if num and den and den ~= 0 then return num / den end
    return nil
  end

  local bare = text:match("^%s*([%d%.]+)%s*$")
  if bare then
    local n = tonumber(bare)
    if not n then return nil end
    -- `0.8` and `80` both mean four fifths. The two cannot collide: a fraction
    -- of a whole is never above 1, and a percentage below 1 would be a rating
    -- of nothing worth drawing. 1 is 100% under either reading.
    if n <= 1 then return n end
    return n / 100
  end
end

return {
  -- `context` is "inline", "block" or "text". The first two take a pandoc
  -- element, so a rating is returned as a RawInline and a non-LaTeX render
  -- still has something to work with. "text" is where Quarto can only
  -- substitute a string, and there the LaTeX is returned as one.
  ["bar"] = function(args, kwargs, meta, raw_args, context)
    local function nothing()
      if context == "text" then return "" end
      return pandoc.Null()
    end

    if #args == 0 then
      quarto.log.warning("bar: no rating given, expected {{< bar 80% >}} or {{< bar 8/10 >}}")
      return nothing()
    end

    local text = pandoc.utils.stringify(args[1])
    local filled = parse(text)

    if not filled then
      quarto.log.warning("bar: cannot read '" .. text ..
        "' as a proportion, expected something like 80%, 0.8 or 8/10")
      return nothing()
    end

    -- Past the end of the track is a typo rather than an intent, and drawing it
    -- would run the fill out of the picture and past whatever is beside it.
    if filled > 1 then
      quarto.log.warning("bar: " .. text .. " is more than a whole; showing 100%")
      filled = 1
    end

    if quarto.doc.is_format("latex") then
      local latex = string.format("\\cvbar{%.4f}", filled)
      if context == "text" then return latex end
      return pandoc.RawInline("latex", latex)
    end

    -- Every latexcv style is a pdf format, so this is only reached when a
    -- document is rendered to something else for a quick look. Block characters
    -- keep it readable without pulling in any styling.
    local segments = 10
    local full = math.floor(filled * segments + 0.5)
    local unicode = string.rep("█", full) .. string.rep("░", segments - full)
    if context == "text" then return unicode end
    return pandoc.Str(unicode)
  end,
}
