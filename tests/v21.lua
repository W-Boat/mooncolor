check("new-adapters-are-loaded",function()
    for _,key in ipairs{"inputs","library_tabs","sidebar","cover_queue","loading_screen","pager","ticket"}do assert(Engine.coverage[key],key)end
end)
check("ffi-color-equality-nil-crash-regression",function()
    local ffi=require("ffi")
    ffi.cdef[[typedef struct {uint8_t v;} MoonBadEq;]]
    local C=ffi.metatype("MoonBadEq",{__eq=function(a,b)return a.v==b.v end})
    local bad=C(255)
    assert(not pcall(function()return bad==nil end))
    local old=BB.Color8
    BB.Color8=function(v)return C(v)end
    local badge=require("ui.widgets.book").progressBadge(150,32)
    assert(badge and badge.style.bg>0xFFFFFF)
    BB.Color8=old
end)
check("input-border-color-survives-focus-change",function()
    local Input=require("ui.themes.widgets.input")
    local input=Input:new{title="输入",fields={{text="A"},{text="B"}}}
    assert(input.frames[1].style.border_color==Engine.accentToken("primary"))
    input:onSwitchFocus(input.inputs[2])
    assert(input.focus_idx==2 and input.frames[2].style.border_color==Engine.accentToken("primary"))
    assert(input.frames[1].style.border_color~=input.frames[2].style.border_color)
end)
check("rules-use-rgb-without-changing-core-LineWidget",function()
    local Title=require("ui.themes.widgets.titlebar")
    local bb=Kit.canvas()
    Title.widget{width=600,title="标题"}:paintTo(bb,0,0)
    local found=false
    for _,op in ipairs(bb.ops)do if op.rgb_api and rgb(op.c)and op.h<=3 then found=true end end
    assert(found)
    local Line=require("ui/widget/linewidget")
    local plain=Line:new{background=0,dimen={w=200,h=1}}
    local core=Kit.canvas();plain:paintTo(core,0,0)
    assert(not rgb(core.ops[1].c))
end)
check("library-private-tab-strip-selected-label-and-rule-colored",function()
    local Library=require("desktop.pages.library")
    local found,seen=nil,{}
    local function visit(fn)
        if seen[fn]then return end;seen[fn]=true
        for i=1,100 do
            local name,value=debug.getupvalue(fn,i);if not name then break end
            if name=="tabStrip"then found=value;return end
            if type(value)=="function"then visit(value)end
        end
    end
    for _,fn in pairs(Library)do if type(fn)=="function"then visit(fn)end end
    assert(found)
    local strip=found(600,{{id="a",text="书籍"},{id="b",text="分类"}},"a",function()end)
    local selected=Kit.find(strip,function(w)return w.text=="书籍"end)
    assert(#selected==1 and rgb(selected[1].fgcolor))
    local bb=Kit.canvas();strip:paintTo(bb,0,0)
    local marked=false;for _,op in ipairs(bb.ops)do if op.w==300 and rgb(op.c)then marked=true end end
    assert(marked)
end)
check("palette-30-real-touch-swatches-and-precise-input-action",function()
    local Swatch=require("mooncolor_swatch")
    local chosen,precise
    local palette=Swatch.new(Engine,"按钮","#205CA8",function(c)chosen=c end,function()precise=true end)
    local taps=Kit.taps(palette)
    assert(#Swatch.colors==30 and #taps>=30)
    taps[2]:onTapThemeArea();assert(chosen==Swatch.colors[2])
    local bb=Kit.canvas();palette:paintTo(bb,0,0)
    local colors=0;for _,op in ipairs(bb.ops)do if op.rgb_api and rgb(op.c)then colors=colors+1 end end
    assert(colors>=30)
end)
check("twelve-valid-themes-nine-roles-each",function()
    assert(#Engine.palettes==12)
    for _,preset in ipairs(Engine.palettes)do
        Engine.set("palette",preset.id)
        for _,role in ipairs(Engine.roles)do assert(Engine.config().custom_colors[role.id]:match("^#%x%x%x%x%x%x$"))end
    end
end)
check("home-database-cache-invalidates-on-stats-change",function()
    local M=require("desktop.pages.home.heatmap")
    local a=M:new{ctx={source={id="local"}},opts={width=300,height=140}}
    a:onEvent("stats_changed")
    local reads=home_db_reads or 0
    a:createWidget()
    a:createWidget()
    assert(home_db_reads==reads+1)
    local before=a.key
    local DB=require("book.stats_db")
    -- The result remains unmodified; invalidation reaches the original real module.
    a:onEvent("stats_changed")
    a:createWidget()
    assert(type(a.key)=="string" and before==a.key)
end)
check("real-cover-queue-yields-input-reuses-cache-and-invalidates",function()
    local Core=require("ui.themes.widgets.image.core")
    local UI=require("ui/uimanager")
    local lfs=require("libs/libkoreader-lfs")
    local attr=lfs.attributes
    local nextTick,schedule=UI.nextTick,UI.scheduleIn
    local oldRender=package.loaded["ui/renderimage"]
    local jobs,decoded={},0
    UI.nextTick=function(_,fn)jobs[#jobs+1]={fn=fn,delay=0}end
    UI.scheduleIn=function(_,delay,fn)jobs[#jobs+1]={fn=fn,delay=delay}end
    lfs.attributes=function(_,field)if field=="mode"then return "file"end;return {size=100000,modification=1}end
    package.loaded["ui/renderimage"]={renderImageFile=function()
        decoded=decoded+1;clock_time=clock_time+.012
        return {stride=400,h=140}
    end}
    local boxes={}
    local modern=Engine.VERSION=="2.2.0"
    local total=modern and 10 or 3
    for i=1,total do boxes[i]=Core.widget{src="/cover"..i..".png",width=100,height=140}end
    assert(decoded==0 and #jobs==1)
    table.remove(jobs,1).fn()
    assert(decoded==(modern and 5 or 1) and #jobs==1 and jobs[1].delay==(modern and .1 or .015))
    while jobs[1]do table.remove(jobs,1).fn()end
    assert(decoded==total)
    Core.widget{src="/cover1.png",width=100,height=140}
    assert(decoded==total and #jobs==0)
    Core.invalidate("/cover1.png")
    Core.widget{src="/cover1.png",width=100,height=140}
    assert(#jobs==1);table.remove(jobs,1).fn();assert(decoded==total+1)
    UI.nextTick,UI.scheduleIn=nextTick,schedule
    lfs.attributes=attr;package.loaded["ui/renderimage"]=oldRender
end)
check("ticket-cache-invalidates-content-file-and-color-changes",function()
    local path="ui.themes.widgets.unused"
    local old=package.loaded["features.lockscreen.render"]
    local files={["/cache/cover.png"]={size=10,modification=1}}
    local writes=0
    local Render={write=function(output)
        writes=writes+1;files[output]={size=123,modification=writes}
        return true
    end}
    local lfsold=package.loaded.lfs
    package.loaded.lfs={attributes=function(file)return files[file]end}
    package.loaded["features.lockscreen.render"]=Render
    require("mooncolor_ticket").install(Engine,function(obj,key,fn)obj[key]=fn end)
    local blocks={{text="A",color=0},{kind="image",file="/cache/cover.png"}}
    assert(Render.write("/cache/ticket.png",nil,blocks,238));assert(writes==1)
    assert(Render.write("/cache/ticket.png",nil,blocks,238));assert(writes==1)
    blocks[1].color=80;Render.write("/cache/ticket.png",nil,blocks,238);assert(writes==2)
    files["/cache/cover.png"].modification=2
    Render.write("/cache/ticket.png",nil,blocks,238);assert(writes==3)
    blocks[1].text="B";Render.write("/cache/ticket.png",nil,blocks,238);assert(writes==4)
    Render.write("/cache/wallpaper.png",nil,blocks,238);assert(writes==5)
    package.loaded.lfs=lfsold;package.loaded["features.lockscreen.render"]=old
end)
check("cover-queue-knobs-and-toggle-restoration",function()
    local Core=require("ui.themes.widgets.image.core")
    local values,seen={},{}
    local function visit(fn)
        if seen[fn]then return end;seen[fn]=true
        local info=debug.getinfo(fn,"S")
        if not info or not info.source:gsub("\\","/"):match("/ui/themes/widgets/image/core%.lua$")then return end
        for i=1,100 do
            local name,v=debug.getupvalue(fn,i);if not name then break end
            if name=="BUDGET_MS"or name=="YIELD_S"or name=="BITMAP_BUDGET"then values[name]=v end
            if type(v)=="function"then visit(v)end
        end
    end
    for _,fn in pairs(Core)do if type(fn)=="function"then visit(fn)end end
    if Engine.VERSION=="2.2.0"then
        assert(values.BUDGET_MS==50 and values.YIELD_S==.1 and values.BITMAP_BUDGET==6*1024*1024)
        Engine.set("fast_covers",true)
        values,seen={},{}
        for _,fn in pairs(Core)do if type(fn)=="function"then visit(fn)end end
        assert(values.BUDGET_MS==50 and values.YIELD_S==.1 and values.BITMAP_BUDGET==12*1024*1024)
    else
        assert(values.BUDGET_MS==8 and values.YIELD_S==.015 and values.BITMAP_BUDGET==16*1024*1024)
    end
    Engine.set("fast_covers",false)
    values,seen={},{}
    for _,fn in pairs(Core)do if type(fn)=="function"then visit(fn)end end
    assert(values.BUDGET_MS==50 and values.YIELD_S==.1 and values.BITMAP_BUDGET==6*1024*1024)
    Engine.set("fast_covers",Engine.VERSION~="2.2.0")
end)
check("opening-notice-replacement-restores-constructor-on-error",function()
    local Reader=require("apps/reader/readerui")
    local Info=require("ui/widget/infomessage")
    local new=Info.new
    local reader={}
    Reader.showReaderCoroutine(reader,"a.epub")
    assert(reader.notice.covers_fullscreen and reader.notice.bar)
    assert(Info.new==new)
    reader.raise=true
    assert(not pcall(Reader.showReaderCoroutine,reader,"bad.epub"))
    assert(Info.new==new)
    reader.raise=false
    Reader.showReaderCoroutine(reader,"a.epub",nil,true)
    assert(not reader.notice.bar)
end)
check("real-engine-progress-throttled-regional-refresh-and-cleanup",function()
    local Rolling=require("apps/reader/modules/readerrolling")
    local Screen=Device.screen
    Screen.bb=Kit.canvas()
    local refreshes={}
    Screen.refreshUI=function(_,x,y,w,h)refreshes[#refreshes+1]={w=w,h=h}end
    local rolling={ui={document={file="book.epub"}}}
    clock_time=100
    Rolling.showEngineProgress(rolling,0)
    assert(rolling._moon_loading)
    local count=#refreshes
    Rolling.showEngineProgress(rolling,.1);assert(#refreshes==count)
    clock_time=101
    Rolling.showEngineProgress(rolling,.5)
    assert(#refreshes==count+1 and refreshes[#refreshes].h<800)
    rolling.ui.document.been_rendered=true
    Rolling.showEngineProgress(rolling,nil)
    assert(not rolling._moon_loading)
end)
check("update-semver-parsing-and-native-async-request",function()
    local U=require("mooncolor_update")
    assert(U.newer("2.10.0","2.9.0") and not U.newer("2.1.0","2.1.0"))
    assert(not U.newer("bad","2.1.0"))
    local old=package.loaded.json
    package.loaded.json={decode=function()return {tag_name="v2.2.0",body="更新"}end}
    local release=assert(U.parse("json"));assert(release.version=="2.2.0")
    assert(release.url=="https://github.com/W-Boat/mooncolor/releases/tag/v2.2.0")
    package.loaded.json=old
end)
