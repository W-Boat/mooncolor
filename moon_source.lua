local Engine=require("mooncolor_engine")
local function entries(desktop)
    Engine.install()
    local function row(opts)return require("ui.themes.widgets.row").widget(opts)end
    local function toggle(key,title,subtitle)
        return function(width)return row{width=width,title=title,subtitle=subtitle,
            toggle=Engine.config()[key],callback=function()Engine.set(key,not Engine.config()[key],desktop)end}end
    end
    return {{group="desktop",order=310,id="appearance",icon="navigation",
        title="底栏与开书遮罩",subtitle="Moon Color "..Engine.VERSION,
        page={title="底栏与开书遮罩",sections=function()
            local Update=require("mooncolor_update")
            return {{title="界面增强",rows={
                toggle("enabled","启用界面增强",Engine.status()),
                toggle("navbar_labels","显示底栏文字","关闭后仅显示图标，长按查看名称"),
                function(width)return row{width=width,title="底栏样式",
                    status=Engine.config().navbar_style=="pill"and"胶囊高亮"or"短线指示",
                    callback=function()require("ui.themes.widgets.sheet"):new{title="底栏样式",items={
                        {text="胶囊高亮",callback=function()Engine.set("navbar_style","pill",desktop)end},
                        {text="短线指示",callback=function()Engine.set("navbar_style","line",desktop)end},
                    }}:show()end}end,
                toggle("loading_screen","全屏开书遮罩","显示月读书名、作者与本地封面，按真实进度局部刷新"),
            }},{title="版本与更新",rows={
                function(width)return row{width=width,title="自动检查更新",toggle=Update.autoEnabled(),
                    subtitle="已联网时每天最多一次",callback=function()
                        Update.setAuto(not Update.autoEnabled());Engine.refresh(desktop)end}end,
                function(width)return row{width=width,title="自动下载安装包",toggle=Update.autoDownload(),
                    subtitle="下载校验后，确认才安装",callback=function()
                        Update.setAutoDownload(not Update.autoDownload());Engine.refresh(desktop)end}end,
                function(width)return row{width=width,title="Moon Color "..Engine.VERSION,
                    subtitle="检查更新 / 安装已下载版本",status=Update.status(),callback=Update.manualCheck}end,
            }}}
        end}}}
end
return {api=1,id=Engine.ID,name="Moon Color",version=Engine.VERSION,
    provides={source=false,features={setting={entries=entries}}}}
