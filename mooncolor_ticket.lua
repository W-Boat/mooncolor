-- 票根页（阅读侧栏 → 阅读票根）出图很慢：每次打开侧栏、切到票根都会离屏重画整张
-- 满屏 PNG（features/lockscreen/render.write：整屏画布 + PNG 编码，Kobo 上要一两秒），
-- 期间界面没有反应。票根内容完全由绘制块决定，块没变时直接沿用上一张图即可。
-- 这里只在「票根」这一条路径上做内容签名缓存，锁屏 / 壁纸的 write 原样放行。
local Ticket = {}

function Ticket.install(Engine, assign)
    local ok, Render = pcall(require, "features.lockscreen.render")
    if not ok or type(Render.write) ~= "function" then return end
    local write = Render.write
    local records = {}

    --- 文件大小 / 修改时间；取不到说明文件不存在。
    ---@param path string
    ---@return number|nil size, number|nil mtime
    local function stat(path)
        local lfs_ok, lfs = pcall(require, "lfs")
        if lfs_ok and lfs and lfs.attributes then
            local ok_attr, attr = pcall(lfs.attributes, path)
            if ok_attr and attr then return attr.size, attr.modification end
            return nil
        end
        local file = io.open(path, "rb")
        if not file then return nil end
        local size = file:seek("end")
        file:close()
        return size
    end

    --- 只把会改变像素的标量字段拼进签名；widget 块（无封面时的纯色封面）由书名、
    --- 作者决定，而这两项本来就在文字块里，所以只需记尺寸。
    ---@param background table|nil
    ---@param blocks table[]
    ---@param fill any
    ---@return string|nil
    local function signature(background, blocks, fill)
        if background ~= nil then return nil end
        local screen=require("device").screen
        local parts = { tostring(fill),tostring(screen:getWidth()),tostring(screen:getHeight()),tostring(Engine.revision) }
        local function add(v)
            local text=tostring(v)
            parts[#parts+1]=#text..":"..text
        end
        for i = 1, #blocks do
            local block = blocks[i]
            local keys={}
            for key in pairs(block)do if key~="widget"then keys[#keys+1]=key end end
            table.sort(keys)
            for _,key in ipairs(keys)do
                local value=block[key]
                if type(value)=="table"or type(value)=="function"then return nil end
                add(key);add(value)
            end
            if block.file then local size,mtime=stat(block.file);add(size);add(mtime)end
            if block.widget then
                local w=block.widget
                -- Only plain fallback covers have a stable, known description.
                if type(w.title)~="string"then return nil end
                add(w.title);add(w.author);add(w.width);add(w.height)
            end
            -- Delimiters in user text cannot collide with length-prefixed fields.
            add(i)
        end
        return table.concat(parts, "\30")
    end

    --- 复用缓存时也要释放这次新建的离屏 widget（原 write 会统一 free）。
    ---@param blocks table[]
    local function freeWidgets(blocks)
        local seen = {}
        for i = 1, #blocks do
            local widget = blocks[i].widget
            if widget and not seen[widget] and type(widget.free) == "function" then
                seen[widget] = true
                widget:free()
            end
        end
    end

    assign(Render, "write", function(path, background, blocks, fill)
        local conf = Engine.config()
        if not conf.enabled or not conf.fast_ticket or type(path) ~= "string"
            or not path:find("ticket%.png$") or type(blocks) ~= "table" then
            return write(path, background, blocks, fill)
        end
        local sig = signature(background, blocks, fill)
        local record = records[path]
        if sig and record and record.sig == sig then
            local size, mtime = stat(path)
            if size and size == record.size and (mtime == nil or mtime == record.mtime) then
                Engine.coverage.ticket_reuse = (Engine.coverage.ticket_reuse or 0) + 1
                freeWidgets(blocks)
                return true
            end
        end
        local ok_write, err = write(path, background, blocks, fill)
        if ok_write and sig then
            local size, mtime = stat(path)
            if size then records[path] = { sig = sig, size = size, mtime = mtime } end
        else
            records[path] = nil
        end
        return ok_write, err
    end)
    Engine.coverage.ticket = true
end

return Ticket
