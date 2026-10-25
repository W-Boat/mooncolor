assert(Engine.coverage.quickpanel_reuse and Engine.coverage.quickpanel_cleanup)
assert(Engine.coverage.quickpanel_header)
local Native=require("features.panel.native")
require("utils.paths").coverPath=function()end
local Device=require("device")
Device.isTouchDevice=function()return true end
Device.hasBattery=function()return false end
package.loaded["datetime"]={secondsToHour=function()return "12:34" end}
package.loaded["ui/bidi"].wrap=function(t)return t end
G_reader_settings.isTrue=function()return false end
local actions={{id="toc",title="目录",icon="menu_book",active=false}}
local sliders={}
package.loaded["features.panel.reader"]={actions=function()return actions end}
package.loaded["features.panel.desktop"]={menuActions=function()return actions end,sliders=function()return sliders end}
local Header=require("features.panel.widget.header")
local Action=require("features.panel.widget.button")
local headers,buttons=0,0
local init=Header.init
Header.init=function(self,...)headers=headers+1;return init(self,...)end
local action_init=Action.init
Action.init=function(self,...)buttons=buttons+1;return action_init(self,...)end
-- Use native switchMenuTab verbatim and real Moon renderPanelContent/buildPanel.
-- The host's native item branch counts calls; its group mirrors native clear/free.
local function freeTree(self)
    for _,child in ipairs(self)do if child.free then child:free()end end
end
local group=require("ui/widget/verticalgroup")
local native_updates=0
local Touch={onCloseWidget=function()end,free=freeTree,
    updateItems=function(self)
        native_updates=native_updates+1;self.item_group:clear()
    end,paintTo=function()end}
Touch.switchMenuTab=assert(loadstring("return function(TouchMenu) "..native_switch_source..
    " return TouchMenu.switchMenuTab end"))()(Touch)
package.loaded["ui/widget/touchmenu"]=Touch
local patch
for i=1,100 do local name,value=debug.getupvalue(Native.onCreate,i)
    if not name then break end;if name=="patchTouchMenu"then patch=value end end
assert(patch);patch()
local function menu()
    local m=setmetatable({width=600,item_width=600,screen_size={w=600,h=800},
        dimen=require("ui/geometry"):new{x=0,y=0,w=600,h=100},show_parent={},
        tab_item_table={{_book_reader_panel=true,_book_ui=quick_snapshot.ui},{},
            {_book_quick_panel=true}},
        footer_top_margin=require("ui/widget/verticalspan"):new{width=1},
        footer=require("ui/widget/verticalspan"):new{width=1},
        time_info={setText=function()end},page_info_text={setText=function()end},
        page_info_left_chev={showHide=function()end},page_info_right_chev={showHide=function()end},
        padding=0,bordersize=0}, {__index=Touch})
    m.bar=require("ui/widget/verticalspan"):new{width=1}
    m.item_group=group:new{}
    m.item_group.clear=function(self)
        freeTree(self);for i=#self,1,-1 do self[i]=nil end;self:resetLayout()
    end
    m[1]=m.item_group
    return m
end
local m=menu()
local initial
check("quickpanel-100-native-round-trips-build-one-body",function()
    m:switchMenuTab(1);initial=m.item_group[3]
    assert(headers==1 and buttons==1)
    -- Cache free is inert during detach; close release is checked separately.
    for i=1,100 do m:switchMenuTab(2);m:switchMenuTab(1);assert(m.item_group[3]==initial)end
    assert(headers==1 and buttons==1 and native_updates==100)
    assert(toc_reads==0,"informational menu caused TOC parsing")
end)
check("hidden-desktop-does-not-request-screen-refresh",function()
    local before=#Kit.dirty;local builds=0
    Engine.refresh({active=false,updateView=function()builds=builds+1 end})
    assert(builds==1 and #Kit.dirty==before)
end)
check("selecting-current-color-does-not-save-or-rebuild",function()
    local before=saves;local rev=Engine.revision
    assert(Engine.setRole("progress",Engine.config().custom_colors.progress,
        {updateView=function()error("unnecessary rebuild")end}))
    assert(saves==before and Engine.revision==rev)
end)
check("quickpanel-updates-live-actions-page-theme-and-sliders",function()
    actions[1].active=true;m:switchMenuTab(1);assert(headers==2 and m.item_group[3]~=initial)
    quick_snapshot.page=43;m:switchMenuTab(1);assert(headers==3)
    Engine.set("palette","garden");m:switchMenuTab(1);assert(headers==4)
    m:switchMenuTab(3);local desktop=m.item_group[3]
    m:switchMenuTab(1);m:switchMenuTab(3);assert(m.item_group[3]==desktop)
    sliders[1]={kind="brightness",title="亮度",value=35}
    m:switchMenuTab(3);assert(m.item_group[3]~=desktop)
end)
check("quickpanel-edit-and-disable-use-original-builder",function()
    m:switchMenuTab(1);local before=headers
    -- Editing's original body requires addable() only when there are actions;
    -- provide the real service API for that path.
    package.loaded["features.panel.reader"].options=function()return {} end
    m.item_table._book_panel_editing=true;m:switchMenuTab(1);m:switchMenuTab(1)
    assert(headers==before+2)
    m.item_table._book_panel_editing=false
    Engine.set("fast_panels",false);m:switchMenuTab(1);m:switchMenuTab(1)
    assert(headers==before+4);Engine.set("fast_panels",true)
end)
check("quickpanel-no-toc-parse-empty-or-loaded-native-directory",function()
    local action=require("features.panel.actions.reader.toc")
    local ui={toc={onShowToc=function()end}}
    assert(action.available({ui=ui}))
    local before=toc_reads
    quick_snapshot.ui.toc.toc={};m:switchMenuTab(1)
    assert(toc_reads==before,"TOC reads "..toc_reads.." vs "..before)
    local title=Kit.find(m.item_group[3],function(w)return w.text=="百年孤独"end)
    assert(#title>=1,"Moon title missing")
end)
check("quickpanel-close-frees-attached-and-detached-bodies-once",function()
    local Box=require("ui.themes.widgets.box")
    local free=Box.free;local freed={}
    Box.free=function(self)
        freed[self]=(freed[self]or 0)+1
        if free then return free(self)end
    end
    local n=menu();n:switchMenuTab(1);local reader=n.item_group[3]
    n:switchMenuTab(3);local desktop=n.item_group[3]
    n:switchMenuTab(2)
    assert(not freed[reader] and not freed[desktop])
    n:onCloseWidget();n:free();n:onCloseWidget()
    assert(freed[reader]==1 and freed[desktop]==1)
    local p=menu();p:switchMenuTab(1);local orphan=p.item_group[3]
    p:free();assert(freed[orphan]==1)
    Box.free=free
end)
check("surface-skips-corner-pixel-copies-for-inscribed-child",function()
    local Box=require("ui.themes.widgets.box")
    local leaf={getSize=function()return {w=20,h=20}end,paintTo=function()end}
    local b=Box:new{style={bg=255,radius=30,border=0},width=100,height=60,leaf}
    local function canvas()
        local bb=Kit.canvas();bb.reads=0
        bb.getWidth=function()return 600 end;bb.getHeight=function()return 800 end
        bb.getPixel=function(self)self.reads=self.reads+1;return {getColorRGB32=function()return 0 end}end
        return bb
    end
    Engine.set("fast_panels",false);local old=canvas();b:paintTo(old,0,0);assert(old.reads>0)
    Engine.set("fast_panels",true);local fast=canvas();b:paintTo(fast,0,0)
    assert(fast.reads==0 and fast.pixels==0)
    assert(#fast.ops==#old.ops)
    -- A cover filling the box still needs the original clipping path.
    leaf.getSize=function()return {w=100,h=60}end
    local full=canvas();b:paintTo(full,0,0);assert(full.reads==old.reads)
    -- Translucent background must preserve underlying corner pixels too.
    leaf.getSize=function()return {w=20,h=20}end;b.bg_alpha=50
    local alpha=canvas();alpha.lightenRect=function()end;b:paintTo(alpha,0,0)
    assert(alpha.reads>0)
end)
check("heatmap-palette-reused-until-theme-revision-changes",function()
    local H=require("ui.widgets.heatmap")
    local tint=Engine.tint;local count=0
    Engine.tint=function(...)count=count+1;return tint(...)end
    Engine.reload()
    local h=H:new{width=80,cols={{{level=1},{level=2},{level=3},{level=4}}}}
    for i=1,100 do h:paintTo(Kit.canvas(),0,0)end
    assert(count==4,"recomputed heatmap palette "..count.." times")
    Engine.reload();h:paintTo(Kit.canvas(),0,0);assert(count==8)
    Engine.tint=tint
end)
check("foreground-contrast-reused-until-theme-changes",function()
    local T=require("mooncolor_themes");local old=T.foreground;local calls=0
    T.foreground=function(...)calls=calls+1;return old(...)end
    Engine.reload();for i=1,100 do Engine.foreground("progress")end
    assert(calls==1)
    Engine.reload();Engine.foreground("progress");assert(calls==2)
    T.foreground=old
end)
