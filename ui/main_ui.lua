local require = require
local iup_hive = require "iup_hive"
local iuplua = require "iuplua52"
print("start gui")
text_location = iup.text{expand="HORIZONTAL", id="text_location"}
btn_browse = iup.button{title="µã»÷", rastersize="x22",id="btn_browse" ,bgcolor = "0 255 0"}
pic = iup.button{size="100x100",title="hello world!"}

vbox = iup.vbox
    {
        pic,
        iup.hbox
        {
            text_location,
            btn_browse
            ; margin="0x0"
        },
        iup.label{title="Text:"},
        iup.multiline{expand="YES"},
		
    }
dlg = iup.dialog
{
    vbox
    ;title="iuplua sample", size="300x200", margin="0x0",maxbox="true"
}

function pic:action()
iup.Message('dddddd','sdl')

end

function btn_browse:action()
	iup_hive.spawn(function()
			local r = iup_hive.call(dlg,"cell_login","login","name","pwd")
			if r == "ok" then		
				iup.Message('YourApp','Login ok!')
			else
				iup.Message('YourApp','Login failure!')
			end
		end
		)
end

function dlg.hivemessage_cb(...)	
end 

dlg:show()

iup.MainLoop()