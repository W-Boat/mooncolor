-- A real touch palette built from existing Moon widgets.
local Swatch={}
Swatch.colors={
    "#205CA8","#285D88","#356C96","#536FB5","#66509A","#8A4C8F",
    "#16685C","#246648","#34785D","#63843D","#865E20","#B45A24",
    "#A34434","#A34454","#B85B72","#875D44","#52677C","#333333",
    "#65A9C9","#80B4A2","#A6BC78","#DBC071","#D99D87","#C5A6D5",
    "#FFFFFF","#E6E6E6","#AAAAAA","#777777","#444444","#000000",
}
function Swatch.new(Engine,role,current,on_select,on_hex)
    local Modal=require("ui.themes.widgets.modal")
    local Theme=require("ui.themes")
    local Text=require("ui.themes.widgets.text")
    local Box=require("ui.themes.widgets.box")
    local Tap=require("ui.themes.widgets.tap")
    local VG=require("ui/widget/verticalgroup")
    local HG=require("ui/widget/horizontalgroup")
    local HS=require("ui/widget/horizontalspan")
    local VS=require("ui/widget/verticalspan")
    local palette=Modal:new{}
    local width=palette:innerWidth()
    local gap=Theme.px(8)
    local size=math.floor((width-5*gap)/6)
    local body=VG:new{align="left"}
    local row
    for i,hex in ipairs(Swatch.colors)do
        if (i-1)%6==0 then
            if row then body[#body+1]=VS:new{width=gap}end
            row=HG:new{align="center"};body[#body+1]=row
        else row[#row+1]=HS:new{width=gap}end
        local rgb=tonumber(hex:sub(2),16)
        local token=Engine.rgbToken(rgb)
        local selected=hex==current
        local cell=Box:new{width=size,height=size,style={bg=token,border=selected and 3 or 1,
            border_color=Engine.foregroundRGB(rgb),radius=4},
            selected and Text.line("body","✓",{color=Engine.foregroundRGB(rgb)})or nil}
        row[#row+1]=Tap.wrap(cell,function()palette:close();on_select(hex)end)
    end
    body[#body+1]=VS:new{width=gap}
    body[#body+1]=Text.line("caption","当前 "..current.." · 点色块应用",{width=width})
    palette:setDialog{title=role,body=body,buttons={
        {text="精确输入",callback=function()palette:close();on_hex()end},
        {text="取消",callback=function()palette:close()end},
    }}
    return palette
end
return Swatch
