-- Scoped read-only preference view: do not overwrite Moon's saved preferences.
local Panels = {}
function Panels.install(Engine, replaceLocal)
    local Settings=require("utils.settings")
    local views=setmetatable({}, {__mode="kv"})
    local proxy=setmetatable({get=function(owner)
        local conf=Settings.get(owner)
        if owner~="ui" or not Engine.installed or not Engine.config().enabled or not Engine.config().fast_panels then return conf end
        if not views[conf] then views[conf]=setmetatable({mesh_mask=false},{__index=conf,__newindex=function(_,k,v)conf[k]=v end})end
        return views[conf]
    end},{__index=Settings})
    local function adapt(mod,suffix)
        local seen,count={},0
        local function walk(fn)
            if seen[fn]then return end;seen[fn]=true
            local info=debug.getinfo(fn,"S")
            local own=info and info.source:gsub("\\","/"):sub(-#suffix)==suffix
            for i=1,math.huge do
                local name,value=debug.getupvalue(fn,i);if not name then break end
                if own and name=="MoonSettings" and value==Settings then
                    replaceLocal(fn,i,proxy);count=count+1
                elseif type(value)=="function"then walk(value)end
            end
        end
        for _,fn in pairs(mod)do if type(fn)=="function"then walk(fn)end end
        return count
    end
    for _,entry in ipairs{
        {"ui.themes.widgets.mask","/ui/themes/widgets/mask.lua","fast_mask"},
        {"ui.themes.widgets.modal","/ui/themes/widgets/modal.lua","fast_modal"},
        {"features.panel.native","/features/panel/native.lua","fast_native_panel"},
    }do
        local ok,mod=pcall(require,entry[1])
        Engine.coverage[entry[3]]=ok and adapt(mod,entry[2])>0 or false
    end
end
return Panels
