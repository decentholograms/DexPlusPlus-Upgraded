local Main,Lib,Apps,Settings
local Explorer, Properties, ScriptViewer, Notebook
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings
	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function initAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

local executorName = "Unknown"
local executorVersion = "???"
if identifyexecutor then
	local name,ver = identifyexecutor()
	executorName = name
	executorVersion = ver
elseif game:GetService("RunService"):IsStudio() then
	executorName = "Studio"
	executorVersion = version()
end

local function getPath(obj)
	if obj.Parent == nil then
		return "Nil parented"
	else
		return Explorer.GetInstancePath(obj)
	end
end

local function main()
	local ScriptViewer = {}
	local window, codeFrame
	local execute, clear, dumpbtn
	local PreviousScr = nil
	
	local function advancedDeobfuscate(source)
		if not source then return "" end
		
		local varMap = {}
		local varCounter = {
			gui = 0, frame = 0, button = 0, player = 0, remote = 0,
			obj = 0, value = 0, result = 0, func = 0, tbl = 0,
			str = 0, num = 0, idx = 0
		}
		
		local function inferType(name, context)
			name = name:lower()
			context = (context or ""):lower()
			
			if name:find("frame") or name:find("gui") or context:find("gui") then return "frame" end
			if name:find("btn") or name:find("button") or context:find("button") then return "button" end
			if name:find("player") or name:find("plr") or context:find("player") then return "player" end
			if name:find("remote") or context:find("invokeserver") or context:find("fireserver") then return "remote" end
			if name:find("result") or context:find("invoke") or context:find("fire") then return "result" end
			if name:find("scroll") then return "scroll" end
			if name:find("text") or name:find("box") then return "textbox" end
			if name:find("selected") or name:find("value") then return "value" end
			if name:find("holder") then return "holder" end
			if name:find("template") then return "template" end
			if name:find("arg") then return "arg" end
			if context:find("pairs") or context:find("ipairs") then return "value" end
			
			return "var"
		end
		
		local function cleanVarName(name)
			name = name:gsub("_upvr$", ""):gsub("_upvw$", "")
			name = name:gsub("var%d+_", ""):gsub("var%d+$", "")
			name = name:gsub("^any_", ""):gsub("_result%d*$", "")
			return name
		end
		
		local function getSmartName(oldName, context)
			if varMap[oldName] then return varMap[oldName] end
			
			local cleaned = cleanVarName(oldName)
			local baseType = inferType(cleaned, context)
			
			if cleaned:match("^[iv]_%d+$") then
				if context:find("pairs") or context:find("GetChildren") then
					return "child"
				end
				return "i"
			end
			
			if cleaned:match("^v_%d+") then
				if context:find("GetChildren") then return "child" end
				if context:find("pairs") then return "item" end
				return "value"
			end
			
			if cleaned:find("Redeem") or oldName:find("Redeem") then return "redeemBtn" end
			if cleaned:find("Mod") or oldName:find("Mod") then return "modRemote" end
			if cleaned:find("ScrollingFrame") then return "scrollFrame" end
			if cleaned:find("Frames") then return "frames" end
			
			if cleaned ~= "" and not cleaned:match("^var%d+$") and not cleaned:match("^v_%d+$") then
				varMap[oldName] = cleaned
				return cleaned
			end
			
			varCounter[baseType] = varCounter[baseType] + 1
			local newName = baseType .. varCounter[baseType]
			varMap[oldName] = newName
			return newName
		end
		
		source = source:gsub("%-%- Decompiler.-\n", "")
		source = source:gsub("%-%- Decompiled.-\n", "")
		source = source:gsub("%-%- Luau version.-\n", "")
		source = source:gsub("%-%- Time taken.-\n", "")
		source = source:gsub("%-%- KONSTANTWARNING.-\n", "")
		
		source = source:gsub("local%s+([%w_]+)%s*=%s*([%w_]+)%s*\n%s*local%s+([%w_]+)%s*=%s*%1([^%w_])", function(v1, v2, v3, after)
			return "local " .. v3 .. " = " .. v2 .. after
		end)
		
		local varDecls = {}
		for var in source:gmatch("local%s+([%w_]+_upv[rw])") do
			varDecls[var] = true
		end
		
		for oldVar, _ in pairs(varDecls) do
			local contextLine = source:match("local%s+" .. oldVar:gsub("%-", "%%-") .. "%s*=%s*([^\n]+)")
			local newVar = getSmartName(oldVar, contextLine or "")
			source = source:gsub("%f[%w_]" .. oldVar:gsub("%-", "%%-") .. "%f[^%w_]", newVar)
		end
		
		source = source:gsub("for%s+_%s*,%s+([%w_]+_upv[rw])%s+in%s+pairs%(([^%)]+)%)", function(var, container)
			local newVar = container:find("GetChildren") and "child" or "item"
			return "for _, " .. newVar .. " in pairs(" .. container .. ")"
		end)
		
		source = source:gsub("for%s+([%w_]+_upv[rw])%s*,%s+([%w_]+)%s+in", function(idx, val)
			return "for i, " .. val .. " in"
		end)
		
		source = source:gsub("any_InvokeServer_result(%d*)", "result")
		source = source:gsub("any_(%w+)_result(%d*)", "%1Result")
		
		source = source:gsub("if%s+not%s+([%w_%.]+)%.Value%s+then", "if not %1 then")
		source = source:gsub("([%w_]+)%.Value%s*=%s*true", "%1 = true")
		source = source:gsub("([%w_]+)%.Value%s*=%s*false", "%1 = false")
		source = source:gsub("local%s+([%w_]+)%s*=%s*([%w_%.]+)%.Value", "local %1 = %2")
		
		source = source:gsub("%-%-%[%[%s*Upvalues%[%d+%]:(.-)\n%]%]", "")
		
		source = source:gsub("\n%s*\n%s*\n", "\n\n")
		
		source = source:gsub("local%s+var%d+", function(match)
			return "local var"
		end)
		
		local indentLevel = 0
		local lines = {}
		for line in source:gmatch("[^\n]+") do
			local stripped = line:match("^%s*(.-)%s*$")
			
			if stripped:match("^end") or stripped:match("^else") or stripped:match("^elseif") or stripped:match("^until") then
				indentLevel = math.max(0, indentLevel - 1)
			end
			
			if stripped ~= "" then
				table.insert(lines, string.rep("\t", indentLevel) .. stripped)
			else
				table.insert(lines, "")
			end
			
			if stripped:match("^if ") or stripped:match("^for ") or stripped:match("^while ") or 
			   stripped:match("^function") or stripped:match("then$") or stripped:match("^repeat") or
			   stripped:match("^else$") or stripped:match("^elseif") or stripped:match(" do$") then
				indentLevel = indentLevel + 1
			end
			
			if stripped:match("^end") then
				indentLevel = math.max(0, indentLevel - 1)
			end
		end
		
		source = table.concat(lines, "\n")
		
		return source
	end
	
	ScriptViewer.DumpFunctions = function(scr)
		local getgc = getgc or get_gc_objects
		local getupvalues = (debug and debug.getupvalues) or getupvalues or getupvals
		local getconstants = (debug and debug.getconstants) or getconstants or getconsts
		local getinfo = (debug and (debug.getinfo or debug.info)) or getinfo
		local original = ("\n-- // Function Dumper made by King.Kevin\n-- // Script Path: %s\n\n--[["):format(getPath(scr))
		local dump = original
		local functions, function_count, data_base = {}, 0, {}
		function functions:add_to_dump(str, indentation, new_line)
			local new_line = new_line or true
			dump = dump .. ("%s%s%s"):format(string.rep("		", indentation), tostring(str), new_line and "\n" or "")
		end
		function functions:get_function_name(func)
			local n = getinfo(func).name
			return n ~= "" and n or "Unknown Name"
		end
		function functions:dump_table(input, indent, index)
			local indent = indent < 0 and 0 or indent
			functions:add_to_dump(("%s [%s] %s"):format(tostring(index), tostring(typeof(input)), tostring(input)), indent - 1)
			local count = 0
			for index, value in pairs(input) do
				count = count + 1
				if type(value) == "function" then
					functions:add_to_dump(("%d [function] = %s"):format(count, functions:get_function_name(value)), indent)
				elseif type(value) == "table" then
					if not data_base[value] then
						data_base[value] = true
						functions:add_to_dump(("%d [table]:"):format(count), indent)
						functions:dump_table(value, indent + 1, index)
					else
						functions:add_to_dump(("%d [table] (Recursive table detected)"):format(count), indent)
					end
				else
					functions:add_to_dump(("%d [%s] = %s"):format(count, tostring(typeof(value)), tostring(value)), indent)
				end
			end
		end
		function functions:dump_function(input, indent)
			functions:add_to_dump(("\nFunction Dump: %s"):format(functions:get_function_name(input)), indent)
			functions:add_to_dump(("\nFunction Upvalues: %s"):format(functions:get_function_name(input)), indent)
			for index, upvalue in pairs(getupvalues(input)) do
				if type(upvalue) == "function" then
					functions:add_to_dump(("%d [function] = %s"):format(index, functions:get_function_name(upvalue)), indent + 1)
				elseif type(upvalue) == "table" then
					if not data_base[upvalue] then
						data_base[upvalue] = true
						functions:add_to_dump(("%d [table]:"):format(index), indent + 1)
						functions:dump_table(upvalue, indent + 2, index)
					else
						functions:add_to_dump(("%d [table] (Recursive table detected)"):format(index), indent + 1)
					end
				else
					functions:add_to_dump(("%d [%s] = %s"):format(index, tostring(typeof(upvalue)), tostring(upvalue)), indent + 1)
				end
			end
			functions:add_to_dump(("\nFunction Constants: %s"):format(functions:get_function_name(input)), indent)
			for index, constant in pairs(getconstants(input)) do
				if type(constant) == "function" then
					functions:add_to_dump(("%d [function] = %s"):format(index, functions:get_function_name(constant)), indent + 1)
				elseif type(constant) == "table" then
					if not data_base[constant] then
						data_base[constant] = true
						functions:add_to_dump(("%d [table]:"):format(index), indent + 1)
						functions:dump_table(constant, indent + 2, index)
					else
						functions:add_to_dump(("%d [table] (Recursive table detected)"):format(index), indent + 1)
					end
				else
					functions:add_to_dump(("%d [%s] = %s"):format(index, tostring(typeof(constant)), tostring(constant)), indent + 1)
				end
			end
		end
		for _, _function in pairs(env.getgc()) do
			if typeof(_function) == "function" and getfenv(_function).script and getfenv(_function).script == scr then
				functions:dump_function(_function, 0)
				functions:add_to_dump("\n" .. ("="):rep(100), 0, false)
			end
		end
		local source = codeFrame:GetText()

		if dump ~= original then source = source .. dump .. "]]" end
		codeFrame:SetText(source)
		
		window:Show()
	end

	ScriptViewer.Init = function()
		window = Lib.Window.new()
		window:SetTitle("Notepad")
		window:Resize(500,400)
		ScriptViewer.Window = window

		codeFrame = Lib.CodeFrame.new()
		codeFrame.Frame.Position = UDim2.new(0,0,0,20)
		codeFrame.Frame.Size = UDim2.new(1,0,1,-40)
		codeFrame.Frame.Parent = window.GuiElems.Content
		
		local copy = Instance.new("TextButton",window.GuiElems.Content)
		copy.BackgroundTransparency = 1
		copy.Size = UDim2.new(0.33,0,0,20)
		copy.Position = UDim2.new(0,0,0,0)
		copy.Text = "Copy to Clipboard"
		
		if env.setclipboard then
			copy.TextColor3 = Color3.new(1,1,1)
			copy.Interactable = true
		else
			copy.TextColor3 = Color3.new(0.5,0.5,0.5)
			copy.Interactable = false
		end

		copy.MouseButton1Click:Connect(function()
			local source = codeFrame:GetText()
			env.setclipboard(source)
		end)

		local save = Instance.new("TextButton",window.GuiElems.Content)
		save.BackgroundTransparency = 1
		save.Size = UDim2.new(0.33,0,0,20)
		save.Position = UDim2.new(0.33,0,0,0)
		save.Text = "Save to File"
		save.TextColor3 = Color3.new(1,1,1)
		
		if env.writefile then
			save.TextColor3 = Color3.new(1,1,1)
			save.Interactable = true
		else
			save.TextColor3 = Color3.new(0.5,0.5,0.5)
		end

		save.MouseButton1Click:Connect(function()
			local source = codeFrame:GetText()
			local filename = "Place_"..game.PlaceId.."_Script_"..os.time()..".txt"

			Lib.SaveAsPrompt(filename,source)
		end)
		
		dumpbtn = Instance.new("TextButton",window.GuiElems.Content)
		dumpbtn.BackgroundTransparency = 1
		dumpbtn.Position = UDim2.new(0.7,0,0,0)
		dumpbtn.Size = UDim2.new(0.3,0,0,20)
		dumpbtn.Text = "Dump Functions"
		dumpbtn.TextColor3 = Color3.new(0.5,0.5,0.5)
		
		if env.getgc then
			dumpbtn.TextColor3 = Color3.new(1,1,1)
			dumpbtn.Interactable = true
		else
			dumpbtn.TextColor3 = Color3.new(0.5,0.5,0.5)
			dumpbtn.Interactable = false
		end

		dumpbtn.MouseButton1Click:Connect(function()
			if PreviousScr ~= nil then
				pcall(ScriptViewer.DumpFunctions, PreviousScr)
			end
		end)
		
		execute = Instance.new("TextButton",window.GuiElems.Content)
		execute.BackgroundTransparency = 1
		execute.Size = UDim2.new(0.5,0,0,20)
		execute.Position = UDim2.new(0,0,1,-20)
		execute.Text = "Execute"
		execute.TextColor3 = Color3.new(1,1,1)
		
		if env.loadstring then
			execute.TextColor3 = Color3.new(1,1,1)
			execute.Interactable = true
		else
			execute.TextColor3 = Color3.new(0.5,0.5,0.5)
			execute.Interactable = false
		end

		execute.MouseButton1Click:Connect(function()
			local source = codeFrame:GetText()
			env.loadstring(source)()
		end)

		clear = Instance.new("TextButton",window.GuiElems.Content)
		clear.BackgroundTransparency = 1
		clear.Size = UDim2.new(0.5,0,0,20)
		clear.Position = UDim2.new(0.5,0,1,-20)
		clear.Text = "Clear"
		clear.TextColor3 = Color3.new(1,1,1)

		clear.MouseButton1Click:Connect(function()
			codeFrame:SetText("")
		end)
	end
	
	ScriptViewer.ViewScript = function(scr)
		local oldtick = tick()
		local s,source = pcall(env.decompile or function() end,scr)

		if not s or not source then
			PreviousScr = nil
			dumpbtn.TextColor3 = Color3.new(0.5,0.5,0.5)
			source = "-- Unable to view source.\n"
			source = source .. "-- Script Path: "..getPath(scr).."\n"
			if (scr.ClassName == "Script" and (scr.RunContext == Enum.RunContext.Legacy or scr.RunContext == Enum.RunContext.Server)) or not scr:IsA("LocalScript") then
				source = source .. "-- Reason: The script is not running on client. (attempt to decompile ServerScript or 'Script' with RunContext Server)\n"
			elseif not env.decompile then
				source = source .. "-- Reason: Your executor does not support decompiler. (missing 'decompile' function)\n"
			else
				source = source .. "-- Reason: Unknown\n"
			end
			source = source .. "-- Executor: "..executorName.." ("..executorVersion..")"
		else
			PreviousScr = scr
			dumpbtn.TextColor3 = Color3.new(1,1,1)

			source = advancedDeobfuscate(source)

			local header = "-- Script Path: "..getPath(scr).."\n"
			header = header .. "-- Took "..tostring(math.floor( (tick() - oldtick) * 100) / 100).."s to decompile.\n"
			header = header .. "-- Executor: "..executorName.." ("..executorVersion..")\n\n"

			source = header .. source
		end

		codeFrame:SetText(source)
		window:Show()
	end

	return ScriptViewer
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
