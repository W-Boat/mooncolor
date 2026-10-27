from pathlib import Path
import os,sys,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'work/test-deps'))
from lupa.luajit21 import LuaRuntime
moon=Path(os.environ.get('MOON_TEST_SOURCE',ROOT/'work/moon-nativecolor')).as_posix()
plugin=Path(os.environ.get('MOON_COLOR_TEST_PLUGIN',ROOT)).as_posix()
BOOT='''
Kit=require("support.widget_stubs");Kit.install("paper")
Device=require("device");BB=require("ffi/blitbuffer")
BB.Color8=function(n)assert(type(n)=="number"and n>=0 and n<=255,"RGB leaked to grayscale");return n end
saved={navbar_labels=false,navbar_style="line",palette="custom",custom_colors={primary="#ff0000"},
    fast_covers=true,quality_refresh=true};saves=0
local Settings=require("utils.settings")
Settings.getSource=function(id)assert(id=="ext.mooncolor");return saved end
Settings.saveSource=function(id)assert(id=="ext.mooncolor");saves=saves+1 end
metadata_rows,metadata_reads={},0
package.loaded["book.store"]={identityFor=function(file)
    metadata_reads=metadata_reads+1;return metadata_rows[file] end}
package.loaded["utils.paths"]={coverPath=function(id,sid)return "/covers/"..sid.."/"..id..".png"end}
package.loaded["libs/libkoreader-lfs"]={attributes=function(file,field)
    if file=="/covers/local/test.png"or file=="/cover.png"then return "file"end end}
decoded,freed=0,0
package.loaded["ui/widget/imagewidget"]={new=function(_,opts)
    decoded=decoded+1
    opts.dimen={w=opts.width,h=opts.height}
    opts.getSize=function(self)return self.dimen end
    opts.paintTo=function()end;opts.free=function()freed=freed+1 end
    return opts end}
package.loaded["ui/widget/infomessage"]={new=function(_,opts)return opts end}
package.loaded["apps/reader/readerui"]={showReaderCoroutine=function(self,file,provider,seamless)
    self.notice=require("ui/widget/infomessage"):new{timeout=0,invisible=seamless,text=file}
    if self.extra then self.extra_notice=require("ui/widget/infomessage"):new{timeout=0,text="another"}end
    if self.raise then error("open failed")end
    return "opened" end}
package.loaded["apps/reader/modules/readerrolling"]={showEngineProgress=function(self)
    self.native_calls=(self.native_calls or 0)+1 end}
clock_time=100;package.loaded.socket={gettime=function()return clock_time end}
package.loaded["ui.guard"]={wrap=function(_,fn)return fn end,
    call=function(_,fn,...)local ok,a,b=pcall(fn,...);assert(ok,a);return ok,a,b end}
package.loaded["ui.exit_windows"]={exiting=false}
local UI=require("ui/uimanager")
refreshes={};Device.screen.bb=Kit.canvas()
Device.screen.bb.paintRect=function(self,x,y,w,h,c)
    self.ops[#self.ops+1]={op="clear",x=x,y=y,w=w,h=h,c=c}end
Device.screen.refreshUI=function(_,x,y,w,h)refreshes[#refreshes+1]={x=x,y=y,w=w,h=h}end
originals={Theme=require("ui.themes").current,Color8=BB.Color8,
    Box=require("ui.themes.widgets.box").paintTo,Dirty=UI.setDirty,Close=UI.close}
Engine=require("mooncolor_engine")
assert(Engine.install(),Engine.error)
Theme=require("ui.themes");Loading=require("mooncolor_loading")
Reader=require("apps/reader/readerui");Rolling=require("apps/reader/modules/readerrolling")
Tabbar=require("ui.themes.widgets.tabbar")
results={}
function check(name,fn)
    local ok,err=pcall(fn);assert(ok,name..": "..tostring(err))
    results[#results+1]={name=name,passed=true}
end
'''

def runtime():
    vm=LuaRuntime(unpack_returned_tuples=True)
    vm.execute(f"package.path='{moon}/tests/?.lua;{moon}/book.koplugin/?.lua;{moon}/book.koplugin/?/init.lua;{plugin}/?.lua;'..package.path")
    vm.execute(BOOT)
    return vm

lua=runtime()
lua.execute('''
check("upgrade-keeps-navigation-and-ignores-all-old-color-performance-settings",function()
    assert(Engine.config().navbar_style=="line"and not Engine.config().navbar_labels)
    assert(not Engine.config().palette and not Engine.config().custom_colors)
    assert(not Engine.config().quality_refresh and not Engine.config().fast_covers)
    assert(saves==0)
end)
check("no-theme-BB-widget-refresh-or-private-function-patches",function()
    local UI=require("ui/uimanager")
    assert(Theme.current==originals.Theme and BB.Color8==originals.Color8)
    assert(require("ui.themes.widgets.box").paintTo==originals.Box)
    assert(UI.setDirty==originals.Dirty and UI.close==originals.Close)
    for _,name in ipairs{"mooncolor_render","mooncolor_themes","mooncolor_swatch","mooncolor_editor",
        "mooncolor_decor","mooncolor_controls","mooncolor_perf","mooncolor_home","mooncolor_ticket",
        "mooncolor_panels","mooncolor_power","mooncolor_surface","mooncolor_quickpanel"}do
        assert(not package.loaded[name],name)
    end
end)
check("navigation-options-validate-and-unchanged-values-do-not-save",function()
    local before=saves
    assert(Engine.set("navbar_style","line")and saves==before)
    assert(not Engine.set("palette","ocean"))
    assert(not Engine.set("navbar_style","invalid"))
    assert(not Engine.set("navbar_labels","false"))
end)
for _,theme in ipairs{"paper","bold","soft"}do
 for _,style in ipairs{"pill","line"}do
  for _,labels in ipairs{true,false}do
   check(theme.."/"..style.."/labels="..tostring(labels),function()
    Kit.use(theme);Engine.set("navbar_style",style);Engine.set("navbar_labels",labels)
    local chosen
    local nav=Tabbar.widget{width=601,tabs={{id="home",text="首页",icon="home"},
        {id="library",text="图书馆",icon="menu_book"},{id="settings",text="设置",icon="settings"}},
        active="home",on_tab=function(id)chosen=id end}
    assert(nav:getSize().w==601)
    assert(Tabbar.height()==(labels and 64 or 48))
    nav:paintTo(Kit.canvas(),0,700)
    local titles=Kit.find(nav,function(w)return w.text=="首页"end)
    assert((#titles>0)==labels)
    local taps=Kit.find(nav,function(w)return w.onTapThemeArea end)
    taps[1]:onTapThemeArea(taps[1]);assert(not chosen)
    taps[2]:onTapThemeArea(taps[2]);assert(chosen=="library")
   end)
  end
 end
end
check("explicit-native-hide-label-option-is-respected",function()
    Engine.set("navbar_labels",true)
    local nav=Tabbar.widget{width=600,tabs={{id="home",text="首页",icon="home"}},active="home",show_labels=false}
    assert(#Kit.find(nav,function(w)return w.text=="首页"end)==0)
    assert(#Kit.find(nav,function(w)return w.onMoonNavHold end)==1)
end)
if Theme.color then
 for _,theme in ipairs{"paper","bold","soft"}do
  for _,preset in ipairs{"ocean","garden","clay"}do
   check("official-color/"..theme.."/"..preset,function()
    Kit.use(theme);Kit.color_enabled=true;Kit.display.theme_preset=preset
    Engine.set("navbar_style","pill")
    local original=Theme.current
    local nav=Tabbar.widget{width=600,tabs={{id="home",text="首页",icon="home"}},active="home"}
    local bb=Kit.canvas();nav:paintTo(bb,0,0)
    local accent=Theme.current().color.navigation
    assert(accent>255 and Theme.current==original)
    local nodes=Kit.find(nav,function(w)return w.fgcolor==accent end);assert(#nodes>0)
    local colored=false;for _,op in ipairs(bb.ops)do if op.rgb then colored=true end end
    assert(colored,"native RGB drawing missing")
    -- Changes made through official settings are picked up without Engine.reload.
    Kit.display.theme_preset=preset=="ocean"and"clay"or"ocean"
    local next_nav=Tabbar.widget{width=600,tabs={{id="home",text="首页",icon="home"}},active="home"}
    assert(#Kit.find(next_nav,function(w)return w.fgcolor==Theme.current().color.navigation end)>0)
   end)
  end
 end
 Kit.color_enabled=false
end
check("loading-prefers-Moon-title-authors-and-local-cover",function()
    metadata_rows["/cache/1.epub"]={source_id="local",stable_id="test",
        book={title="月读书名",authors={"作者甲","作者乙"},cover="https://example.invalid/cover"}}
    local m=Loading.metadata("/cache/1.epub",{title="旧书名",authors="旧作者"})
    assert(m.title=="月读书名"and m.authors=="作者甲 · 作者乙"and m.cover=="/covers/local/test.png")
    assert(Loading.metadata("/example.epub").title=="example")
end)
check("initial-opening-paint-does-not-redraw-for-zero-or-tiny-progress",function()
    Loading.finish();clock_time=100
    local reader={};Reader.showReaderCoroutine(reader,"/cache/1.epub")
    local card=reader.notice;card:paintTo(Kit.canvas(),0,0)
    local before=#refreshes;local decoded_before=decoded;local reads=metadata_reads
    local rolling={ui={document={file="/cache/1.epub"}}}
    Rolling.showEngineProgress(rolling,0);clock_time=101;Rolling.showEngineProgress(rolling,.02)
    assert(#refreshes==before,"initial repaint count "..#refreshes.." before "..before)
    clock_time=102;Rolling.showEngineProgress(rolling,.1)
    assert(#refreshes==before+1 and refreshes[#refreshes].h<800,
        "partial repaint count "..#refreshes.." before "..before.." height "..tostring(refreshes[#refreshes]and refreshes[#refreshes].h))
    clock_time=103;Rolling.showEngineProgress(rolling,.1);Rolling.showEngineProgress(rolling,.09)
    assert(#refreshes==before+1)
    assert(decoded==decoded_before and metadata_reads==reads)
    clock_time=103.1;Rolling.showEngineProgress(rolling,1)
    assert(card.bar.percent==100 and #refreshes==before+2)
    Rolling.showEngineProgress(rolling,nil);assert(not rolling._moon_loading)
end)
check("new-document-does-not-inherit-previous-book-progress-throttle",function()
    Loading.finish();clock_time=200
    local a={ui={document={file="a.epub"}}};Rolling.showEngineProgress(a,.5)
    local old=a._moon_loading
    local b={ui={document={file="b.epub"}}};Rolling.showEngineProgress(b,.01)
    assert(b._moon_loading and b._moon_loading~=old and not a._moon_loading)
    assert(b._moon_loading.book.title=="b")
end)
check("screen-rotation-rebuilds-only-the-loading-card",function()
    Loading.finish();clock_time=300
    local a={ui={document={file="rotation.epub"}}};Rolling.showEngineProgress(a,.1)
    local old=a._moon_loading
    Kit.SCREEN_W,Kit.SCREEN_H=800,600;clock_time=300.1;Rolling.showEngineProgress(a,.11)
    assert(a._moon_loading~=old and a._moon_loading.dimen.w==800 and a._moon_loading.dimen.h==600)
    Loading.finish();Kit.SCREEN_W,Kit.SCREEN_H=600,800
end)
check("Info-constructor-restored-on-errors-and-only-first-notice-replaced",function()
    Loading.finish()
    local I=require("ui/widget/infomessage");local new=I.new
    local a={extra=true};assert(Reader.showReaderCoroutine(a,"a.epub")=="opened")
    assert(a.notice.covers_fullscreen and not a.extra_notice.covers_fullscreen and I.new==new)
    a.raise=true;assert(not pcall(Reader.showReaderCoroutine,a,"error.epub"));assert(I.new==new)
end)
check("seamless-loaded-document-disabled-progress-keep-native-behavior",function()
    local a={};Reader.showReaderCoroutine(a,"a.epub",nil,true);assert(not a.notice.covers_fullscreen)
    local rolling={ui={document={file="a.epub",been_rendered=true}}}
    Rolling.showEngineProgress(rolling,.5);assert(rolling.native_calls==1)
    Engine.set("loading_screen",false);rolling.ui.document.been_rendered=false
    Rolling.showEngineProgress(rolling,.5);assert(rolling.native_calls==2)
    Engine.set("loading_screen",true)
end)
check("suspend-disable-and-exit-release-loading-once",function()
    Loading.finish();local a={};Reader.showReaderCoroutine(a,"a.epub")
    local card=a.notice;local old=card.free;local frees=0
    card.free=function(self)frees=frees+1;return old(self)end
    Engine.suspend();Engine.suspend();Loading.finish();assert(frees==1)
    local r={ui={document={file="a.epub"}}};Rolling.showEngineProgress(r,.5);assert(not r._moon_loading)
    Engine.resume();Engine.set("enabled",false)
    Reader.showReaderCoroutine(a,"a.epub");assert(not a.notice.covers_fullscreen)
    Engine.set("enabled",true)
end)
check("settings-only-show-navigation-loading-and-update",function()
    local source=require("moon_source")
    assert(source.id=="ext.mooncolor"and source.provides.source==false)
    assert(not source.provides.features.panel)
    local U=require("mooncolor_update")
    local row=source.provides.features.setting.entries({})[1]
    local sections=row.page.sections();assert(#sections==2)
    assert(#sections[1].rows==4 and #sections[2].rows==3)
end)
''')
lua.globals().python_sha256=lambda text:hashlib.sha256(text.encode('utf-8')).hexdigest()
lua.execute((ROOT/'tests/update.lua').read_text(encoding='utf-8'))
results=[dict(x.items())for x in lua.globals().results.values()]
report={'version':'3.0.0','passed':len(results),'moon_source':moon,'cases':results,
        'method':'Actual Moon widgets/themes and loading code; transport, filesystem, device, fonts and reader host boundaries stubbed.',
        'limitations':'No device timing or waveform validation.'}
(ROOT/'test-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(f"{len(results)} Moon Color 3.0 checks passed")
