local cell = require "cell"
local c = require "cell.c"
local msgpack = require "cell.msgpack"

cell.command {
	login = function(...)
		print("=========login",...)
		return "ok"
	end
}

cell.gui {
	login = function(gui_info) --from cmd tag name pwd
			print("get------",gui_info)
			local handle = gui_info[1]
			c.post_message(tonumber(handle),gui_info[2],{"hello","world"})
			return 
	end
}

function cell.main()
	print("login start")
	local p2p_port = 9999
	cell.open(9997,udp)
	--local p2p = cell.cmd("launch", "ucenter","192.168.203.157",8088,"10.3.0.11",p2p_port)
	--cell.cmd("launch", "p2p","10.3.0.11",p2p_port,p2p)
	--cell.cmd("launch", "desktop_share",11)
	c.register("cell_login")
end
