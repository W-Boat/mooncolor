"""Pixel equality using KOReader's actual Lua FFI BlitBuffer, without native CBB.
Storage is a retained ffi array, so this works on the Windows test host too.
"""
from pathlib import Path
import os, sys, json
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'work/test-deps'))
from lupa.luajit21 import LuaRuntime
vm=LuaRuntime(unpack_returned_tuples=True)
moon=Path(os.environ.get('MOON_TEST_SOURCE',ROOT/'work/moon-0.2.43')).as_posix()
plugin=Path(os.environ.get('MOON_COLOR_TEST_PLUGIN', ROOT)).as_posix()
vm.execute(f"package.path='{moon}/tests/?.lua;{moon}/book.koplugin/?.lua;{moon}/book.koplugin/?/init.lua;{plugin}/?.lua;'..package.path")
vm.globals().real_bb_path=Path(os.environ.get('KOREADER_BLITBUFFER_SOURCE',ROOT/'work/blitbuffer-2026.07.lua')).as_posix()
result=vm.execute('''
local Kit=require("support.widget_stubs");Kit.install("paper")
package.loaded["ffi/posix_h"]={}
local BB=dofile(real_bb_path)
package.loaded["ffi/blitbuffer"]=BB
local ffi=require("ffi")
local Box=require("ui.themes.widgets.box")
local Theme=require("ui.themes")
local original=Box.paintTo
local fast=require("mooncolor_surface").wrap(original,{config=function()return {enabled=true,fast_panels=true}end},Theme,BB)
local function buffer()
    local storage=ffi.new("uint8_t[?]",160*120*4)
    local bb=BB.new(160,120,BB.TYPE_BBRGB32,storage)
    for y=0,119 do bb:paintRectRGB32(0,y,160,1,BB.ColorRGB32(y,50,200-y,255))end
    return bb,storage
end
local count=0
for _,radius in ipairs{0,2,8,30,999}do
 for _,size in ipairs{{10,10},{48,26},{100,60},{120,80}}do
  for _,alpha in ipairs{50,100}do
   for _,aa in ipairs{true,false}do
    G_reader_settings.nilOrTrue=function()return aa end
    local leaf={getSize=function()return {w=size[1],h=size[2]}end,
      paintTo=function(self,bb,x,y)bb:paintRectRGB32(x,y,size[1],size[2],BB.ColorRGB32(20,100,180,255))end}
    local b=Box:new{style={bg=255,radius=radius,border=2,border_color=70,
        shadow=2,shadow_color=0},width=100,height=60,bg_alpha=alpha,leaf}
    local before,storage1=buffer();local after,storage2=buffer()
    original(b,before,20,20);fast(b,after,20,20)
    assert(ffi.string(storage1,160*120*4)==ffi.string(storage2,160*120*4),
        "pixel mismatch radius="..radius.." size="..size[1].." alpha="..alpha.." aa="..tostring(aa))
    count=count+1
   end
  end
 end
end
return count
''')
report={'passed_pixel_comparisons':result,'blitbuffer':'KOReader actual Lua FFI, CBB disabled',
        'cases':'radius, child size/clipping, opacity, anti alias, shadow; RGB background and child',
        'limitations':'Host pixel equality; no physical screen waveform validation'}
report_path=ROOT/'outputs/mooncolor-pixel-tests.json' if (ROOT/'outputs').is_dir() else ROOT/'pixel-test-results.json'
report_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
