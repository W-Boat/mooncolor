-- Small extension runtime. Theme and color rendering belong to Moon itself.
local Engine={ID="ext.mooncolor",VERSION="3.1.0",installed=false,suspended=false,coverage={}}
local defaults={enabled=true,navbar_style="pill",navbar_labels=true,navbar_compact=false,
    sidebar_style="pill",sidebar_labels=true,sidebar_compact=false,
    loading_screen=true,loading_style="book"}
local config,Settings
function Engine.reload()config=nil end
function Engine.config()
    if config then return config end
    Settings=Settings or require("utils.settings")
    local saved=Settings.getSource(Engine.ID)
    config={}
    for key,value in pairs(defaults)do
        if type(saved[key])==type(value)then config[key]=saved[key]else config[key]=value end
    end
    if config.navbar_style~="pill"and config.navbar_style~="line"then config.navbar_style="pill"end
    for _,key in ipairs{"style","labels","compact"}do
        if saved["sidebar_"..key]==nil then config["sidebar_"..key]=config["navbar_"..key]end
    end
    if config.sidebar_style~="pill"and config.sidebar_style~="line"then config.sidebar_style="pill"end
    if config.loading_style~="book"and config.loading_style~="simple"then config.loading_style="book"end
    return config
end
function Engine.status()
    if not Engine.installed then return Engine.error or "尚未接入月读"end
    return Engine.config().enabled and "底栏与开书遮罩已启用" or "已关闭"
end
function Engine.install()
    if Engine.installed then return true end
    local undo={}
    local function assign(object,key,value)
        undo[#undo+1]={object=object,key=key,old=object[key]}
        object[key]=value
    end
    local ok,err=pcall(function()
        Settings=require("utils.settings")
        assert(type(Settings.getSource)=="function"and type(Settings.saveSource)=="function","请更新月读")
        require("mooncolor_nav").install(Engine,assign)
        require("mooncolor_loading").install(Engine,assign)
    end)
    if not ok then
        for i=#undo,1,-1 do local item=undo[i];item.object[item.key]=item.old end
        Engine.error="moonflow 未启用："..tostring(err)
        return false
    end
    Engine.installed,Engine.error=true,nil
    return true
end
function Engine.refresh(desktop)
    if Engine.suspended or not desktop or desktop.closed then return end
    desktop._shell=nil
    desktop:updateView()
    -- Desktop.updateView owns its dirty regions; do not enqueue another refresh.
end
function Engine.set(key,value,desktop)
    if not Engine.install()then return false end
    if defaults[key]==nil or type(defaults[key])~=type(value)then return false end
    if(key=="navbar_style"or key=="sidebar_style")and value~="pill"and value~="line"then return false end
    if key=="loading_style"and value~="book"and value~="simple"then return false end
    if Engine.config()[key]==value then return true end
    Settings.getSource(Engine.ID)[key]=value
    Settings.saveSource(Engine.ID)
    Engine.reload()
    if (key=="enabled"and not value)or(key=="loading_screen"and not value)then
        require("mooncolor_loading").finish()
    end
    if key~="loading_screen"and key~="loading_style"then Engine.refresh(desktop)end
    return true
end
function Engine.suspend()
    Engine.suspended=true
    require("mooncolor_loading").finish()
end
function Engine.resume()Engine.suspended=false end
return Engine
