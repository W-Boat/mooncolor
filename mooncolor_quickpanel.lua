-- Reuse only Moon panel bodies, for the lifetime of one native menu.
-- Native menu items remain live; no persistent widgets, background jobs or timers.
local Quick = {}
function Quick.install(Engine, assign, replaceLocal)
    local Native = require("features.panel.native")
    local menus = setmetatable({}, {__mode="k"})
    local function enabled()
        return Engine.installed and not Engine.suspended and Engine.config().enabled
            and Engine.config().fast_panels
    end
    local function own(fn, suffix)
        local info = debug.getinfo(fn,"S")
        return info and info.source:gsub("\\","/"):sub(-#suffix)==suffix
    end
    local function replaceNamed(mod, suffix, name, wrap)
        local seen, count = {}, 0
        local function visit(fn)
            if seen[fn] then return end
            local owner=own(fn,suffix)
            if not owner and not own(fn,"/mooncolor_quickpanel.lua") then return end
            seen[fn]=true
            for i=1,100 do
                local key,value=debug.getupvalue(fn,i); if not key then break end
                if owner and key==name and type(value)=="function" then
                    replaceLocal(fn,i,wrap(value)); count=count+1
                elseif type(value)=="function" then visit(value) end
            end
        end
        for _,fn in pairs(mod) do if type(fn)=="function" then visit(fn) end end
        return count>0
    end
    local function dispose(entry)
        if not entry or entry.disposed then return end
        entry.disposed=true
        -- Keep free() inert until menu teardown, including subsequent parent free.
        if entry.free then entry.free(entry.widget) end
    end
    local function clear(menu)
        local entries=menus[menu]; menus[menu]=nil
        for _,entry in pairs(entries or {}) do dispose(entry) end
    end
    local function hook(Touch)
        if Touch._mooncolor_body_cleanup then return end
        assign(Touch,"_mooncolor_body_cleanup",true)
        for _,method in ipairs{"onCloseWidget","free"} do
            local original=Touch[method]
            if original then assign(Touch,method,function(menu,...)
                clear(menu)
                return original(menu,...)
            end) end
        end
    end
    -- Closing also clears the body which is currently detached from item_group.
    Engine.coverage.quickpanel_cleanup=replaceNamed(Native,"/features/panel/native.lua",
        "patchTouchMenu",function(original)
            return function(...)
                original(...)
                local Touch=require("ui/widget/touchmenu")
                hook(Touch)
            end
        end)
    -- Moon may have installed its native menu hooks before this plugin starts.
    local Touch=package.loaded["ui/widget/touchmenu"]
    if Touch and Touch._book_panel_patched and not Touch._mooncolor_body_cleanup then
        hook(Touch)
    end
    local function stamp(menu,W,actions,sliders)
        local tab=menu.item_table
        local values={}
        local function add(v)
            local s=tostring(v); values[#values+1]=#s..":"..s
        end
        add(tab);add(tab._book_ui);add(menu.show_parent);add(menu.item_width)
        add(Engine.revision);add(W.Theme.current());add(W.Theme.px(100))
        add(require("device").screen.night_mode)
        for _,action in ipairs(actions) do
            for _,key in ipairs{"id","title","icon","active","hold"} do add(action[key]) end
        end
        for _,slider in ipairs(sliders or {}) do add(slider.kind);add(slider.title);add(slider.value) end
        if tab._book_reader_panel then
            local s=require("reader.session").current() or {}
            local id=s.identity or {};local book=id.book or {}
            for _,v in ipairs{"page","total_pages","percent","reading_chapter_idx"} do add(s[v]) end
            add(id.stable_id);add(id.source_id);add(id.chapter_idx);add(book.title);add(book.authors)
            local toc=s.chapter and s.chapter.toc or s.ui and s.ui.toc and s.ui.toc.toc
            add(toc);add(toc and #toc)
        end
        return table.concat(values,"|")
    end
    Engine.coverage.quickpanel_reuse=replaceNamed(Native,"/features/panel/native.lua",
        "buildPanel",function(original)
            return function(menu,W)
                local tab=menu.item_table
                if not enabled() or tab._book_panel_editing then
                    clear(menu)
                    return original(menu,W)
                end
                local reader=tab._book_reader_panel
                local actions=reader and W.ReaderPanel.actions(tab._book_ui) or W.Desktop.menuActions()
                local sliders=not reader and W.Desktop.sliders() or nil
                local key=stamp(menu,W,actions,sliders)
                local entries=menus[menu]
                if not entries then entries={};menus[menu]=entries end
                local slot=reader and "reader" or "desktop"
                local entry=entries[slot]
                if entry and entry.key==key then return entry.widget end
                dispose(entry);entries[slot]=nil
                -- Feed the already sampled dynamic values to Moon's original builder.
                local view=setmetatable({
                    ReaderPanel=setmetatable({actions=function()return actions end},{__index=W.ReaderPanel}),
                    Desktop=setmetatable({menuActions=function()return actions end,
                        sliders=function()return sliders end},{__index=W.Desktop}),
                },{__index=W})
                local widget=original(menu,view)
                entry={key=key,widget=widget,free=widget.free}
                -- VerticalGroup.clear calls free on every tab change. The menu owns
                -- these at most two bodies until close or explicit invalidation.
                widget.free=function()end
                entries[slot]=entry
                return widget
            end
        end)
    -- A header is informational: opening it must not fill/parse an empty TOC.
    local ok,Header=pcall(require,"features.panel.widget.header")
    Engine.coverage.quickpanel_header=ok and replaceNamed(Header,"/features/panel/widget/header.lua",
        "bookInfo",function(original)
            return function(...)
                if not enabled() then return original(...) end
                local Session=require("reader.session")
                local s=Session.current();local id=s and s.identity or {}
                if id.chapter_idx then return original(...) end
                local book=id.book or {};local percent=s and s.percent or 0
                local page,total=Session.bookPages()
                local _=require("gettext")
                local progress=string.format("%d%%",math.floor(percent+0.5))
                if total>0 then progress=string.format(_("第 %d/%d 页"),page,total).." · "..progress end
                local toc=s and s.ui and s.ui.toc and s.ui.toc.toc
                local chapter=toc and s.reading_chapter_idx and toc[s.reading_chapter_idx]
                return {title=book.title or _("阅读"),authors=book.authors or "",
                    chapter=chapter and chapter.title or "",progress=progress,percent=percent,
                    cover=id.stable_id and require("utils.paths").coverPath(id.stable_id,id.source_id)}
            end
        end) or false
    local action_ok,action=pcall(require,"features.panel.actions.reader.toc")
    if action_ok and type(action.available)=="function" and own(action.available,"/features/panel/actions/reader/toc.lua") then
        -- This availability query previously parsed TOC before noticing the native
        -- TOC action already exists. Keep actual navigation on the original path.
        local original=action.available
        assign(action,"available",function(ctx)
            local ui=ctx and ctx.ui
            if enabled() and ui and ui.toc and ui.toc.onShowToc then return true end
            return original(ctx)
        end)
    end
end
return Quick
