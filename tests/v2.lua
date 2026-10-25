check("v2-all-home-and-panel-adapters-loaded",function()
    for _,key in ipairs{"home_heatmap","home_tiles","rings","fast_mask","fast_modal","fast_native_panel"}do assert(Engine.coverage[key],key)end
end)
check("warm-drawing-does-not-read-source-settings",function()
    local settings=require("utils.settings")
    local get=settings.getSource
    local calls=0
    settings.getSource=function(...)calls=calls+1;return get(...)end
    Engine.config()
    local before=calls
    local Progress=require("ui.themes.widgets.progress")
    local Heatmap=require("ui.widgets.heatmap")
    for i=1,100 do
        Progress:new{width=200,percent=i}:paintTo(Kit.canvas(),0,0)
        Heatmap:new{width=80,cols={{{level=1},{level=2},{level=3},{level=4}}}}:paintTo(Kit.canvas(),0,0)
    end
    settings.getSource=get
    assert(calls==before,"settings accessed in hot drawing path: "..calls-before)
end)
check("home-heatmap-real-createWidget-colors-active-cells",function()
    local M=require("desktop.pages.home.heatmap")
    local obj=M:new{opts={width=300,height=140},ctx={source={id="local"}}}
    local widget=obj:createWidget()
    local cells=Kit.find(widget,function(w)return w.keep_bg and w.style and w.style.bg and w.style.bg>0xFFFFFF end)
    assert(#cells>0)
    local bb=Kit.canvas();widget:paintTo(bb,0,0)
    local count=0;for _,op in ipairs(bb.ops)do if op.rgb_api and rgb(op.c)then count=count+1 end end
    assert(count>=#cells)
end)
check("home-tiles-real-dots-and-bars-colors",function()
    local M=require("desktop.pages.home.tiles")
    local widget=M:new{opts={width=550,height=320},ctx={source={id="local"}}}:createWidget()
    local dots=Kit.find(widget,function(w)return w.style and w.style.radius==999 and (w.style.bg or 0)>0xFFFFFF end)
    local bars=Kit.find(widget,function(w)return w.style and not w.style.radius and (w.style.bg or 0)>0xFFFFFF end)
    assert(#dots>0 and #bars>0)
    widget:paintTo(Kit.canvas(),0,0)
end)
check("mixed-ring-three-colors-and-bitmap-cache-invalidation",function()
    Engine.set("palette","aurora")
    local Ring=require("ui.widgets.ring")
    local saved_new,saved_type=BB.new,BB.TYPE_BBRGB32
    local images,frees,blits,colors=0,0,0,{}
    BB.TYPE_BBRGB32=99
    BB.new=function(w,h)
        images=images+1
        return {paintRectRGB32=function()end,
            setPixel=function(_,x,y,c)
                assert(x>=0 and x<w and y>=0 and y<h,"pixel outside cached bitmap")
                if rgb(c)then colors[c.r..","..c.g..","..c.b]=true end
            end,free=function()frees=frees+1 end}
    end
    local bb=Kit.canvas()
    bb.alphablitFrom=function()blits=blits+1 end
    local widget=Ring:new{size=96,rings={{fraction=1},{fraction=1},{fraction=1}}}
    widget:paintTo(bb,10,20);widget:paintTo(bb,20,30)
    assert(images==1 and blits==2)
    for _,role in ipairs{"stat1","stat2","stat3"}do
        local c=Engine.accent(role);assert(colors[c.r..","..c.g..","..c.b],role)
    end
    widget.rings[2].fraction=.5;widget:paintTo(bb,0,0);assert(images==2 and frees==(Engine.VERSION=="2.1.0"and 0 or 1))
    Engine.set("palette","garden");widget:paintTo(bb,0,0);assert(images==3 and frees==2)
    widget:free()
    if Engine.VERSION=="2.1.0"then
        local other=Ring:new{size=96,rings={{fraction=1},{fraction=.5},{fraction=1}}}
        other:paintTo(bb,0,0);assert(images==3)
        other:free()
        Engine.reload()
        -- Flush shared entries while allocation is still instrumented.
        Ring:new{size=20,rings={{fraction=.5}}}:paintTo(Kit.canvas(),0,0)
    end
    assert(frees==3)
    BB.new,BB.TYPE_BBRGB32=saved_new,saved_type
end)
check("fast-mask-skips-precisely-530880-pixel-writes-on-Libra",function()
    local Mask=require("ui.themes.widgets.mask")
    local widget=Mask:new{dimen={w=1264,h=1680}}
    Kit.display.mesh_mask=true
    Engine.set("fast_panels",true)
    local bb=Kit.canvas();widget:paintTo(bb,0,0);assert(bb.pixels==0)
    Engine.set("fast_panels",false)
    widget:paintTo(bb,0,0);assert(bb.pixels==1264*1680/4)
    assert(Kit.display.mesh_mask==true)
    Engine.set("fast_panels",true)
    Engine.set("enabled",false)
    local small=Kit.canvas();Mask:new{dimen={w=40,h=40}}:paintTo(small,0,0);assert(small.pixels==400)
    Engine.set("enabled",true)
end)
check("real-modal-show-no-mask-full-refresh-in-fast-mode",function()
    local UI=require("ui/uimanager")
    local show=UI.show
    local mode
    UI.show=function(_,_,m)mode=m end
    local Modal=require("ui.themes.widgets.modal")
    local modal=Modal:new{}
    modal:show();assert(mode=="ui")
    Engine.set("fast_panels",false)
    modal:show();assert(mode=="full")
    Engine.set("fast_panels",true)
    UI.show=show
end)
check("reader-native-menu-update-does-not-force-full-with-fast-panels",function()
    local Native=require("features.panel.native")
    local patch
    for i=1,100 do local name,value=debug.getupvalue(Native.onCreate,i);if not name then break end
        if name=="patchTouchMenu"then patch=value end end
    assert(patch)
    local old=package.loaded["ui/widget/touchmenu"]
    local TouchMenu={updateItems=function()end,paintTo=function()end,onCloseWidget=function()end}
    package.loaded["ui/widget/touchmenu"]=TouchMenu
    patch()
    local menu={is_fresh=true,dimen={h=200,y=0},screen_size={w=1264,h=1680}}
    local before=#Kit.dirty
    TouchMenu.updateItems(menu)
    assert(#Kit.dirty==before)
    Engine.set("fast_panels",false)
    TouchMenu.updateItems(menu);assert(Kit.dirty[#Kit.dirty].mode=="full")
    Engine.set("fast_panels",true)
    package.loaded["ui/widget/touchmenu"]=old
end)
check("custom-colors-validate-normalize-and-choose-readable-labels",function()
    assert(Engine.setRole("primary"," #ff0 "))
    assert(Engine.config().custom_colors.primary=="#FFFF00" and Engine.foreground("primary")==0)
    local old=Engine.config().custom_colors.primary
    assert(not Engine.setRole("primary","oops"));assert(not Engine.setRole("unknown","#abc"))
    assert(Engine.config().custom_colors.primary==old)
    for i,role in ipairs(Engine.roles)do
        assert(Engine.setRole(role.id,string.format("#%02x%02x%02x",i*10,i*15,i*20)))
        local c=Engine.accent(role.id);assert(c.r==i*10 and c.g==i*15 and c.b==i*20)
    end
end)
check("themes-save-load-delete-persist-without-changing-performance-flags",function()
    Engine.set("navbar_labels",false);Engine.set("navbar_style","line")
    local color=Engine.config().custom_colors.stat3
    local id=assert(Engine.saveTheme("我的混色"))
    assert(not Engine.saveTheme("我的混色"));assert(not Engine.saveTheme(""))
    Engine.set("palette","ocean");Engine.set("navbar_labels",true);Engine.set("navbar_style","pill")
    Engine.set("fast_panels",false);Engine.set("quality_refresh",true)
    Engine.reload()
    assert(Engine.loadTheme(id))
    assert(Engine.config().custom_colors.stat3==color and not Engine.config().navbar_labels and Engine.config().navbar_style=="line")
    assert(not Engine.config().fast_panels and Engine.config().quality_refresh)
    assert(Engine.themeName()=="我的混色")
    assert(Engine.deleteTheme(id));assert(#Engine.listThemes()==0)
    assert(Engine.config().custom_colors.stat3==color)
    for i=1,12 do assert(Engine.saveTheme("主题"..i))end
    assert(not Engine.saveTheme("第十三套"))
    for _,theme in ipairs(Engine.listThemes())do assert(Engine.deleteTheme(theme.id))end
    Engine.set("fast_panels",true);Engine.set("quality_refresh",false)
end)
check("editor-uses-real-input-string-callback-contract",function()
    local Editor=require("mooncolor_editor")
    local originals={}
    for _,key in ipairs{"list","input","toast"}do
        local path="ui.themes.widgets."..key
        originals[path]=package.loaded[path]
        package.loaded[path]={new=function(_,opts)return setmetatable(opts,{__index={show=function(self)editor_shown=self end}})end}
    end
    Editor.colors(Engine)
    assert(#editor_shown.items==9)
    if Engine.VERSION=="2.1.0"then
        local Swatch=require("mooncolor_swatch")
        local make=Swatch.new
        Swatch.new=function(_,_,_,_,precise)return {show=function()precise()end}end
        editor_shown.items[1].callback()
        Swatch.new=make
    else editor_shown.items[1].callback()end
    editor_shown.callback("#123456")
    assert(Engine.config().custom_colors.primary=="#123456")
    Editor.save(Engine);editor_shown.callback("通过编辑器保存");assert(#Engine.listThemes()==1)
    for path,mod in pairs(originals)do package.loaded[path]=mod end
    -- nil original modules are not enumerated by pairs.
    for _,key in ipairs{"list","input","toast"}do package.loaded["ui.themes.widgets."..key]=originals["ui.themes.widgets."..key]end
end)
