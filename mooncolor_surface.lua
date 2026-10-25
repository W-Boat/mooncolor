-- A child wholly inside a rounded surface cannot overwrite its outer corners.
-- In that case avoid Moon's per-pixel corner snapshots and restores altogether.
local Surface={}
function Surface.wrap(original,Engine,Theme,BB)
    return function(self,bb,x,y)
        if not Engine.config().enabled or not Engine.config().fast_panels then
            return original(self,bb,x,y)
        end
        local child=self[1]
        local s,w,h=self.style,self.box_w,self.box_h
        local r=math.min(Theme.px(s.radius or 0),math.floor(math.min(w,h)/2))
        if not child or r<=0 or (s.bg and self.bg_alpha and self.bg_alpha<100) then
            return original(self,bb,x,y)
        end
        local size=child:getSize()
        local cx,cy=math.floor((w-size.w)/2),math.floor((h-size.h)/2)
        if cx<0 or cy<0 or size.w<=0 or size.h<=0 then return original(self,bb,x,y) end
        local dx=math.max(r-cx,cx+size.w-1-(w-1-r),0)
        local dy=math.max(r-cy,cy+size.h-1-(h-1-r),0)
        if dx*dx+dy*dy>r*r then
            return original(self,bb,x,y)
        end
        self.dimen.x,self.dimen.y=x,y
        if self.shadow>0 then
            bb:paintRoundedRect(x+self.shadow,y+self.shadow,w,h,BB.Color8(s.shadow_color),r)
        end
        if s.bg then bb:paintRoundedRect(x,y,w,h,BB.Color8(s.bg),r) end
        local border=Theme.px(s.border or 0)
        if border>0 then bb:paintBorder(x,y,w,h,border,BB.Color8(s.border_color),r,
            G_reader_settings:nilOrTrue("anti_alias_ui")) end
        return child:paintTo(bb,x+cx,y+cy)
    end
end
return Surface
