from pathlib import Path
import sys
import json
import os

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'work/test-deps'))
from lupa.luajit21 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
moon = Path(os.environ.get('MOON_TEST_SOURCE', ROOT / 'work/moon')).as_posix()
plugin = Path(os.environ.get('MOON_COLOR_TEST_PLUGIN', ROOT)).as_posix()
TESTING_V21 = any(v in Path(plugin, '_meta.lua').read_text(encoding='utf-8') for v in ['2.1.0','2.2.0'])
lua.execute(f"package.path = '{moon}/tests/?.lua;{moon}/book.koplugin/?.lua;{moon}/book.koplugin/?/init.lua;{plugin}/?.lua;' .. package.path")
BOOT = '''
Kit = require("support.widget_stubs")
Kit.install("paper")
-- Use KOReader's real line drawing implementation, not the no-op test leaf.
package.loaded["ui/widget/linewidget"] = nil
package.preload["ui/widget/linewidget"] = function()
    return dofile(KOREADER_ROOT .. "/frontend/ui/widget/linewidget.lua")
end
package.loaded["ui/widget/container/bottomcontainer"] = nil
package.preload["ui/widget/container/bottomcontainer"] = function()
    return dofile(KOREADER_ROOT .. "/frontend/ui/widget/container/bottomcontainer.lua")
end
local plain_canvas = Kit.canvas
Kit.canvas = function()
    local bb=plain_canvas()
    local function gray(c)
        if type(c)=="table" and c.rgb then return math.floor(c.r*0.3+c.g*0.59+c.b*0.11) end
        return c
    end
    local rounded,border=bb.paintRoundedRect,bb.paintBorder
    bb.paintRect=function(_,x,y,w,h,c) bb.ops[#bb.ops+1]={op="rect",x=x,y=y,w=w,h=h,c=gray(c)} end
    bb.paintRoundedRect=function(self,x,y,w,h,c,r) return rounded(self,x,y,w,h,gray(c),r) end
    bb.paintBorder=function(self,x,y,w,h,bw,c,r) return border(self,x,y,w,h,bw,gray(c),r) end
    bb.paintRectRGB32=function(_,x,y,w,h,c) bb.ops[#bb.ops+1]={op="rect",x=x,y=y,w=w,h=h,c=c,rgb_api=true} end
    bb.paintRoundedRectRGB32=function(self,x,y,w,h,c,r) rounded(self,x,y,w,h,c,r);bb.ops[#bb.ops].rgb_api=true end
    bb.paintBorderRGB32=function(self,x,y,w,h,bw,c,r) border(self,x,y,w,h,bw,c,r);bb.ops[#bb.ops].rgb_api=true end
    return bb
end
Device = require("device")
Device.hasColorScreen = function() return true end
Device.hasKaleidoWfm = function() return true end
Device.screen.isColorEnabled = function() return true end
BB = require("ffi/blitbuffer")
BB.Color8 = function(v)
    assert(type(v) == "number" and v >= 0 and v <= 255, "RGB token leaked to grayscale constructor: " .. tostring(v))
    return v
end
original_color8 = BB.Color8
BB.ColorRGB32 = function(r,g,b,a) return {r=r,g=g,b=b,a=a, rgb=true} end
saved, saves = {}, 0
local Settings = require("utils.settings")
Settings.getSource = function(id) assert(id == "ext.mooncolor"); return saved end
Settings.saveSource = function(id) assert(id == "ext.mooncolor"); saves=saves+1 end
package.loaded["logger"] = {warn=function() end}
package.loaded["utils.log"] = {warn=function() end}
package.loaded["ui.guard"] = {
    wrap=function(_,fn) return fn end,
    call=function(_,fn,...) return fn(...) end,
}
package.loaded["ui.exit_windows"] = {exiting=false}
package.loaded["utils.paths"] = {}
package.loaded["libs/libkoreader-lfs"] = {}
package.loaded["ui.widgets.plain_cover"] = {}
if PLUGIN_UNDER_TEST == "2.1" then
    metadata_rows,metadata_reads={},0
    package.loaded["book.store"]={identityFor=function(file)
        metadata_reads=metadata_reads+1
        return metadata_rows[file]
    end}
    package.loaded["ui.themes.widgets.image.core"]=nil
    package.preload["ui.themes.widgets.image.core"]=nil
    package.loaded["ui.themes.widgets.image.download"] = {cached=function()end}
    package.loaded["ui/widget/imagewidget"] = {
        new=function(_,opts)
            opts.dimen={w=opts.width or 10,h=opts.height or 10}
            opts.getSize=function(self)return self.dimen end
            opts.free=function()end
            opts.paintTo=function()end
            return opts
        end,
    }
    package.loaded["ui/widget/infomessage"]={new=function(_,opts)return opts end}
    package.loaded["apps/reader/readerui"]={
        showReaderCoroutine=function(self,file,provider,seamless)
            self.notice=require("ui/widget/infomessage"):new{timeout=0,invisible=seamless,text=file}
            if self.raise then error("open failed")end
        end,
    }
    package.loaded["apps/reader/modules/readerrolling"]={showEngineProgress=function(self,p)
        self.native_calls=(self.native_calls or 0)+1
    end}
    clock_time=100
    package.loaded["socket"]={gettime=function()return clock_time end}
end
-- Data and host boundaries only; home widgets, calculations, mask and panel code are real Moon Lua.
package.loaded["book.catalog"] = {libraryScope=function(id)return id end,formatDuration=function(n)return tostring(math.floor(n/60)).."分钟"end}
package.loaded["book.stats_db"] = {
    dailyBySource=function()
        home_db_reads=(home_db_reads or 0)+1
        local days={};for i=0,30 do days[#days+1]={ymd=os.date("%Y-%m-%d",os.time()-i*86400),seconds=(i%5)*900,pages=i+1}end
        return days
    end,progressBooks=function()return {}end,
}
package.loaded["source.base"] = {SourceCapabilities={}}
package.loaded["desktop.reader_exit"] = {}
package.loaded["features.panel.menu"] = {}
package.loaded["features.panel.native_settings"] = {}
Kit.sections.insight={month_goal_hours=10,year_goal_books=20}
Kit.sections.home={home_stats_opacity=100}
Engine = require("mooncolor_engine")
assert(Engine.install(), Engine.error)
assert(Engine.active())
Theme = require("ui.themes")
results = {}
function check(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ": " .. tostring(err))
    results[#results+1] = {name=name, passed=true}
end
function rgb(c) return type(c)=="table" and c.rgb==true end
'''.replace('KOREADER_ROOT', json.dumps(Path(os.environ.get('KOREADER_TEST_SOURCE', ROOT / 'work/koreader-2026.07')).as_posix()))
BOOT = BOOT.replace('PLUGIN_UNDER_TEST', json.dumps('2.1' if TESTING_V21 else '2.0'))
lua.execute(BOOT)
lua.execute('''
check("global-grayscale-constructor-unchanged", function() assert(BB.Color8==original_color8); assert(BB.Color8(128)==128) end)
local Button = require("ui.themes.widgets.button")
local Row = require("ui.themes.widgets.row")
local Tabbar = require("ui.themes.widgets.tabbar")
local Progress = require("ui.themes.widgets.progress")
local Box = require("ui.themes.widgets.box")
for _, theme_id in ipairs(Theme.ids) do
  for _, palette in ipairs(Engine.palettes) do
    check(theme_id .. "/" .. palette.id .. "/actual-Moon-widgets", function()
      Kit.use(theme_id)
      Engine.set("palette", palette.id)
      local raw = Theme.get(theme_id)
      assert(raw.button.primary.bg < 256 and raw.selected.ink < 256)
      local t = Theme.current()
      assert(t ~= raw and t.button.primary.bg > 0xFFFFFF)
      assert(t.color.ink==0 and t.color.page==255)
      local bb = Kit.canvas()
      Button:new{text="确定", variant="primary", width=200}:paintTo(bb,0,0)
      Row.widget{width=550,title="选中条目",selected=true}:paintTo(bb,0,100)
      Tabbar.widget{width=550, tabs={{id="a",text="首页",icon="home"},{id="b",text="设置",icon="settings"}},active="a"}:paintTo(bb,0,200)
      Progress:new{width=300,percent=43}:paintTo(bb,0,300)
      local found = false
      for _, op in ipairs(bb.ops) do if rgb(op.c) then found=true end end
      assert(found, "no actual RGB paint operations")
      assert(BB.Color8==original_color8)
    end)
  end
end
check("primary-button-has-white-label-and-colored-fill", function()
  local b=Button:new{text="确定",variant="primary",width=150}
  local labels=Kit.find(b,function(w) return w.text=="确定" and w.fgcolor~=nil end)
  assert(#labels==1 and labels[1].fgcolor==255)
  local bb=Kit.canvas(); b:paintTo(bb,0,0); assert(rgb(bb.ops[1].c))
end)
check("selected-row-has-colored-text", function()
  local row=Row.widget{width=550,title="选中",selected=true}
  local labels=Kit.find(row,function(w) return w.text=="选中" end)
  assert(#labels==1 and rgb(labels[1].fgcolor))
end)
check("optional-card-borders", function()
  Engine.set("card_edges",true)
  local box=Box:new{style=Theme.current().card,width=200,height=80}
  local bb=Kit.canvas();box:paintTo(bb,0,0)
  local found=false; for _,op in ipairs(bb.ops) do if op.op=="border" and rgb(op.c) then found=true end end
  assert(found); Engine.set("card_edges",false)
end)
check("toggles-respect-disabled-sections", function()
  for _,key in ipairs{"buttons","tabs","progress"} do Engine.set(key,false) end
  local t=Theme.current(); assert(t.button.primary.bg<256 and t.selected.ink<256 and t.progress.fill<256)
  for _,key in ipairs{"buttons","tabs","progress"} do Engine.set(key,true) end
end)
check("disable-and-reenable", function()
  Engine.set("enabled",false);assert(Theme.current()==Theme.get(Theme.id()))
  Engine.set("enabled",true);assert(Theme.current()~=Theme.get(Theme.id()))
end)
check("night-mode-falls-back", function()
  Device.screen.night_mode=true;assert(not Engine.active());assert(Theme.current()==Theme.get(Theme.id()))
  Device.screen.night_mode=false
end)
check("monochrome-device-falls-back", function()
  Device.hasColorScreen=function() return false end;assert(not Engine.active());assert(Theme.current()==Theme.get(Theme.id()))
  Device.hasColorScreen=function() return true end
end)
check("color-disabled-falls-back", function()
  Device.screen.isColorEnabled=function() return false end;assert(not Engine.active());assert(Theme.current()==Theme.get(Theme.id()))
  Device.screen.isColorEnabled=function() return true end
end)
check("invalid-settings-and-key-are-rejected", function()
  assert(not Engine.set("palette","invalid"));assert(not Engine.set("bogus",nil))
  saved.palette="invalid";Engine.reload();assert(Engine.config().palette=="ocean");saved.palette="ocean";Engine.reload()
end)
check("repeat-install-is-idempotent", function()
  local fn=Theme.current;assert(Engine.install());assert(Theme.current==fn)
end)
local UI=require("ui/uimanager")
check("default-keeps-original-refresh-opt-in-uses-color-waveform", function()
  UI:setDirty({book_window=true},"ui");assert(Kit.dirty[#Kit.dirty].mode=="ui")
  Engine.set("quality_refresh",true)
  UI:setDirty({book_window=true},"ui");assert(Kit.dirty[#Kit.dirty].mode=="full")
end)
check("native-and-reader-refresh-unchanged", function()
  UI:setDirty({},"ui");assert(Kit.dirty[#Kit.dirty].mode=="ui")
  UI:setDirty("all","ui");assert(Kit.dirty[#Kit.dirty].mode=="ui")
end)
check("small-clock-region-remains-ui", function()
  UI:setDirty({book_window=true},"ui",{w=600,h=20});assert(Kit.dirty[#Kit.dirty].mode=="ui")
end)
check("fast-progress-remains-fast", function()
  UI:setDirty({book_window=true},"fast");assert(Kit.dirty[#Kit.dirty].mode=="fast")
end)
check("refresh-callback-preserves-region-and-dither", function()
  UI:setDirty({book_window=true},function() return "ui",{w=600,h=700},true end)
  local mode,region,dither=Kit.dirty[#Kit.dirty].mode();assert(mode=="full" and region.h==700 and dither==true)
end)
check("quality-refresh-toggle", function()
  Engine.set("quality_refresh",false);UI:setDirty({book_window=true},"ui");assert(Kit.dirty[#Kit.dirty].mode=="ui")
  Engine.set("quality_refresh",false)
end)
check("extension-contract-and-settings-rows", function()
  local desc=dofile(PLUGIN_ROOT .. "/moon_source.lua")
  assert(desc.api==1 and desc.id=="ext.mooncolor" and desc.provides.source==false)
  local desktop={updateView=function(self) self.updated=true end}
  local entries=desc.provides.features.setting.entries(desktop)
  assert(entries[1].group=="desktop")
  local sections=entries[1].page.sections()
  assert(#sections[1].rows>=13 and #sections[2].rows==4)
  for _,make in ipairs(sections[1].rows) do make(550):paintTo(Kit.canvas(),0,0) end
  local row=sections[1].rows[1](550);Kit.taps(row)[1]:onTapThemeArea();assert(saved.enabled==false and desktop.updated)
  Engine.set("enabled",true)
  local action=desc.provides.features.panel.actions()[1]
  assert(action.scope=="desktop");desktop.updated=false
  action.run({ui={book={desktop=desktop}}});assert(saved.enabled==false and desktop.updated)
  Engine.set("enabled",true)
end)
for _, id in ipairs(Theme.ids) do
  check(id .. "/quick-panel-real-widget", function()
    Kit.use(id)
    local ActionButton=require("features.panel.widget.button")
    local button=ActionButton:new{width=180,height=150,icon="palette",title="彩墨配色",active=true,id="color"}
    local bb=Kit.canvas();button:paintTo(bb,0,0)
    local found=false;for _,op in ipairs(bb.ops) do if rgb(op.c) then found=true end end
    assert(found)
  end)
end
check("icon-picker-selected-cell", function()
  Kit.use("paper")
  local Picker=require("ui.themes.widgets.icon_picker")
  local cell=Picker.cellWidget({theme=Theme.current(),current="home",cell_w=120,cell=100},"home")
  local labels=Kit.find(cell,function(w) return w.text=="home" and w.fgcolor~=nil end)
  assert(#labels>0);for _,label in ipairs(labels) do assert(rgb(label.fgcolor)) end
  cell:paintTo(Kit.canvas(),0,0)
end)
check("ordinary-rectangle-really-loses-RGB-in-test-harness", function()
  local bb=Kit.canvas();bb:paintRect(0,0,20,3,BB.ColorRGB32(20,80,150,255));assert(not rgb(bb.ops[1].c))
end)
for _, theme in ipairs(Theme.ids) do
 for _, style in ipairs{"line","pill"} do
  for _, labels in ipairs{true,false} do
   check(theme.."/"..style.."/labels-"..tostring(labels).."/navigation-raster",function()
    Kit.use(theme);Engine.set("navbar_style",style);Engine.set("navbar_labels",labels)
    local selected,rect=nil,nil
    local nav=Tabbar.widget{width=551,tabs={{id="a",text="首页",icon="home"},{id="b",text="设置",icon="settings"}},active="a",
      on_tab=function(id,r)selected,rect=id,r end}
    local bb=Kit.canvas();nav:paintTo(bb,0,0)
    local indicator=false
    for _,op in ipairs(bb.ops) do
      if style=="line" and op.h==Theme.px(3) and op.w<=Theme.px(28) and op.rgb_api and rgb(op.c) then indicator=true end
      if style=="pill" and op.op=="border" and op.r>0 and op.rgb_api and rgb(op.c) then indicator=true end
    end
    assert(indicator,"missing actual colored active indicator")
    local found=false;for _,text in ipairs(Kit.texts(nav))do if text=="首页" then found=true end end
    assert(found==labels)
    local taps=Kit.taps(nav);assert(#taps==2)
    assert(taps[1].dimen.w+taps[2].dimen.w==551)
    assert(taps[1].dimen.h>=Theme.px(44))
    taps[1]:onTapThemeArea();assert(selected==nil)
    taps[2]:onTapThemeArea();assert(selected=="b" and rect.w==276)
    if not labels then assert(taps[1].onMoonNavHold and taps[1].ges_events.MoonNavHold) end
   end)
  end
 end
end
check("paper-default-buttons-and-progress-use-RGB-drawing",function()
  Kit.use("paper");local bb=Kit.canvas()
  Button:new{text="开始阅读",variant="primary",width=220}:paintTo(bb,0,0)
  Progress:new{width=220,percent=50}:paintTo(bb,0,100)
  local count=0;for _,op in ipairs(bb.ops)do if rgb(op.c)and op.rgb_api then count=count+1 end end
  assert(count>=3)
end)
check("headings-and-icons-colored-body-stays-black",function()
  local Text=require("ui.themes.widgets.text");local Icon=require("ui.themes.widgets.icon")
  assert(rgb(Text.line("title","图书馆").fgcolor));assert(Text.line("body","正文").fgcolor==0)
  local widget=Icon.widget{name="settings",size=24}
  local labels=Kit.find(widget,function(w)return w.fgcolor~=nil end);assert(rgb(labels[1].fgcolor))
end)
check("statistics-heatmap-and-chart-use-RGB",function()
  assert(Engine.coverage.heatmap and Engine.coverage.chart)
  local Heatmap=require("ui.widgets.heatmap")
  local heat=Heatmap:new{width=70,cols={{{level=1},{level=2},{level=3},{level=4}}}}
  local bb=Kit.canvas();heat:paintTo(bb,0,0)
  for _,op in ipairs(bb.ops)do assert(op.rgb_api and rgb(op.c))end
  local chart=require("ui.widgets.chart").bars{width=500,values={100,200,350},show_labels=false}
  chart:paintTo(bb,0,150)
  local found=false;for _,op in ipairs(bb.ops)do if op.rgb_api and rgb(op.c)then found=true end end;assert(found)
end)
check("book-progress-badge-color",function()
  assert(Engine.coverage.book_badges)
  local badge=require("ui.widgets.book").progressBadge(150,32)
  local bb=Kit.canvas();badge:paintTo(bb,0,0);assert(bb.ops[1].rgb_api and rgb(bb.ops[1].c))
end)
check("real-FFI-RGB-type-is-detected",function()
  local ffi=require("ffi");ffi.cdef[[typedef struct {uint8_t r,g,b,alpha;} MoonTestRGB;]]
  local old=BB.ColorRGB32;BB.ColorRGB32=ffi.typeof("MoonTestRGB")
  assert(require("mooncolor_render").isRGB(BB.ColorRGB32(20,80,150,255)))
  BB.ColorRGB32=old
end)
check("nav-height-change-forces-desktop-shell-rebuild",function()
  local desk={_shell="old",updateView=function(self)assert(self._shell==nil)end}
  Engine.set("navbar_labels",true,desk)
  Engine.set("navbar_labels",false,desk)
end)
check("navbar-color-toggle-preserves-neutral-navigation",function()
  Engine.set("tabs",false)
  local nav=Tabbar.widget{width=600,tabs={{id="a",text="首页",icon="home"}},active="a"}
  local bb=Kit.canvas();nav:paintTo(bb,0,0)
  for _,op in ipairs(bb.ops)do assert(not rgb(op.c)) end
  Engine.set("tabs",true)
end)
'''.replace('PLUGIN_ROOT', json.dumps(plugin)))

lua.execute((ROOT / 'tests/v2.lua').read_text(encoding='utf-8'))
if TESTING_V21:
    lua.execute((ROOT / 'tests/v21.lua').read_text(encoding='utf-8'))
    if '2.2.0' in Path(plugin, '_meta.lua').read_text(encoding='utf-8'):
        lua.execute((ROOT / 'tests/v22.lua').read_text(encoding='utf-8'))
results = [dict(item.items()) for item in lua.globals().results.values()]
for scenario in ['rollback-and-retry', 'missing-moon']:
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.execute(f"package.path = '{moon}/tests/?.lua;{moon}/book.koplugin/?.lua;{moon}/book.koplugin/?/init.lua;{plugin}/?.lua;' .. package.path")
    vm.execute(BOOT.replace('assert(Engine.install(), Engine.error)\nassert(Engine.active())', ''))
    if scenario == 'rollback-and-retry':
        vm.execute('''
        local Row=require("ui.themes.widgets.row")
        local real=Row.widget
        Row.widget=function() end
        local Theme=require("ui.themes")
        local original=Theme.current
        assert(not Engine.install());assert(Theme.current==original);assert(BB.Color8==original_color8)
        Row.widget=real
        assert(Engine.install(),Engine.error)
        local Button=require("ui.themes.widgets.button")
        local bb=Kit.canvas();Button:new{text="Retry",variant="primary",width=150}:paintTo(bb,0,0)
        assert(type(bb.ops[1].c)=="table" and bb.ops[1].c.rgb)
        ''')
    else:
        vm.execute('''
        package.loaded["ui.themes"]=nil
        package.preload["ui.themes"]=function() error("Moon not installed") end
        assert(not Engine.install());assert(not Engine.active());assert(type(Engine.status())=="string")
        ''')
    results.append({'name': scenario, 'passed': True})
report = {'runtime': 'LuaJIT 2.1 (lupa)', 'moon_source': moon,
          'passed': len(results), 'cases': results,
          'method': 'Actual Moon widgets/home/image queue/library/sidebar Lua; KOReader LineWidget/BottomContainer; FFI equality regression. Device, fonts, I/O, data and ReaderUI/ReaderRolling host interfaces are stubbed. RGB-specific paint assertions.',
          'limitations': 'No hardware or on-device visual validation.'}
(ROOT / 'test-results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(f"{len(results)} Moon Color integration checks passed")
