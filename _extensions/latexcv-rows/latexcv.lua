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

--- Render a `::: {.interrupt}` div as a one-line band.
---
--- Upstream runs two of these down its page -- a filled strip under the title
--- carrying a summary, and a darker one between two sections pointing at a
--- link. Neither names a section, so neither can be written as a heading, and
--- there is nowhere else in the document for them to come from.
---
--- `.dark` picks the second of the two: filled in the dark neutral, and
--- without the chevrons that flank the accent one, as upstream sets them.
---
--- The content is flattened to inlines because an interrupt row is one line by
--- definition. A div holding several paragraphs is not a different kind of
--- interrupt row, it is a section.
local function interrupt_row(el)
  local dark = el.classes:includes("dark")
  local fill = dark and "bgcol" or "sectcol"
  local marks = dark and "" or "bgcol"

  local inlines = pandoc.List({
    raw("\\begin{cvinterrupt}{" .. fill .. "}{" .. marks .. "}"),
  })
  inlines:extend(pandoc.utils.blocks_to_inlines(el.content))
  inlines:insert(raw("\\end{cvinterrupt}"))

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
--- The heading is left where it was written, outside the band it introduces,
--- but it is not set there: in this style a section is named down the right
--- margin of its own band, so \cvsection only records the heading and the band
--- draws it. That is also why the heading is not moved inside the band -- it
--- has to be recorded before the band begins, and a band is opened here
--- without knowing how tall it will turn out to be.
--- @param has_photo boolean whether the document carries a `profilepic`.
local function band_sections(blocks, has_photo)
  local out = pandoc.List({})
  local band = nil
  -- Blocks written before the first heading. They belong to neither a section
  -- nor a band of their own, and upstream puts exactly this material -- its
  -- \metasection block -- beside the photograph above the first section. So
  -- they are collected rather than emitted, and go into the intro band.
  local intro = pandoc.List({})
  local intro_open = true
  -- Whether a level-1 heading has been seen and not yet closed off. A band can
  -- be reopened while this holds -- see the interrupt row below -- and outside
  -- it there is no section for stray content to belong to.
  local in_section = false
  -- Set on a band that continues a section an earlier band already named, so
  -- that the name is not repeated down the side of both halves.
  local continuing = false
  local index = 0

  local function close_band()
    if not band or #band == 0 then
      band = nil
      return
    end
    -- `light` and `white` alternate, so consecutive sections stay apart
    -- without the shading building up. A continuation keeps its section's
    -- shade: the two halves are one section, and shading them differently
    -- would say they were two.
    local shade = (index % 2 == 1) and "lightcol" or "white"
    if continuing then
      out:insert(raw_block("\\cvbandnotitle"))
    end
    out:insert(raw_block("\\begin{cvband}{" .. shade .. "}"))
    out:extend(band)
    out:insert(raw_block("\\end{cvband}"))
    band = nil
  end

  -- Whether the photograph is still looking for a band to sit in. It goes in
  -- the first intro band there is, and an interrupt row can split the material
  -- before the first heading into more than one -- upstream's own summary strip
  -- sits between its title and its photo, so that ordering has to survive.
  local photo_pending = has_photo

  -- Emit what has been collected so far as one intro band, keeping it where it
  -- was written. Nothing collected means no band: an empty one would be a
  -- white strip with nothing in it.
  local function flush_intro()
    if #intro == 0 then return end
    local env = photo_pending and "cvintro" or "cvintroplain"
    photo_pending = false
    out:insert(raw_block("\\begin{" .. env .. "}"))
    out:extend(intro)
    out:insert(raw_block("\\end{" .. env .. "}"))
    intro = pandoc.List({})
  end

  -- Close off the region before the first heading. A photo that never found a
  -- band gets one of its own here, which is the case of a document that sets
  -- `profilepic` and then writes nothing before its first section.
  local function close_intro()
    if not intro_open then return end
    intro_open = false
    flush_intro()
    if photo_pending then
      photo_pending = false
      out:insert(raw_block("\\begin{cvintro}\\end{cvintro}"))
    end
  end

  for _, block in ipairs(blocks) do
    if block.t == "Header" and block.level == 1 then
      close_intro()
      close_band()
      index = index + 1
      out:insert(block)
      band = pandoc.List({})
      in_section = true
      continuing = false
    elseif block.t == "Div" and block.classes:includes("interrupt") then
      -- An interrupt row is a band of its own, so it ends whichever band it
      -- was written inside. Anything after it reopens one, rather than the
      -- band being reopened here: an interrupt row written at the end of a
      -- section -- which is where upstream puts both of its own -- would
      -- otherwise be followed by an empty band, and an empty band is still
      -- \cvbandheight tall.
      -- Before the first heading there is no band to close, but there may be
      -- collected intro material, which was written above this row and has to
      -- stay above it.
      if not in_section then flush_intro() end
      close_band()
      out:insert(interrupt_row(block))
      continuing = in_section
    elseif in_section then
      if not band then band = pandoc.List({}) end
      band:insert(block)
    else
      -- Before the first heading: held for the intro band.
      intro:insert(block)
    end
  end
  close_intro()
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
    -- Whether to leave room for the photograph beside the intro material. The
    -- template draws it; this only decides which band it belongs to, which is
    -- a question about the document's blocks and so has to be settled here.
    local photo = doc.meta.profilepic
    local has_photo = photo ~= nil and pandoc.utils.stringify(photo) ~= ""
    doc.blocks = band_sections(doc.blocks, has_photo)
  end

  return doc:walk({ Header = rewrite_header })
end
