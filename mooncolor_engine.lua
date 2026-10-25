-- Moon Color, GPL-3.0-or-later. Moon-only color token adapter.
local Engine = { ID = "ext.mooncolor", VERSION = "2.0.0", installed = false, revision = 0 }
local Themes = require("mooncolor_themes")
local TAG = 0x1000000
Engine.palettes, Engine.roles = Themes.presets, Themes.roles
local defaults = { enabled = true, palette = "ocean", buttons = true,
    tabs = true, progress = true, card_edges = false, quality_refresh = false,
    icons = true, headings = true, statistics = true, navbar_style = "pill", navbar_labels = true, fast_panels = true, fast_ticket = true }
local fallback, colors = {}, {}
local cache = setmetatable({}, { __mode = "k" })
local Settings, Device, BB
local config_cache, role_tokens = nil, {}

function Engine.reload()
    config_cache, role_tokens = nil, {}
    Engine.revision = Engine.revision + 1
    cache = setmetatable({}, { __mode = "k" })
end

function Engine.config()
    if config_cache then return config_cache end
    local saved = Settings.getSource(Engine.ID)
    -- Once when upgrading: stop the previous version's forced quality refresh.
    if saved.performance_schema ~= 2 then
        saved.quality_refresh, saved.performance_schema = false, 2
        Settings.saveSource(Engine.ID)
    end
    local out = {}
    for key, value in pairs(defaults) do
        if type(saved[key]) == type(value) then out[key] = saved[key] else out[key] = value end
    end
    local valid = false
    for _, p in ipairs(Engine.palettes) do if out.palette == p.id then valid = true end end
    if not valid and out.palette ~= "custom" then out.palette = defaults.palette end
    if out.navbar_style ~= "pill" and out.navbar_style ~= "line" then out.navbar_style = "pill" end
    out.custom_colors = Themes.resolve(out.palette, saved.custom_colors)
    config_cache = out
    return config_cache
end

function Engine.active()
    if not Engine.installed or not Engine.config().enabled then return false end
    if not Device.hasColorScreen or not Device:hasColorScreen() then return false end
    if Device.screen.night_mode then return false end
    return Device.screen.isColorEnabled and Device.screen:isColorEnabled() == true
end

function Engine.status()
    if not Engine.installed then return Engine.error or "尚未接入月读" end
    if not Engine.config().enabled then return "已关闭" end
    if not Device.hasColorScreen or not Device:hasColorScreen() then return "黑白屏：保持灰度" end
    if Device.screen.night_mode then return "夜间模式：保持原主题" end
    if not Device.screen.isColorEnabled or not Device.screen:isColorEnabled() then
        return "请先在月读“界面显示”开启彩色屏幕支持，并重启 KOReader"
    end
    return "已启用彩墨配色"
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = clone(v) end
    return out
end

local function token(rgb, gray)
    local value = TAG + rgb
    fallback[value] = gray
    return value
end

-- Private proxy, installed into Moon module-local upvalues only.
-- Neither the global BB.Color8 constructor nor KOReader widgets are changed.
local function convert(value)
    if fallback[value] ~= nil then
        if not Engine.active() then return BB.Color8(fallback[value]) end
        if not colors[value] then
            local rgb = value - TAG
            colors[value] = BB.ColorRGB32(math.floor(rgb / 0x10000),
                math.floor(rgb / 0x100) % 256, rgb % 256, 255)
        end
        return colors[value]
    end
    return BB.Color8(value)
end

function Engine.accentToken(role)
    role = role or "primary"
    if not role_tokens[role] then
        role_tokens[role] = token(Themes.rgb(Engine.config().custom_colors[role] or Engine.config().custom_colors.primary), 0)
    end
    return role_tokens[role]
end

function Engine.accent(role)
    return convert(Engine.accentToken(role))
end

function Engine.tint(weight, role)
    if not Engine.active() then return 0xEE end
    local value = Engine.accentToken(role) - TAG
    local function mix(v) return math.floor(255 * (1-weight) + v * weight + 0.5) end
    local r, g, b = mix(math.floor(value/65536)), mix(math.floor(value/256)%256), mix(value%256)
    return token(r*65536+g*256+b, math.floor(255*(1-weight)+0.5))
end

Engine.color = convert

function Engine.foreground(role)
    return Themes.foreground(Engine.accentToken(role)-TAG)
end

function Engine.theme(base)
    if not Engine.active() then return base end
    local conf = Engine.config()
    local signature = Engine.revision
    local previous = cache[base]
    if previous and previous.signature == signature then return previous.theme end
    local accent = Engine.accentToken("primary")
    local t = clone(base)
    -- Keep the page and small text neutral; use color to communicate state.
    t.color.page, t.color.ink = 255, 0
    t.color.muted, t.color.faint = 0x44, 0x66
    if conf.buttons then
        t.button.primary.bg, t.button.primary.ink = accent, Engine.foreground("primary")
        t.button.primary.border_color = accent
        t.button.normal.bg, t.button.normal.ink = 255, 0
        t.button.normal.border_color = accent
        t.control.border = math.max(1, t.control.border or 0)
    end
    if conf.tabs then
        t.selected.bg, t.selected.ink = 255, Engine.accentToken("navigation")
        t.selected.mark = math.max(3, t.selected.mark or 0)
    end
    if conf.progress then t.progress.fill, t.progress.track = Engine.accentToken("progress"), 0xDD end
    if conf.card_edges then
        local border_color = Engine.accentToken("borders")
        t.card.border_color, t.raised.border_color, t.dialog.border_color = border_color, border_color, border_color
        for _, style in ipairs({ t.card, t.raised, t.dialog }) do style.border = math.max(1, style.border or 0) end
    end
    cache[base] = { signature = signature, theme = t }
    return t
end

-- Follow only functions belonging to the allowlisted Moon module itself.
-- Shared upvalues mean local helpers and later-created closures see the proxy too.
local function adapt(module, proxy, suffix, undo)
    local seen, count = {}, 0
    local function visit(fn)
        if seen[fn] then return end
        seen[fn] = true
        local info = debug.getinfo(fn, "S")
        local source = info and info.source:gsub("\\", "/") or ""
        if source:sub(-#suffix) ~= suffix then return end
        for i = 1, math.huge do
            local name, value = debug.getupvalue(fn, i)
            if not name then break end
            if name == "Blitbuffer" and value == BB then
                undo[#undo + 1] = { fn = fn, index = i, old = value, replacement = proxy }
                debug.setupvalue(fn, i, proxy)
                count = count + 1
            elseif type(value) == "function" then
                visit(value)
            end
        end
    end
    for _, value in pairs(module) do if type(value) == "function" then visit(value) end end
    return count
end

local function quality(widget, mode, region)
    if not Engine.active() or not Engine.config().quality_refresh
        or type(widget) ~= "table" or widget.book_window ~= true
        or not Device.hasKaleidoWfm or not Device:hasKaleidoWfm() then return mode end
    if mode ~= nil and mode ~= "ui" and mode ~= "partial" then return mode end
    -- Keep small clock/slider/progress updates fast. Full-color waveforms for
    -- page/dialog transitions; do not alter reading-page or native UI refreshes.
    if region and region.w and region.h
        and region.w * region.h < Device.screen:getWidth() * Device.screen:getHeight() / 3 then return mode end
    return "full"
end

function Engine.install()
    if Engine.installed then return true end
    local undo = {}
    local function assign(object, key, value)
        undo[#undo + 1] = { object = object, key = key, old = object[key], replacement = value }
        object[key] = value
    end
    local function replaceLocal(fn,index,value)
        local _,old=debug.getupvalue(fn,index)
        undo[#undo+1]={fn=fn,index=index,old=old,replacement=value}
        debug.setupvalue(fn,index,value)
    end
    local ok, err = pcall(function()
        Settings, Device, BB = require("utils.settings"), require("device"), require("ffi/blitbuffer")
        assert(type(Settings.getSource) == "function" and type(Settings.saveSource) == "function", "月读缺少扩展配置接口")
        local Theme = require("ui.themes")
        local base = Theme.current()
        assert(type(base) == "table" and base.button and base.selected and base.progress and base.card
            and base.raised and base.dialog and base.color, "月读主题接口不兼容，请更新月读")
        assert(BB.ColorRGB32 and debug.getupvalue and debug.setupvalue, "缺少 RGB 或 LuaJIT 适配接口")
        local names = { "text", "box", "button", "row", "tabbar", "progress", "icon_picker" }
        local modules = {}
        -- Resolve dependencies before publishing a theme containing tagged values.
        for _, name in ipairs(names) do modules[name] = require("ui.themes.widgets." .. name) end
        local panel_ok, panel = pcall(require, "features.panel.widget.button")
        local proxy = setmetatable({ Color8 = convert }, { __index = BB })
        local total = 0
        for name, mod in pairs(modules) do
            local count = adapt(mod, proxy, "/ui/themes/widgets/" .. name .. ".lua", undo)
            assert(count > 0, "月读控件接口不兼容：" .. name)
            total = total + count
        end
        if panel_ok then adapt(panel, proxy, "/features/panel/widget/button.lua", undo) end
        local Render = require("mooncolor_render")
        for _, mod in ipairs({ modules.box, modules.progress, require("ui.themes.widgets.modal") }) do
            assign(mod, "paintTo", Render.wrap(mod.paintTo))
        end
        local original = Theme.current
        assign(Theme, "current", function() return Engine.theme(original()) end)
        require("mooncolor_decor").install(Engine, assign)
        require("mooncolor_nav").install(Engine, assign)
        require("mooncolor_panels").install(Engine,replaceLocal)
        local UIManager = require("ui/uimanager")
        local dirty, close = UIManager.setDirty, UIManager.close
        assign(UIManager, "setDirty", function(self, widget, mode, region, dither)
            if not Engine.config().quality_refresh then return dirty(self, widget, mode, region, dither) end
            if type(mode) == "function" and type(widget) == "table" and widget.book_window then
                local callback = mode
                mode = function()
                    local m, r, d = callback()
                    return quality(widget, m, r), r, d
                end
            elseif type(mode) ~= "function" then mode = quality(widget, mode, region) end
            return dirty(self, widget, mode, region, dither)
        end)
        assign(UIManager, "close", function(self, widget, mode, region, dither)
            if not Engine.config().quality_refresh then return close(self, widget, mode, region, dither) end
            if type(mode) ~= "function" then mode = quality(widget, mode, region) end
            return close(self, widget, mode, region, dither)
        end)
        Engine.adapters = total
        Engine.installed, Engine.error = true, nil
    end)
    if not ok then
        for i = #undo, 1, -1 do
            local item = undo[i]
            if item.fn then
                local _, current = debug.getupvalue(item.fn, item.index)
                if current == item.replacement then debug.setupvalue(item.fn, item.index, item.old) end
            elseif item.object[item.key] == item.replacement then item.object[item.key] = item.old end
        end
        Engine.error = "Moon Color 未启用：" .. tostring(err)
        pcall(function() require("logger").warn(Engine.error) end)
    end
    return Engine.installed
end

function Engine.refresh(desktop, clean)
    if not desktop or desktop.closed then return end
    local overlay = desktop.settings_overlay
    while overlay do
        overlay.theme = require("ui.themes").current()
        overlay = overlay.parent
    end
    desktop._shell = nil -- Rebuild topbar and content geometry after nav height/theme changes.
    desktop:updateView()
    require("ui/uimanager"):setDirty(desktop, clean and "full" or "ui")
end

function Engine.set(key, value, desktop)
    if not Engine.install() then return false end
    if defaults[key] == nil or type(value) ~= type(defaults[key]) then return false end
    if key == "palette" then
        local found = false
        for _, p in ipairs(Engine.palettes) do if p.id == value then found = true end end
        if not found and value ~= "custom" then return false end
    end
    if key == "navbar_style" and value ~= "pill" and value ~= "line" then return false end
    if Engine.config()[key] == value then return true end
    Settings.getSource(Engine.ID)[key] = value
    if key == "palette" then Settings.getSource(Engine.ID).active_theme_name = nil end
    Settings.saveSource(Engine.ID)
    Engine.reload()
    Engine.refresh(desktop, key == "palette")
    return true
end

function Engine.commit(mutator, desktop, clean)
    if not Engine.install() then return false, Engine.status() end
    mutator(Settings.getSource(Engine.ID))
    Settings.saveSource(Engine.ID)
    Engine.reload()
    Engine.refresh(desktop, clean)
    return true
end

function Engine.setRole(id, value, desktop)
    local found=false
    for _,role in ipairs(Engine.roles)do if role.id==id then found=true end end
    local hex=Themes.hex(value)
    if not found then return false,"未知的颜色项目" end
    if not hex then return false,"请输入 #RRGGBB 或 #RGB 颜色" end
    local custom=clone(Engine.config().custom_colors)
    custom[id]=hex
    local flags={primary="buttons",icons="icons",headings="headings",navigation="tabs",progress="progress",
        stat1="statistics",stat2="statistics",stat3="statistics",borders="card_edges"}
    return Engine.commit(function(saved)
        saved.custom_colors,saved.palette,saved.active_theme_name=custom,"custom",nil
        saved[flags[id]]=true
    end,desktop,true)
end

local theme_keys={"buttons","tabs","progress","icons","headings","statistics","card_edges","navbar_style","navbar_labels"}
function Engine.listThemes()
    local raw=Settings.getSource(Engine.ID).saved_themes
    local out={}
    if type(raw)=="table"then
        for _,item in ipairs(raw)do
            if type(item)=="table" and type(item.id)=="string" and type(item.name)=="string" and type(item.colors)=="table"then
                local copy={id=item.id,name=item.name,colors=Themes.resolve("custom",item.colors),settings={}}
                for _,k in ipairs(theme_keys)do
                    if type(item.settings)=="table" and type(item.settings[k])==type(defaults[k])then copy.settings[k]=item.settings[k]end
                end
                out[#out+1]=copy
            end
        end
    end
    return out
end

function Engine.saveTheme(name)
    if type(name)~="string"then return nil,"请输入主题名称"end
    name=name:match("^%s*(.-)%s*$")
    local _,length=name:gsub("[^\128-\191]","")
    if name=="" or name:find("[%z\1-\31]") or length>32 then return nil,"名称需为 1–32 个字符"end
    local list=Engine.listThemes()
    if #list>=12 then return nil,"最多保存 12 套主题，请先删除不用的主题"end
    for _,item in ipairs(list)do if item.name==name then return nil,"主题名称已存在"end end
    local conf=Engine.config()
    local item={name=name,colors=clone(conf.custom_colors),settings={}}
    for _,k in ipairs(theme_keys)do item.settings[k]=conf[k]end
    Engine.commit(function(saved)
        local n=math.floor(tonumber(saved.theme_counter)or 0)+1
        local exists={};for _,v in ipairs(list)do exists[v.id]=true end
        while exists["user_"..n]do n=n+1 end
        item.id="user_"..n;list[#list+1]=item
        saved.theme_counter,saved.saved_themes=n,list
    end)
    return item.id
end

function Engine.loadTheme(id,desktop)
    for _,item in ipairs(Engine.listThemes())do
        if item.id==id then return Engine.commit(function(saved)
            saved.palette,saved.custom_colors,saved.active_theme_name="custom",clone(item.colors),item.name
            for _,k in ipairs(theme_keys)do if item.settings[k]~=nil then saved[k]=item.settings[k]end end
        end,desktop,true)end
    end
    return false,"找不到该主题"
end

function Engine.deleteTheme(id)
    local list=Engine.listThemes()
    for i,item in ipairs(list)do if item.id==id then
        table.remove(list,i)
        return Engine.commit(function(saved)saved.saved_themes=list end)
    end end
    return false,"找不到该主题"
end

function Engine.themeName()
    local conf=Engine.config()
    if conf.palette=="custom" then return Settings.getSource(Engine.ID).active_theme_name or "自定义 / 混色"end
    return (Themes.find(conf.palette)or Engine.palettes[1]).name
end

return Engine
