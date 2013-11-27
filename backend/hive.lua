local c = require "hivecore"

local system_cell = assert(package.searchpath("hive.system", package.path),"system cell was not found")

local hive = {}

function hive.start(t)
	local main = assert(package.searchpath(t.main, package.path), "main cell was not found")
	local gui = package.searchpath(t.gui, package.path)
	print(c,main,gui)
	if gui then
		return c.start(t, system_cell, main,gui)
	else
		return c.start(t, system_cell, main)
	end
end

return hive
