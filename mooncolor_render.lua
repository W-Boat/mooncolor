-- KOReader's ordinary rectangle APIs intentionally reduce colors to luminance.
-- Supply a bound canvas view to Moon widgets; never alter native BB methods.
local Render = {}
local BB = require("ffi/blitbuffer")
local ffi = require("ffi")
local views = setmetatable({}, { __mode = "kv" })

function Render.isRGB(color)
    if BB.isColorRGB32 then return BB.isColorRGB32(color) end
    if type(color) == "cdata" then return ffi.istype(BB.ColorRGB32, color) end
    return type(color) == "table" and color.rgb == true -- offline test canvas
end

function Render.canvas(bb)
    if type(bb) == "table" and rawget(bb, "_moon_rgb_canvas") then return bb end
    if views[bb] then return views[bb] end
    local view = { _moon_rgb_canvas = true }
    function view:paintRect(x,y,w,h,c,setter)
        if Render.isRGB(c) then return bb:paintRectRGB32(x,y,w,h,c,setter) end
        return bb:paintRect(x,y,w,h,c,setter)
    end
    function view:paintRoundedRect(x,y,w,h,c,r)
        if Render.isRGB(c) then return bb:paintRoundedRectRGB32(x,y,w,h,c,r) end
        return bb:paintRoundedRect(x,y,w,h,c,r)
    end
    function view:paintBorder(x,y,w,h,bw,c,r,aa)
        if Render.isRGB(c) then return bb:paintBorderRGB32(x,y,w,h,bw,c,r,aa) end
        return bb:paintBorder(x,y,w,h,bw,c,r,aa)
    end
    views[bb] = view
    return setmetatable(view, { __index = function(_, key)
        local value = bb[key]
        if type(value) == "function" then
            local bound = function(_, ...) return value(bb, ...) end
            rawset(view, key, bound)
            return bound
        end
        return value
    end })
end

function Render.wrap(fn)
    return function(self, bb, ...) return fn(self, Render.canvas(bb), ...) end
end

return Render
