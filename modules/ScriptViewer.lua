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
	local execute, clear, dumpbtn, beautifyBtn
	local PreviousScr = nil
	
	local getgc = getgc or get_gc_objects
	local getupvalues = (debug and debug.getupvalues) or getupvalues or getupvals
	local getconstants = (debug and debug.getconstants) or getconstants or getconsts
	local getinfo = (debug and (debug.getinfo or debug.info)) or getinfo
	local getprotos = (debug and debug.getprotos) or getprotos
	local setconstant = (debug and debug.setconstant) or setconstant or setconst
	local setupvalue = (debug and debug.setupvalue) or setupvalue or setupval
	
	local processedFuncs = {}
	local varNameMap = {}
	local varCounter = 0
	
	local function generateVarName(prefix)
		varCounter = varCounter + 1
		return prefix .. varCounter
	end
	
	local function smartClean(str)
		if not str or type(str) ~= "string" then return str end
		str = str:gsub("_upvr$", ""):gsub("_upvw$", "")
		str = str:gsub("var%d+_upvr$", ""):gsub("var%d+_upvw$", "")
		str = str:gsub("^any_", ""):gsub("_result%d*$", "")
		if str:match("^[iv]_%d+$") then
			return "index"
		end
		if str:match("^v_%d+$") then
			return "value"
		end
		return str
	end
	
	local function inferVarType(value, name)
		local vtype = typeof(value)
		name = name or ""
		
		if vtype == "Instance" then
			local className = value.ClassName
			if className:find("Frame") or className:find("GUI") then
				return "gui"
			elseif className:find("Part") or className:find("Model") then
				return "obj"
			elseif className:find("Player") then
				return "player"
			elseif className:find("Remote") then
				return "remote"
			end
			return "inst"
		elseif vtype == "function" then
			return "func"
		elseif vtype == "table" then
			return "tbl"
		elseif vtype == "string" then
			return "str"
		elseif vtype == "number" then
			return "num"
		elseif vtype == "boolean" then
			return "bool"
		end
		
		return "var"
	end
	
	local function analyzeFunction(func)
		if not func or processedFuncs[func] then return nil end
		processedFuncs[func] = true
		
		local analysis = {
			upvalues = {},
			constants = {},
			protos = {},
			behavior = {},
			purpose = "unknown"
		}
		
		if getupvalues then
			local upvals = getupvalues(func)
			for k, v in pairs(upvals) do
				local cleanName = smartClean(tostring(k))
				local inferredType = inferVarType(v, cleanName)
				analysis.upvalues[cleanName] = {
					value = v,
					type = typeof(v),
					inferredName = inferredType .. "_" .. cleanName
				}
			end
		end
		
		if getconstants then
			local consts = getconstants(func)
			for i, const in ipairs(consts) do
				if type(const) == "string" then
					table.insert(analysis.constants, const)
					local lower = const:lower()
					if lower:find("remote") or lower:find("invoke") or lower:find("fire") then
						table.insert(analysis.behavior, "REMOTE_CALL")
					end
					if lower:find("player") or lower:find("character") then
						table.insert(analysis.behavior, "PLAYER_RELATED")
					end
					if lower:find("gui") or lower:find("frame") or lower:find("button") then
						table.insert(analysis.behavior, "GUI_RELATED")
					end
					if lower:find("ban") or lower:find("kick") or lower:find("admin") then
						table.insert(analysis.behavior, "ADMIN_ACTION")
					end
				end
			end
		end
		
		if getprotos then
			local protos = getprotos(func)
			for i, proto in ipairs(protos) do
				table.insert(analysis.protos, proto)
			end
		end
		
		if #analysis.behavior > 0 then
			if table.find(analysis.behavior, "REMOTE_CALL") then
				analysis.purpose = "RemoteHandler"
			elseif table.find(analysis.behavior, "GUI_RELATED") then
				analysis.purpose = "UIHandler"
			elseif table.find(analysis.behavior, "ADMIN_ACTION") then
				analysis.purpose = "AdminAction"
			end
		end
		
		return analysis
	end
	
	local function deobfuscateCode(source)
		if not source then return "" end
		
		local replacements = {}
		
		replacements["_upvr"] = ""
		replacements["_upvw"] = ""
		replacements["var%d+"] = "var"
		
		for pattern, replacement in pairs(replacements) do
			source = source:gsub(pattern, replacement)
		end
		
		source = source:gsub("local%s+([%w_]+)%s*=%s*([%w_]+)%s*\n%s*local%s+([%w_]+)%s*=%s*%1", function(var1, var2, var3)
			return "local " .. var3 .. " = " .. var2
		end)
		
		source = source:gsub("if%s+not%s+([%w_%.]+)%.Value%s+then", "if not %1 then")
		source = source:gsub("([%w_]+)%.Value%s*=%s*true", "%1 = true")
		source = source:gsub("([%w_]+)%.Value%s*=%s*false", "%1 = false")
		
		source = source:gsub("for%s+_%s*,%s*v_%d+", "for _, value")
		source = source:gsub("for%s+i_%d+", "for i")
		
		source = source:gsub("any_InvokeServer_result%d*", "result")
		
		local functionNames = {}
		for name in source:gmatch("function%s+([%w_]+)%s*%(") do
			if not functionNames[name] and name:match("^var%d+") then
				local newName = "func_" .. (#functionNames + 1)
				functionNames[name] = newName
			end
		end
		
		for oldName, newName in pairs(functionNames) do
			source = source:gsub(oldName, newName)
		end
		
		return source
	end
	
	ScriptViewer.DumpFunctions = function(scr)
		processedFuncs = {}
		varNameMap = {}
		varCounter = 0
		
		local output = "\n"
		local functionCount = 0
		
		if getgc then
			for _, obj in pairs(getgc()) do
				if typeof(obj) == "function" then
					local success, fenv = pcall(getfenv, obj)
					if success and fenv and fenv.script and fenv.script == scr then
						functionCount = functionCount + 1
						local analysis = analyzeFunction(obj)
						
						if analysis then
							output = output .. string.format("Function %d [%s]:\n", functionCount, analysis.purpose)
							
							if next(analysis.upvalues) then
								output = output .. "  Upvalues:\n"
								for name, data in pairs(analysis.upvalues) do
									output = output .. string.format("    %s [%s]\n", data.inferredName, data.type)
								end
							end
							
							if #analysis.constants > 0 then
								output = output .. "  Key Strings: "
								local shown = 0
								for _, const in ipairs(analysis.constants) do
									if shown < 5 and #const > 3 and #const < 50 then
										output = output .. '"' .. const .. '", '
										shown = shown + 1
									end
								end
								output = output .. "\n"
							end
							
							if #analysis.protos > 0 then
								output = output .. string.format("  Nested Functions: %d\n", #analysis.protos)
							end
							
							output = output .. "\n"
						end
					end
				end
			end
		end
		
		output = output .. string.format("\nTotal Functions: %d\nScript: %s\n", functionCount, getPath(scr))
		
		local currentSource = codeFrame:GetText()
		codeFrame:SetText(currentSource .. "\n" .. output)
		window:Show()
	end
	
	ScriptViewer.BeautifyCode = function()
		local source = codeFrame:GetText()
		local deobfuscated = deobfuscateCode(source)
		codeFrame:SetText(deobfuscated)
	end

	ScriptViewer.Init = function()
		window = Lib.Window.new()
		window:SetTitle("Script Viewer")
		window:Resize(500,400)
		ScriptViewer.Window = window

		codeFrame = Lib.CodeFrame.new()
		codeFrame.Frame.Position = UDim2.new(0,0,0,40)
		codeFrame.Frame.Size = UDim2.new(1,0,1,-60)
		codeFrame.Frame.Parent = window.GuiElems.Content
		
		local copy = Instance.new("TextButton",window.GuiElems.Content)
		copy.BackgroundTransparency = 1
		copy.Size = UDim2.new(0.2,0,0,20)
		copy.Position = UDim2.new(0,0,0,0)
		copy.Text = "Copy"
		copy.TextColor3 = env.setclipboard and Color3.new(1,1,1) or Color3.new(0.5,0.5,0.5)
		copy.Interactable = env.setclipboard ~= nil

		copy.MouseButton1Click:Connect(function()
			env.setclipboard(codeFrame:GetText())
		end)

		local save = Instance.new("TextButton",window.GuiElems.Content)
		save.BackgroundTransparency = 1
		save.Size = UDim2.new(0.2,0,0,20)
		save.Position = UDim2.new(0.2,0,0,0)
		save.Text = "Save"
		save.TextColor3 = env.writefile and Color3.new(1,1,1) or Color3.new(0.5,0.5,0.5)
		save.Interactable = env.writefile ~= nil

		save.MouseButton1Click:Connect(function()
			local filename = string.format("Script_%d.lua", os.time())
			Lib.SaveAsPrompt(filename, codeFrame:GetText())
		end)
		
		beautifyBtn = Instance.new("TextButton",window.GuiElems.Content)
		beautifyBtn.BackgroundTransparency = 1
		beautifyBtn.Position = UDim2.new(0.4,0,0,0)
		beautifyBtn.Size = UDim2.new(0.2,0,0,20)
		beautifyBtn.Text = "Beautify"
		beautifyBtn.TextColor3 = Color3.new(1,1,1)

		beautifyBtn.MouseButton1Click:Connect(function()
			ScriptViewer.BeautifyCode()
		end)
		
		dumpbtn = Instance.new("TextButton",window.GuiElems.Content)
		dumpbtn.BackgroundTransparency = 1
		dumpbtn.Position = UDim2.new(0.6,0,0,0)
		dumpbtn.Size = UDim2.new(0.2,0,0,20)
		dumpbtn.Text = "Analyze"
		dumpbtn.TextColor3 = env.getgc and Color3.new(1,1,1) or Color3.new(0.5,0.5,0.5)
		dumpbtn.Interactable = env.getgc ~= nil

		dumpbtn.MouseButton1Click:Connect(function()
			if PreviousScr then
				pcall(ScriptViewer.DumpFunctions, PreviousScr)
			end
		end)
		
		execute = Instance.new("TextButton",window.GuiElems.Content)
		execute.BackgroundTransparency = 1
		execute.Size = UDim2.new(0.5,0,0,20)
		execute.Position = UDim2.new(0,0,1,-20)
		execute.Text = "Execute"
		execute.TextColor3 = env.loadstring and Color3.new(1,1,1) or Color3.new(0.5,0.5,0.5)
		execute.Interactable = env.loadstring ~= nil

		execute.MouseButton1Click:Connect(function()
			pcall(function()
				env.loadstring(codeFrame:GetText())()
			end)
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
		local success, source = pcall(env.decompile or function() error("No decompiler") end, scr)

		if not success or not source then
			PreviousScr = nil
			dumpbtn.TextColor3 = Color3.new(0.5,0.5,0.5)
			dumpbtn.Interactable = false
			
			local errorMsg = "Failed to decompile script\n"
			errorMsg = errorMsg .. "Path: " .. getPath(scr) .. "\n"
			errorMsg = errorMsg .. "Class: " .. scr.ClassName .. "\n"
			
			if (scr.ClassName == "Script" and (scr.RunContext == Enum.RunContext.Legacy or scr.RunContext == Enum.RunContext.Server)) or not scr:IsA("LocalScript") then
				errorMsg = errorMsg .. "Reason: ServerSide script\n"
			elseif not env.decompile then
				errorMsg = errorMsg .. "Reason: No decompiler available\n"
			else
				errorMsg = errorMsg .. "Reason: Unknown error\n"
			end
			
			errorMsg = errorMsg .. "Executor: " .. executorName .. " " .. executorVersion

			codeFrame:SetText(errorMsg)
		else
			PreviousScr = scr
			dumpbtn.TextColor3 = Color3.new(1,1,1)
			dumpbtn.Interactable = true

			local cleaned = deobfuscateCode(source)
			codeFrame:SetText(cleaned)
		end

		window:Show()
	end

	return ScriptViewer
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
