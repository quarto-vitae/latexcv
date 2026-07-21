--[[
  Render Markdown headings as latexcv section headings, and group the document
  into bands for the `rows` style.

  Upstream's styles style their headings through \cvsection rather than through
  LaTeX's own \section, and none of them define a second level. Both commands
  are declared by each `latexcv-<style>.tex`, and mapped onto `#` and `##`
  here, so that a document is written in ordinary Markdown and the styles stay
  free to disagree about what a heading looks like.

  Only levels 1 and 2 are remapped, since those are the only two the styles
  define. Level 3 and below fall through to the article class's own
  \subsubsection.
]]

local function raw(s)
  return pandoc.RawInline("latex", s)
end

local function raw_block(s)
  return pandoc.RawBlock("latex", s)
end

local function heading_command(level)
  if level == 1 then
    return "\\cvsection"
  elseif level == 2 then
    return "\\cvsubsection"
  end
end

local function rewrite_header(el)
  local cmd = heading_command(el.level)
  if not cmd then
    return nil
  end

  -- Built around the heading's inlines rather than stringifying them, so
  -- emphasis, links and inline code in a heading survive.
  local inlines = pandoc.List({ raw(cmd .. "{") })
  inlines:extend(el.content)
  inlines:insert(raw("}"))

  -- \label after the heading, so `@sec-education` resolves to the right page.
  if el.identifier and el.identifier ~= "" then
    inlines:insert(raw("\\label{" .. el.identifier .. "}"))
  end

  return pandoc.Plain(inlines)
end

--- Wrap each level-1 section in a band, for the `rows` style.
---
--- Upstream's `rows` is a stack of full-width blocks in alternating shades,
--- each a minipage of a hand-measured fraction of the text height. Those
--- fractions only add up for the content upstream happens to ship, so the
--- bands are derived from the document here instead: one per level-1 section,
--- shaded alternately, and sized by what it contains.
---
--- The heading itself stays outside the band it introduces, since it is
--- already a filled bar in this style and would otherwise sit on a second
--- background.
local function band_sections(blocks)
  local out = pandoc.List({})
  local band = nil
  local index = 0

  local function close_band()
    if not band then return end
    -- `light` and `white` alternate, so consecutive sections stay apart
    -- without the shading building up.
    local shade = (index % 2 == 1) and "lightcol" or "white"
    out:insert(raw_block("\\begin{cvband}{" .. shade .. "}"))
    out:extend(band)
    out:insert(raw_block("\\end{cvband}"))
    band = nil
  end

  for _, block in ipairs(blocks) do
    if block.t == "Header" and block.level == 1 then
      close_band()
      index = index + 1
      out:insert(block)
      band = pandoc.List({})
    elseif band then
      band:insert(block)
    else
      -- Anything before the first heading is not part of a band.
      out:insert(block)
    end
  end
  close_band()

  return out
end

-- The document is walked from here rather than from a top-level Header
-- function, because the metadata saying which style this is must be read
-- before anything is rewritten, and Pandoc walks Meta *after* blocks.
function Pandoc(doc)
  if not FORMAT:match("latex") then
    return nil
  end

  -- Banding runs first, so that it sees real Header elements rather than the
  -- raw \cvsection calls the rewrite leaves behind.
  if doc.meta["latexcv-rows"] == true then
    doc.blocks = band_sections(doc.blocks)
  end

  return doc:walk({ Header = rewrite_header })
end
