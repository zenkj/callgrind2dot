local callgrind_file = nil
local dot_file = nil
local threshold = 1 -- 0~100
local focus_function = nil
local list_functions = false

local match, gmatch = string.match, string.gmatch
local len   = string.len
local assert = assert
local error = error
local tonumber = tonumber

local function usage()
    local arg = arg
    print("Usage:")
    print("    " .. arg[-1] .. " " .. arg[0] .. " [options] callgrind-file")
    print("Options:")
    print("    --list-functions            list all functions mentioned, in this;")
    print("                                case the --threshold is ignored;")
    print("    --threshold=<threshold>     the threshold of Instruction percentage")
    print("                                that function under <threshold>% will not")
    print("                                be generated in the dot file. the range")
    print("                                is 0.0 ~ 100.0, default is 1.0;")
    print("    --focus-funtion=<function>  generate dot file for function")
    print("                                <function> and its caller and callee;")
    print("    --dot-file=<dotfile>        write the output to dot file <dotfile>")
    print("                                default is to write the output to standard")
    print("                                output.")
    os.exit()
end

local function parseargs()
    local i = 1
    local arg = arg
    while arg[i] do
        local a = arg[i]
        local  k,v = a:match("^%-%-([%w%-_]*)=?(.*)$")
        if not k then break end
        if k == "threshold" then
            v = tonumber(v)
            if not v or v < 0 or v > 100 then
                error("invalid threshold value " .. v)
            end
            threshold = v
        elseif k == "focus-function" then
            if not v then
                error("function name should be specified for --focus-function")
            end
            focus_function = v
        elseif k == "dot-file" then
            if not v then
                error("dot file should be specified for --dot-file")
            end
            dot_file = v
        elseif k == "list-functions" then
            list_functions = true
        else
            print("unknown option '" .. k .. "'")
            usage()
        end
        i = i + 1
    end

    if not arg[i] then
        print("a callgrind file should be specified")
        usage()
    end

    callgrind_file = arg[i]
end

parseargs()

local empty_count = 0
local head_count = 0
local spec_count = 0
local cost_count = 0

local id2ob = {}
local id2fl = {}
local id2fn = {}

local FN = {}

local currfnid = 1

local currob, currfl, currfi, currfn, currcob, currcfi, currcfn
local currFN, currcffn
local PID, CMD
local POSITIONS={'line'}
local EVENTS={'Ir', ['Ir'] = 1}
local TOTALS=0

local file

local parse_cost, parse_spec, parse_head

local function packfn(ob, fl, fn)
    return "ob=" .. ob .. ",fl=" .. fl .. ",fn=" .. fn
end

local function unpackfn(fullfn)
    return match(fullfn, "^ob=([^,]+),fl=([^,]+),fn=([^,]+)$")
end

-- jump table for the specification definition
local spec_jtable = {
    ob    = function(id, val)
               if id and val then id2ob[id] = val end
               if id then currob = id2ob[id] end
               if val then currob = val end
            end,
    fl    = function(id, val)
               if id and val then id2fl[id] = val end
               if id then currfl = id2fl[id] end
               if val then currfl = val end
            end,
    fi    = function(id, val)
               if id and val then id2fl[id] = val end
               if id then currfi = id2fl[id] end
               if val then currfi = val end
            end,
    fe    = function(id, val)
               if id and val then id2fl[id] = val end
               if id then currfi = id2fl[id] end
               if val then currfi = val end
            end,
    fn    = function(id, val)
                currfi = nil
                if id and val then id2fn[id] = val end
                if id then currfn = id2fn[id] end
                if val then currfn = val end
                local fullfn = packfn(currob, currfl, currfn)
                currFN = FN[fullfn]
                if not currFN then
                    currFN = {selfcost=0, cost=0, count=0, id=currfnid, callee={}}
                    currfnid = currfnid + 1
                    FN[fullfn] = currFN
                end
            end,
    cob   = function(id, val)
                if id and val then id2ob[id] = val end
                if id then currcob = id2ob[id] end
                if val then currcob = val end
            end,  
    cfi   = function(id, val)
                if id and val then id2fl[id] = val end
                if id then currcfi = id2fl[id] end
                if val then currcfi = val end
            end,  
    cfn   = function(id, val)
                if id and val then id2fn[id] = val end
                if id then currcfn = id2fn[id] end
                if val then currcfn = val end
                currcffn = packfn(currcob or currob, currcfi or currfi or currfl, currcfn)
                currcob = nil
                currcfi = nil
                currcfn = nil
            end,  
    calls = function(id, val)
                assert(id == nil)
                assert(currcalls == nil)
                local count = match(val, "^(%d+)%s.*$")
                assert(count)
                count = tonumber(count)

                assert(currFN and currFN.callee)
                local callee = currFN.callee

                local cost = parse_cost(file:read '*l', false)
                assert(cost, "cost should be specified after calls specification")

                assert(currcffn)
                local cffn = currcffn
                currcffn = nil
                local cfFN = callee[cffn] or {cost=0, count=0}
                local ocost = cfFN.cost
                local ocount = cfFN.count

                cfFN.cost = ocost + cost
                cfFN.count = ocount + count

                callee[cffn] = cfFN
            end
}
spec_jtable.cfl = spec_jtable.cfi

-- jump table for head
local head_jtable = {
    dummy     = function(val) end,
    version   = function(val)
                  if not val or tonumber(val) ~= 1 then
                      error("unsupported version number " .. val)
                  end
                end,
    creator   = function(val)
                  -- creator = callgrind-3.9.0
                end,
    pid       = function(val) PID = val end,
    cmd       = function(val) CMD = val end,
    positions = function(val)
                    local pos = {}
                    for p in gmatch(val, '%w+') do
                        table.insert(pos, p)
                    end
                    if next(pos) then
                        POSITIONS = pos
                    end
                end,
    events    = function(val)
                    local es = {}
                    for e in gmatch(val, '%w+') do
                        table.insert(es, e)
                        if e == 'Ir' then es.Ir = #es end
                    end
                    assert(es.Ir, "No Ir event is specified");
                    EVENTS = es
                end,
    summary   = function(val)
                    val = tonumber(val)
                    TOTALS = val or TOTALS
                end,
}

head_jtable.totals = head_jtable.summary

local function parse_empty(line)
    if match(line, "^%s*$") then
        return true
    elseif match(line, "^%s*#.*$") then
        return true
    else
        return false
    end
end

local function parse_head(line)
    local key, val = match(line, "^(%w+):%s*(.*)$")
    if not key then
        return false
    end

    local f = head_jtable[key] or head_jtable.dummy
    f(val)
    return true
end


function parse_spec(line)
    local key, id, val
    key, id, val = match(line, "^(%a+)=%((%d+)%)%s*(.*)$")
    if not key then
        key, val = match(line, "^(%a+)=%s*(.*)$")
        if not key then
            return false
        end
    end

    if val and len(val) == 0 then
        val = nil
    end

    local f = spec_jtable[key]

    if not f then
        error("unknown specification line " .. line)
    end

    f(id, val)

    return true
end

function parse_cost(line, addtoself)
    local pcount = #POSITIONS
    local ecount = #EVENTS
    local irp = EVENTS.Ir

    local p = 1
    local np
    local n
    for i=1,pcount do
        n, np= match(line, '([%+%-%*xX%x]+)()', p)
        if not n then
            error("invalid position in cost line: " .. line)
        end
        p = np
    end

    for i=1,ecount do
        n, np = match(line, '([xX%x]+)()', p)
        if not n then
            error("invalid position in cost line: " .. line)
        end
        p = np
        if i == irp then
            n = tonumber(n)
            if currFN then
                local cost = currFN.cost or 0
                currFN.cost = cost + n
                if addtoself then
                    local selfcost = currFN.selfcost or 0
                    currFN.selfcost = selfcost + n
                end
            end

            return n
        end
    end
    return nil
end

file = io.open(callgrind_file)

if not file then
    error "can't read callgrind file test.callgrind"
end

for line in file:lines() do
    if parse_empty(line) then
        empty_count = empty_count + 1
    elseif parse_head(line) then
        head_count = head_count + 1
    elseif parse_spec(line) then
        spec_count = spec_count + 1
    elseif parse_cost(line, true) then
        cost_count = cost_count + 1
    else
        local count = empty_count + head_count + spec_count + cost_count + 1
        error("invalid line(" .. count .. "): " .. line)
    end

end

file:close()

for k,v in pairs(FN) do
    for k1,v1 in pairs(v.callee) do
        local fn = FN[k1]
        assert(fn)
        fn.count = fn.count + v1.count
    end
end

for k,v in pairs(FN) do
    local fn = v
    if not fn.count or fn.count == 0 then
        fn.count = 1
    end
end

if dot_file then
    file = io.open(dot_file, "w")
    if not file then error("can't open dot file" .. dot_file) end
else
    file = io.stdout
end

if list_functions then
    file:write("                function      cost      count       object-file      source-file\n")
    for k,v in pairs(FN) do
        local ob, fl, fn = unpackfn(k)
        file:write(string.format("%25s %8.2f/%8.2f %10d %-30s %-30s\n",
                                 fn, v.selfcost*100/TOTALS, v.cost*100/TOTALS, v.count, ob, fl))
    end
    file:close()
    os.exit(0)
end

local function removethreshold()
    for k,v in pairs(FN) do
        if v.cost*100/TOTALS < threshold then
            FN[k] = nil
        end
    end
end

local function filterfocused()
    local focused = {}
    local caller = {}
    local callee = {}
    for k,v in pairs(FN) do
        local ob, fl, fn = unpackfn(k)
        if fn == focus_function then
            focused[k] = v
        end
    end
    for k,v in pairs(FN) do
        for k1,v1 in pairs(v.callee) do
            if focused[k1] and not focused[k] then
                caller[k] = v
            end
        end
    end
    for k,v in pairs(focused) do
        for k1,v1 in pairs(v.callee) do
            if not focused[k1] and not caller[k1] then
                callee[k1] = FN[k1]
            end
        end
    end

    for k,v in pairs(caller) do focused[k] = v end
    for k,v in pairs(callee) do focused[k] = v end

    FN = focused
end

if focus_function then
    filterfocused()
else
    removethreshold()
end

local function getfile(path)
    if not string.match(path, '[/\\]') then
        return path
    end
    local file = string.match(path, '.*[/\\]([^/\\]+)')
    return file
end

local function penwidth(cost)
    local w = cost * 0.05
    if w < 0.1 then w = 0.1 end
    return w
end

file:write("digraph {\n")

for k,v in pairs(FN) do
    local ob, fl, fn = unpackfn(k)
    local sob = getfile(ob)
    local sfl = getfile(fl)
    local selfcost = v.selfcost*100/TOTALS
    local cost = v.cost*100/TOTALS
    local data = string.format('%d [label="%s\\n%s\\n%.2f%% / %.2f%%\\n%d"];\n', v.id, sob, fn, selfcost, cost, v.count)
    file:write(data)

    for k1,v1 in pairs(v.callee) do
        local vv = FN[k1]
        if vv then
            cost = v1.cost*100/TOTALS
            data = string.format('%d -> %d [label="%.2f%%\\n%d", penwidth="%.2f"];\n', v.id, vv.id, cost, v1.count, penwidth(cost))
            file:write(data)
        end
    end
end
file:write("}\n")
file:close()
