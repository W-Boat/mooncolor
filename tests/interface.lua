check("moonflow-display-name-and-compatible-identity",function()
    local meta=dofile(PLUGIN_ROOT.."/_meta.lua")
    assert(meta.fullname=="moonflow"and meta.version=="3.1.0")
    assert(Engine.ID=="ext.mooncolor")
end)
check("sidebar-layout-is-independent-and-context-restores-after-errors",function()
    Engine.set("navbar_labels",true);Engine.set("navbar_compact",false)
    Engine.set("sidebar_labels",false);Engine.set("sidebar_compact",true)
    local sidebar={render=function(self)
        self.height=Tabbar.height()
        self.widget=Tabbar.widget{width=510,tabs={{id="info",text="信息",icon="info"}},active="info"}
        if self.raise then error("render failure")end
    end}
    local old=package.loaded["features.sidebar"];package.loaded["features.sidebar"]=sidebar
    Engine.attachSidebar();Engine.attachSidebar()
    sidebar:render();assert(sidebar.height==40 and Tabbar.height()==64)
    assert(#Kit.find(sidebar.widget,function(w)return w.text=="信息"end)==0)
    sidebar.raise=true;assert(not pcall(sidebar.render,sidebar))
    assert(Tabbar.height()==64,"sidebar context leaked on failure")
    Engine.set("navbar_compact",true);assert(Tabbar.height()==56)
    Engine.set("navbar_compact",false)
    package.loaded["features.sidebar"]=old
end)
check("simple-loading-never-stats-or-decodes-a-cover",function()
    Loading.finish();Engine.set("loading_style","simple")
    local lfs=require("libs/libkoreader-lfs");local attr=lfs.attributes
    lfs.attributes=function()error("simple loading must not look up cover files")end
    metadata_rows["simple.epub"]={book={title="简洁书名",authors="作者",cover="/cover.png"}}
    local before=decoded;local reader={};Reader.showReaderCoroutine(reader,"simple.epub")
    assert(reader.notice.book.title=="简洁书名"and decoded==before)
    reader.notice:paintTo(Kit.canvas(),0,0)
    local direct=Loading.make("simple.epub");assert(direct.book.title=="简洁书名")
    lfs.attributes=attr;Loading.finish();Engine.set("loading_style","book")
end)
check("real-cover-takes-priority-without-reading-hitokoto",function()
    Loading.finish()
    local h=package.loaded["online.hitokoto"];local current=h.current
    h.current=function()error("quote must not be read when there is a real cover")end
    local before=decoded
    local card=Loading.make("cover.epub",{title="封面书名",authors="作者",cover="/cover.png"})
    assert(card.has_cover and not card.quote and decoded==before+1)
    h.current=current
end)
check("missing-or-broken-cover-displays-Moon-quote-and-keeps-book-metadata",function()
    local before=decoded
    local card=Loading.make("without-cover.epub",{title="真实月读书名",authors="真实作者"})
    assert(not card.has_cover and card.quote.text=="纸上有光，书中有路。"and decoded==before)
    assert(#Kit.find(card,function(w)return w.text=="纸上有光，书中有路。"end)==1)
    assert(#Kit.find(card,function(w)return w.text=="真实月读书名"end)==1)
    local Images=require("ui/widget/imagewidget");local new=Images.new;local released=0
    Images.new=function()
        return {getSize=function()error("bad image")end,free=function()released=released+1 end}
    end
    local broken=Loading.make("broken.epub",{title="坏封面",authors="作者",cover="/broken.png"})
    assert(not broken.has_cover and broken.quote and released==1)
    Images.new=new
end)
check("one-quote-per-opening-without-rereading-during-progress",function()
    Loading.finish();clock_time=400
    local h=package.loaded["online.hitokoto"];local current=h.current;local reads=0
    h.current=function()reads=reads+1;return {text="只读一次的一言",source="缓存"}end
    local reader={};Reader.showReaderCoroutine(reader,"quote.epub")
    local card=reader.notice;card:paintTo(Kit.canvas(),0,0)
    local rolling={ui={document={file="quote.epub"}}}
    for i=1,10 do clock_time=400+i;Rolling.showEngineProgress(rolling,i/10)end
    assert(reads==1 and card==rolling._moon_loading and card.quote.text=="只读一次的一言")
    Loading.finish();h.current=current
end)
check("actual-Moon-hitokoto-interface-uses-fresh-cache-or-offline-fallback-with-no-requests",function()
    local names={"online.hitokoto","online.base","json","http.request","utils.image","utils.text"}
    local old={};for _,name in ipairs(names)do old[name]=package.loaded[name]end
    package.loaded["online.hitokoto"],package.loaded["online.base"]=nil,nil
    package.loaded.json={decode=function()error("unexpected disk decode")end}
    package.loaded["http.request"]={get=function()error("unexpected network request")end}
    package.loaded["utils.image"]={}
    package.loaded["utils.text"]={trim=function(s)return s:match("^%s*(.-)%s*$")end}
    local h=require("online.hitokoto")
    h.data={text="官方缓存内容",source="官方来源"};h._expire=os.time()+60;h._cache_key=h:url()
    local quote=Loading.quote();assert(quote.text=="官方缓存内容"and quote.source=="官方来源")
    h._expire=0
    local fallback=Loading.quote()
    assert(fallback.text==h.fallback().text and fallback.text~="官方缓存内容")
    for _,name in ipairs(names)do package.loaded[name]=old[name]end
end)
check("quote-interface-failure-isolated-and-toolbox-removed",function()
    local old=package.loaded["online.hitokoto"]
    package.loaded["online.hitokoto"]={current=function()error("cache error")end,
        fallback=function()return {text="官方离线句",source="作者"}end}
    assert(Loading.quote().text=="官方离线句")
    package.loaded["online.hitokoto"]={current=function()return {text=" "}end,
        fallback=function()error("fallback error")end}
    local card=Loading.make("error.epub",{title="仍可打开",authors="作者"})
    assert(not card.has_cover and not card.quote and card.bar)
    package.loaded["online.hitokoto"]=old
    local Main=dofile(PLUGIN_ROOT.."/main.lua")
    assert(not Main.onMoonflowTools and not Main.onDispatcherRegisterActions)
    local items={};Main:addToMainMenu(items)
    assert(items.mooncolor.text=="moonflow"and not items.moonflow_tools)
    assert(not Engine.config().navbar_hold_tools)
end)
