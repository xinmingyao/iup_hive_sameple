package.path = package.path .. ";.\\backend\\?.lua" .. ";.\\ui\\?.lua"
package.cpath = package.cpath .. ";.\\?.dll"
print(package.cpath)
local hive = require "hive"

hive.start {
	thread = 4,
	main = "login",
	gui = "main_ui",
}

