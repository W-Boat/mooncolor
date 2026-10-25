-- Adapt Moon-owned constructors only. No global KOReader widget patching.
local Controls={}
local function walk(w,fn)
    if type(w)~="table"then return end
    fn(w)
    for _,child in ipairs(w)do walk(child,fn)end
end
function Controls.install(Engine,assign,replaceLocal)
    local BB=require("ffi/blitbuffer")
    local Theme=require("ui.themes")
    local Render=require("mooncolor_render")
    local Line=require("ui/widget/linewidget")
    local function black(c)
        if type(c)=="number"then return c==0 end
        if type(c)=="cdata"then
            local ok,gray=pcall(function()return c:getColor8().a end)
            return ok and gray==0
        end
        return false
    end
    -- Thin rules: map only the local LineWidget reference in Moon modules.
    local lineProxy=setmetatable({new=function(_,opts)
        if not Engine.active()or not Engine.config().dividers then return Line:new(opts)end
        local copy={};for k,v in pairs(opts)do copy[k]=v end
        if not Render.isRGB(copy.background)then copy.background=Engine.color(Engine.tint(.65,"borders"))end
        local widget=Line:new(copy)
        widget._moon_rule_ink=black(opts.background)
        widget.paintTo=Render.wrap(widget.paintTo)
        return widget
    end},{__index=Line})
    local function adaptLines(mod,suffix)
        local seen={}
        local function visit(fn)
            if seen[fn]then return end;seen[fn]=true
            local info=debug.getinfo(fn,"S")
            if not info or info.source:gsub("\\","/"):sub(-#suffix)~=suffix then return end
            for i=1,100 do
                local name,value=debug.getupvalue(fn,i);if not name then break end
                if name=="LineWidget"and value==Line then replaceLocal(fn,i,lineProxy)
                elseif type(value)=="function"then visit(value)end
            end
        end
        for _,fn in pairs(mod)do if type(fn)=="function"then visit(fn)end end
    end
    for _,name in ipairs{"row","titlebar","list","sheet","pager","sections","tabbar"}do
        local ok,mod=pcall(require,"ui.themes.widgets."..name)
        if ok then adaptLines(mod,"/ui/themes/widgets/"..name..".lua")end
    end
    local input_ok,Input=pcall(require,"ui.themes.widgets.input")
    Engine.coverage.inputs=input_ok
    if input_ok then
        local function frames(self)
            if not Engine.active()or not Engine.config().inputs then return end
            for i,frame in ipairs(self.frames or {})do
                local s={};for k,v in pairs(frame.style)do s[k]=v end
                s.border=math.max(1,s.border or 0)
                s.border_color=i==self.focus_idx and Engine.accentToken("primary")or Engine.tint(.45,"primary")
                frame.style=s
            end
        end
        for _,key in ipairs{"init","onSwitchFocus"}do
            local original=Input[key]
            assign(Input,key,function(self,...)
                local result=original(self,...);frames(self);return result
            end)
        end
    end
    local library_ok,Library=pcall(require,"desktop.pages.library")
    Engine.coverage.library_tabs=false
    if library_ok then
        adaptLines(Library,"/desktop/pages/library/init.lua")
        -- tabStrip is private; find its owning closure once at installation.
        local seen={}
        local function find(fn)
            if seen[fn]then return end;seen[fn]=true
            local info=debug.getinfo(fn,"S")
            if not info or not info.source:gsub("\\","/"):match("/desktop/pages/library/init%.lua$")then return end
            for i=1,100 do
                local name,value=debug.getupvalue(fn,i);if not name then break end
                if name=="tabStrip"and type(value)=="function"then
                    replaceLocal(fn,i,function(...)
                        local width=(...)
                        local widget=value(...)
                        if Engine.active()and Engine.config().tabs then
                            walk(widget,function(w)
                                if w.fgcolor and w.bold and black(w.fgcolor)then w.fgcolor=Engine.accent("navigation")end
                                if getmetatable(w)==Line and w._moon_rule_ink and w.dimen and w.dimen.h<=Theme.px(3)
                                    and w.dimen.w<width then w.background=Engine.accent("navigation")end
                            end)
                        end
                        return widget
                    end)
                    Engine.coverage.library_tabs=true
                elseif type(value)=="function"then find(value)end
            end
        end
        for _,fn in pairs(Library)do if type(fn)=="function"then find(fn)end end
    end
    local sidebar_ok,Sidebar=pcall(require,"features.sidebar")
    Engine.coverage.sidebar=sidebar_ok
    if sidebar_ok then
        adaptLines(Sidebar,"/features/sidebar/init.lua")
        local render=Sidebar.render
        assign(Sidebar,"render",function(self,...)
            local result=render(self,...)
            if Engine.active()and Engine.config().sidebar then
                walk(self[1],function(w)
                    if w.fgcolor and black(w.fgcolor)then w.fgcolor=Engine.accent("icons")end
                end)
            end
            return result
        end)
    end
end
return Controls
