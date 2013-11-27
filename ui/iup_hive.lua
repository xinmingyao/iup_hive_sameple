local c = require "cell.c"
local iuplua = require "iuplua52"

local coroutine = coroutine
local assert = assert
local select = select
local table = table
local next = next
local pairs = pairs
local type = type

local session = 0
local port = {}
local task_coroutine = {}
local task_session = {}
local task_source = {}
local command = {}
local message = {}
local gui = {}
local cell = {}


local event_q1 = {}
local event_q2 = {}

local function new_task(source, session, co, event)
	task_coroutine[event] = co
	task_session[event] = session
	task_source[event] = source
end




function cell.fork(f)
	local co = coroutine.create(function() f() return "EXIT" end)
	session = session + 1
	new_task(nil, nil, co, session)
	cell.wakeup(session)
end

function cell.timeout(ti, f)
	local co = coroutine.create(function() f() return "EXIT" end)
	session = session + 1
	c.send(system, 2, self, session, "timeout", ti)
	new_task(nil, nil, co, session)
end

function cell.sleep(ti)
	session = session + 1
	c.send(system, 2, self, session, "timeout", ti)
	coroutine.yield("WAIT", session)
end

function cell.wakeup(event)
	table.insert(event_q1, event)
end

function cell.event()
	session = session + 1
	return session
end

function cell.wait(event)
	coroutine.yield("WAIT", event)
end

function cell.call(handle,addr, ...)
	-- command
	local source =iup.ihandle_toint(handle)
	session = session + 1
	c.iup_send(addr, 2, source, session, ...)
	return select(2,assert(coroutine.yield("WAIT", session)))
end


function cell.send(addr, ...)
	-- message
	c.send(addr, 3, ...)
end

cell.rawsend = c.send

function cell.register(handle)

end
function cell.dispatch(p)
	local id = assert(p.id)
	if p.replace then
		assert(port[id])
	else
		assert(port[id] == nil)
	end
	port[id] = p
end

function cell.cmd(...)
	return cell.call(system, ...)
end



function cell.command(cmdfuncs)
	command = cmdfuncs
end

function cell.message(msgfuncs)
	message = msgfuncs
end


local function suspend(source, session, co, ok, op,...)
	print("suspend:",ok,op)
	if ok then
		if op == "RETURN" then
			--c.send(source, 1, session, true, ...)
		elseif op == "EXIT" then
			-- donothing
		elseif op == "WAIT" then
			new_task(source, session, co,...)
		else
			print("Unknown op : "..op)
		end
	else
		print("dddddd")
	end
end

local function resume_co(session, ...)
	local co = task_coroutine[session]
	if co == nil then
		error ("Unknown response : " .. tostring(session))
	end
	local reply_session = task_session[session]
	local reply_addr = task_source[session]
	task_coroutine[session] = nil
	task_session[session] = nil
	task_source[session] = nil
	suspend(reply_addr, reply_session, co, coroutine.resume(co,...))
end



function cell.spawn(f)
	local co = coroutine.create(function() f() return "EXIT" end)
	suspend(nil, nil, co, coroutine.resume(co))
end

----------------------------------------


cell.dispatch {
	id = 3, -- message
	dispatch = function(cmd, ...)
		local f = message[cmd]
		if f == nil then
			print("Unknown message ", cmd)
		else
			local co = coroutine.create(function(...) return "EXIT", f(...) end)
			suspend(source, session, co, coroutine.resume(co,...))
		end
	end
}

cell.dispatch {
	id = 2,	-- command
	dispatch = function(from,port,source, session, cmd, ...)
		resume_co(session,...)
	end
}

cell.dispatch {
	id = 1,	-- response
	dispatch = function (source,port,session,...)
		resume_co(session,...)
	end,
}

iup.dispatch(function(...)
	local h,d,p = ...
	print("dispatch:",c.data_unpack(d))
	local pp = port[p]
	if pp == nil then
		error ("Unknown port : ".. p)
	end
	pp.dispatch(c.data_unpack(d))
end)

return cell
