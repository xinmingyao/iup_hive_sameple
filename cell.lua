local c = require "cell.c"
local csocket = require "cell.c.socket"

local msgpack = require "cell.msgpack"


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

local self = c.self
local system = c.system
win_handle =  c.win_handle
cell.self = self
sraw = require "cell.stable"
sraw.init()  -- init lightuserdata metatable
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

function cell.call(addr, ...)
	-- command
	session = session + 1
	c.send(addr, 2, cell.self, session, ...)
	return select(2,assert(coroutine.yield("WAIT", session)))
end

function cell.rawcall(addr, session, ...)
	c.send(addr, ...)
	return select(2,assert(coroutine.yield("WAIT", session)))
end

function cell.send(addr, ...)
	-- message
	c.send(addr, 3, ...)
end

cell.rawsend = c.send

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

function cell.exit()
	cell.send(system, "kill", self)
	-- no return
	cell.wait(cell.event())
end

function cell.command(cmdfuncs)
	command = cmdfuncs
end

function cell.message(msgfuncs)
	message = msgfuncs
end

function cell.gui(cmdfuncs)
	gui = cmdfuncs
end
local function suspend(source, session, co, ok, op, ...)
	if ok then
		if op == "RETURN" then
			c.send(source, 1, session, true, ...)
		elseif op == "EXIT" then
			-- do nothing
		elseif op == "WAIT" then
			new_task(source, session, co, ...)
		else
			error ("Unknown op : ".. op)
		end
	elseif source then
		c.send(source, 1, session, false, op)
	else
		print(cell.self,op)
		print(debug.traceback(co))
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
	suspend(reply_addr, reply_session, co, coroutine.resume(co, ...))
end

local function deliver_event()
	while next(event_q1) do
		event_q1, event_q2 = event_q2, event_q1
		for i = 1, #event_q2 do
			local ok, err = pcall(resume_co,event_q2[i])
			if not ok then
				print(cell.self,err)
			end
			event_q2[i] = nil
		end
	end
end

function cell.main() end

------------ sockets api ---------------
local sockets = {}
local sockets_event = {}
local sockets_arg = {}
local sockets_closed = {}
local sockets_fd = nil
local sockets_accept = {}
local sockets_udp = {}
local socket = {}
local listen_socket = {}

local rpc = {}
local rpc_head = {}
local function close_msg(self)
	cell.send(sockets_fd, "disconnect", self.__fd)
end

local socket_meta = {
	__index = socket,
	__gc = close_msg,
	__tostring = function(self)
		return "[socket: " .. self.__fd .. "]"
	end,
}

local listen_meta = {
	__index = listen_socket,
	__gc = close_msg,
	__tostring = function(self)
		return "[socket listen: " .. self.__fd .. "]"
	end,
}


--todo:
function listen_socket:disconnect()
	sockets_accept[self.__fd] = nil
	socket.disconnect(self)
end

function cell.connect(addr, port)
	sockets_fd = sockets_fd or cell.cmd("socket")
	local obj = { __fd = assert(cell.call(sockets_fd, "connect", self, addr, port), "Connect failed") }
	return setmetatable(obj, socket_meta)
end

function cell.open(port,accepter)
	sockets_fd = sockets_fd or cell.cmd("socket")
	local obj = { __fd = assert(cell.call(sockets_fd, "open", self, port), "Open failed") }
	sockets_udp[obj.__fd]=function(fd,len,msg,peer_ip,peer_port)
		accepter(fd,len,msg,peer_ip,peer_port)
	end
	return setmetatable(obj, socket_meta)
end

function cell.listen(port, accepter)
	assert(type(accepter) == "function")
	sockets_fd = sockets_fd or cell.cmd("socket")
	local obj = { __fd = assert(cell.call(sockets_fd, "listen", self, port), "Listen failed") }
	sockets_accept[obj.__fd] =  function(fd, addr)
		return accepter(fd, addr, obj)
	end
	return setmetatable(obj, listen_meta)
end

function cell.bind(fd)
	sockets_fd = sockets_fd or cell.cmd("socket")
	local obj = { __fd = fd }
	return setmetatable(obj, socket_meta)
end
function socket:rpc(rpc_funs)
	rpc[self.__fd] = rpc_funs
end
function socket:disconnect()
	assert(sockets_fd)
	local fd = self.__fd
	sockets[fd] = nil
	sockets_closed[fd] = true
	if sockets_event[fd] then
		cell.wakeup(sockets_event[fd])
	end

	cell.send(sockets_fd, "disconnect", fd)
end

function socket:write(msg,...)
	local fd = self.__fd
	local sz,msg=csocket.sendpack(msg)
	cell.rawsend(sockets_fd, 6, fd,sz,msg,...)
end

local function socket_wait(fd, sep)
	assert(sockets_event[fd] == nil)
	sockets_event[fd] = cell.event()
	sockets_arg[fd] = sep
	cell.wait(sockets_event[fd])
end

function socket:readbytes(bytes)
	local fd = self.__fd
	if sockets_closed[fd] then
		sockets[fd] = nil
		return
	end
	if sockets[fd] then
		local data = csocket.pop(sockets[fd], bytes)
		if data then
			return data
		end
	end
	socket_wait(fd, bytes)
	if sockets_closed[fd] then
		sockets[fd] = nil
		return
	end
	return csocket.pop(sockets[fd], bytes)
end

function socket:readline(sep)
	local fd = self.__fd
	if sockets_closed[fd] then
		sockets[fd] = nil
		return
	end
	sep = sep or "\n"
	if sockets[fd] then
		local line = csocket.readline(sockets[fd], sep)
		if line then
			return line
		end
	end
	socket_wait(fd, sep)
	if sockets_closed[fd] then
		sockets[fd] = nil
		return
	end
	return csocket.readline(sockets[fd], sep)
end

----------------------------------------

cell.dispatch {
	id = 7,	-- gui
	dispatch = function(msg,len)
		local pos,rep = binlib.unpack("A"..len,msg,len)
        local info = msgpack:unpack(rep)
        local f = gui[info[2]]
		if f == nil then
			c.post_message(tonumber(info[1]),info[2],{-1,"Unknown gui command " ..  info[2]})
		else
			local co = coroutine.create(function()
                        local t = f(info)
                        --c.post_message(tonumber(info[1]),info[2],t)
                        return "EXIT", t end)
			suspend(source, session, co, coroutine.resume(co,info))
		end
	end
}

cell.dispatch {
	id = 6, -- socket
	dispatch = function(fd, sz, msg,...)
		local accepter = sockets_accept[fd]
		if accepter then
			-- accepter: new fd (sz) ,  ip addr (msg)
			local co = coroutine.create(function()
				local forward = accepter(sz,msg) or self
				cell.call(sockets_fd, "forward", sz , forward)
				return "EXIT"
			end)
			suspend(nil, nil, co, coroutine.resume(co))
			return
		end
		local udp = sockets_udp[fd]
		if udp then
		       udp(fd,sz,msg,...)
		       return
		end
		local ev = sockets_event[fd]
		sockets_event[fd] = nil
		if sz == 0 then
			sockets_closed[fd] = true
			if ev then
				cell.wakeup(ev)
			end
		else
			local buffer, bsz = csocket.push(sockets[fd], msg, sz)
			sockets[fd] = buffer
			if ev then
				local arg = sockets_arg[fd]
				if type(arg) == "string" then
					local line = csocket.readline(buffer, arg, true)
					if line then
						cell.wakeup(ev)
					end
				else
					if bsz >= arg then
						cell.wakeup(ev)
					end
				end
			elseif rpc[fd]  then
				
				if rpc_head[fd] == nil then
					if bsz >=4 then
					
						local head = csocket.pop(sockets[fd], 4)
						local pos,len=binlib.unpack(">I",head)  
						local data = csocket.pop(sockets[fd],len)
						if data then
							rpc_head[fd]  = nil
							local pos,rep = binlib.unpack("A"..len,data)
							local info = msgpack:unpack(rep)
							local fs = rpc[fd]
							local f = fs[info[1]]
							if f then
								f(fd,info)
							else
								error ("UnSupport rpc cmd : " .. info[1])
							end
						else
						    rpc_head[fd]  = len
						end
					end
				else
					local data = csocket.pop(sockets[fd],rpc_head[fd] )
					if data then
						rpc_head[fd]  = nil
						local pos,rep = binlib.unpack("A"..rpc_head[fd],data)
						local info = msgpack:unpack(rep)
						local fs = rpc[fd]
						local f = fs[info[1]]
						print(f)
						if f then
							f(fd,info)
						else
							error ("UnSupport rpc cmd : " .. info[1])
						end
					end
				end
			else
			 -- donothing
			end
		end
	end
}

cell.dispatch {
	id = 5, -- exit
	dispatch = function()
		local err = tostring(self) .. " is dead"
		for event,session in pairs(task_session) do
			local source = task_source[event]
			if source ~= self then
				c.send(source, 1, session, false, err)
			end
		end
	end
}

cell.dispatch {
	id = 4, -- launch
	dispatch = function(source, session, report, ...)
		local op = report and "RETURN" or "EXIT"
		local co = coroutine.create(function(...) return op, cell.main(...) end)
		suspend(source, session, co, coroutine.resume(co,...))
	end
}

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
	dispatch = function(source, session, cmd, ...)
		local f = command[cmd]
		if f == nil then
			c.send(source, 1, session, false, "Unknown command " ..  cmd)
		else
			local co = coroutine.create(function(...) return "RETURN", f(...) end)
			suspend(source, session, co, coroutine.resume(co, ...))
		end
	end
}

cell.dispatch {
	id = 1,	-- response
	dispatch = function (session, ...)
		resume_co(session,...)
	end,
}

c.dispatch(function(p,...)
	local pp = port[p]
	if pp == nil then
		deliver_event()
		error ("Unknown port : ".. p)
	end
	pp.dispatch(...)
	deliver_event()
end)

return cell
