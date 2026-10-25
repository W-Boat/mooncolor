-- Moon extension API v1. GPL-3.0-or-later.
local Editor = {}
local function notice(text)
    require("ui.themes.widgets.toast"):new{ text = text }:show()
end
function Editor.presets(engine, desktop)
    local items = {}
    for _, preset in ipairs(engine.palettes) do
        local id = preset.id
        items[#items + 1] = { text = preset.name, callback = function()
            engine.set("palette", id, desktop)
        end }
    end
    require("ui.themes.widgets.list"):new{ title = "单色 / 混色主题", items = items }:show()
end
function Editor.colors(engine, desktop)
    local items = {}
    for _, role in ipairs(engine.roles) do
        local id, name = role.id, role.name
        items[#items + 1] = { text = name .. "  " .. engine.config().custom_colors[id],
            callback = function()
                require("ui.themes.widgets.input"):new{
                    title = "自定义颜色 · " .. name,
                    fields = {{ text = engine.config().custom_colors[id],
                        label = "颜色（#RRGGBB 或 #RGB）", hint = "#205CA8" }},
                    callback = function(value)
                        local ok, err = engine.setRole(id, value, desktop)
                        if not ok then notice(err) end
                    end,
                }:show()
            end }
    end
    require("ui.themes.widgets.list"):new{ title = "按部位自定义颜色", items = items }:show()
end
function Editor.save(engine, desktop)
    require("ui.themes.widgets.input"):new{
        title = "保存当前主题",
        fields = {{ text = "", label = "主题名称", hint = "给配色取个名字" }},
        callback = function(value)
            local id, err = engine.saveTheme(value)
            if not id then notice(err) else
                engine.refresh(desktop)
                notice("主题已保存")
            end
        end,
    }:show()
end
function Editor.library(engine, desktop)
    local themes, items = engine.listThemes(), {}
    if #themes == 0 then notice("还没有保存的主题"); return end
    for _, theme in ipairs(themes) do
        local id, name = theme.id, theme.name
        items[#items + 1] = { text = name, callback = function()
            require("ui.themes.widgets.sheet"):new{ title = name, items = {
                { text = "应用主题", callback = function()
                    local ok, err = engine.loadTheme(id, desktop)
                    if not ok then notice(err) end
                end },
                { text = "删除已保存主题", callback = function()
                    engine.deleteTheme(id)
                    engine.refresh(desktop)
                    notice("已删除；当前配色保留")
                end },
            } }:show()
        end }
    end
    require("ui.themes.widgets.list"):new{ title = "我的主题", items = items }:show()
end
return Editor
