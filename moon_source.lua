local Engine=require("mooncolor_engine")
local function entries(desktop)
    Engine.install()
    local function row(opts)return require("ui.themes.widgets.row").widget(opts)end
    local function toggle(key,title,subtitle)
        return function(width)return row{width=width,title=title,subtitle=subtitle,
            toggle=Engine.config()[key],callback=function()Engine.set(key,not Engine.config()[key],desktop)end}end
    end
    local function selectRow(key,title,choices)
        return function(width)
            local status="";for _,item in ipairs(choices)do if item.id==Engine.config()[key]then status=item.text end end
            return row{width=width,title=title,status=status,callback=function()
                local items={}
                for _,item in ipairs(choices)do local id=item.id
                    items[#items+1]={text=item.text,callback=function()Engine.set(key,id,desktop)end}
                end
                require("ui.themes.widgets.sheet"):new{title=title,items=items}:show()
            end}
        end
    end
    local styles={{id="pill",text="胶囊高亮"},{id="line",text="短线指示"}}
    return {{group="desktop",order=310,id="appearance",icon="navigation",
        title="moonflow",subtitle="底栏 · 开书遮罩 · "..Engine.VERSION,
        page={title="moonflow",sections=function()
            local Update=require("mooncolor_update")
            return {{title="桌面底栏",rows={
                toggle("enabled","启用界面增强",Engine.status()),
                toggle("navbar_labels","显示文字","关闭后仅显示图标，长按查看名称"),
                selectRow("navbar_style","底栏样式",styles),
                toggle("navbar_compact","紧凑布局","缩小底栏高度与图标，增加内容空间"),
            }},{title="阅读侧栏底栏",rows={
                toggle("sidebar_labels","显示文字","可与桌面底栏分别设置"),
                selectRow("sidebar_style","侧栏底栏样式",styles),
                toggle("sidebar_compact","紧凑布局","仅影响阅读侧栏，不改变桌面尺寸"),
            }},{title="开书遮罩",rows={
                toggle("loading_screen","全屏开书遮罩","真实封面优先；无封面显示月读一言"),
                selectRow("loading_style","遮罩样式",{{id="book",text="封面优先 / 一言回退"},{id="simple",text="简洁进度（不加载封面）"}}),
            }},{title="版本与更新",rows={
                function(width)return row{width=width,title="自动检查更新",toggle=Update.autoEnabled(),
                    subtitle="已联网时每天最多一次",callback=function()
                        Update.setAuto(not Update.autoEnabled());Engine.refresh(desktop)end}end,
                function(width)return row{width=width,title="自动下载安装包",toggle=Update.autoDownload(),
                    subtitle="下载校验后，确认才安装",callback=function()
                        Update.setAutoDownload(not Update.autoDownload());Engine.refresh(desktop)end}end,
                function(width)return row{width=width,title="moonflow "..Engine.VERSION,
                    subtitle="检查更新 / 安装已下载版本",status=Update.status(),callback=Update.manualCheck}end,
            }}}
        end}}}
end
return {api=1,id=Engine.ID,version=Engine.VERSION,
    provides={source=false,features={setting={entries=entries}}}}
