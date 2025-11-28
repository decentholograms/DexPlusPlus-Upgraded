--[[
	Advanced Script Decompiler & Function Dumper
	Enhanced version with deep analysis capabilities
]]

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
	
	local getgc = getgc or get_gc_objects
	local getupvalues = (debug and debug.getupvalues) or getupvalues or getupvals
	local getconstants = (debug and debug.getconstants) or getconstants or getconsts
	local getinfo = (debug and (debug.getinfo or debug.info)) or getinfo
	local getprotos = (debug and debug.getprotos) or getprotos
	local getstack = (debug and debug.getstack) or getstack
	local getlocals = (debug and debug.getlocals) or getlocals or getlocalvars
	
	local processedObjects = {}
	local functionRegistry = {}
	local stringPatterns = {}
	
	local function smartSerialize(value, depth, maxDepth)
		depth = depth or 0
		maxDepth = maxDepth or 8
		
		if depth > maxDepth then return "..." end
		
		local vType = typeof(value)
		
		if vType == "string" then
			if #value > 200 then
				return string.format('"%s..."', string.sub(value, 1, 197))
			end
			return string.format('"%s"', value:gsub('"', '\\"'))
		elseif vType == "number" then
			if value % 1 == 0 then return tostring(value) end
			return string.format("%.6f", value)
		elseif vType == "boolean" or vType == "nil" then
			return tostring(value)
		elseif vType == "Vector3" then
			return string.format("Vector3.new(%.3f, %.3f, %.3f)", value.X, value.Y, value.Z)
		elseif vType == "Vector2" then
			return string.format("Vector2.new(%.3f, %.3f)", value.X, value.Y)
		elseif vType == "CFrame" then
			return string.format("CFrame.new(%.3f, %.3f, %.3f)", value.X, value.Y, value.Z)
		elseif vType == "Color3" then
			return string.format("Color3.new(%.3f, %.3f, %.3f)", value.R, value.G, value.B)
		elseif vType == "EnumItem" then
			return tostring(value)
		elseif vType == "Instance" then
			return string.format("game.%s", getPath(value) or "Unknown")
		elseif vType == "table" then
			if processedObjects[value] then
				return "{CIRCULAR_REF}"
			end
			processedObjects[value] = true
			
			local items = {}
			local count = 0
			for k, v in pairs(value) do
				count = count + 1
				if count > 50 then
					table.insert(items, "...")
					break
				end
				local key = type(k) == "string" and string.format('["%s"]', k) or string.format("[%s]", tostring(k))
				table.insert(items, string.format("%s = %s", key, smartSerialize(v, depth + 1, maxDepth)))
			end
			
			processedObjects[value] = nil
			return "{" .. table.concat(items, ", ") .. "}"
		else
			return string.format("<%s>", vType)
		end
	end
	
	local function analyzeFunctionBehavior(func)
		local behavior = {
			isCoroutine = false,
			hasYield = false,
			accessesGlobal = false,
			modifiesEnv = false,
			callsGetfenv = false,
			callsSetfenv = false,
			hasMetatable = false
		}
		
		if not getconstants then return behavior end
		
		local constants = getconstants(func)
		for _, const in ipairs(constants) do
			if type(const) == "string" then
				local lower = const:lower()
				if lower:find("wait") or lower:find("yield") then
					behavior.hasYield = true
				end
				if lower:find("getfenv") then
					behavior.callsGetfenv = true
				end
				if lower:find("setfenv") then
					behavior.callsSetfenv = true
				end
				if lower:find("metatable") then
					behavior.hasMetatable = true
				end
			end
		end
		
		return behavior
	end
	
	local function extractStringPatterns(func)
		if not getconstants then return {} end
		
		local patterns = {}
		local constants = getconstants(func)
		
		for _, const in ipairs(constants) do
			if type(const) == "string" and #const > 3 then
				if const:match("^%u[%w_]+$") then
					table.insert(patterns, {type = "IDENTIFIER", value = const})
				elseif const:match("^https?://") then
					table.insert(patterns, {type = "URL", value = const})
				elseif const:match("%d+%.%d+%.%d+") then
					table.insert(patterns, {type = "VERSION", value = const})
				elseif const:match("^[%w_]+%.[%w_]+") then
					table.insert(patterns, {type = "PATH", value = const})
				end
			end
		end
		
		return patterns
	end
	
	local function dumpProtos(func, indent)
		if not getprotos then return "" end
		
		local output = ""
		local protos = getprotos(func)
		
		if #protos > 0 then
			output = output .. string.rep("\t", indent) .. string.format("Nested Functions: %d\n", #protos)
			for i, proto in ipairs(protos) do
				local protoInfo = getinfo(proto)
				local protoName = protoInfo.name ~= "" and protoInfo.name or "anonymous_" .. i
				output = output .. string.rep("\t", indent + 1) .. string.format("[%d] %s\n", i, protoName)
				
				if getupvalues then
					local upvals = getupvalues(proto)
					if next(upvals) then
						output = output .. string.rep("\t", indent + 2) .. "Captured: "
						local captured = {}
						for k, v in pairs(upvals) do
							table.insert(captured, string.format("%s=%s", tostring(k), smartSerialize(v, 0, 3)))
						end
						output = output .. table.concat(captured, ", ") .. "\n"
					end
				end
			end
		end
		
		return output
	end
	
	local function advancedFunctionDump(func, indent, name)
		local output = ""
		local info = getinfo(func)
		local funcName = name or (info.name ~= "" and info.name or "anonymous")
		
		output = output .. string.rep("\t", indent) .. string.format("=== FUNCTION: %s ===\n", funcName)
		output = output .. string.rep("\t", indent) .. string.format("Source: %s:%d\n", info.short_src or "?", info.linedefined or 0)
		output = output .. string.rep("\t", indent) .. string.format("Parameters: %d | Upvalues: %d\n", info.nparams or 0, info.nups or 0)
		
		local behavior = analyzeFunctionBehavior(func)
		local behaviors = {}
		if behavior.hasYield then table.insert(behaviors, "ASYNC") end
		if behavior.callsGetfenv then table.insert(behaviors, "ENV_READ") end
		if behavior.callsSetfenv then table.insert(behaviors, "ENV_WRITE") end
		if behavior.hasMetatable then table.insert(behaviors, "METATABLE") end
		if #behaviors > 0 then
			output = output .. string.rep("\t", indent) .. "Behavior: " .. table.concat(behaviors, " | ") .. "\n"
		end
		
		if getupvalues then
			local upvals = getupvalues(func)
			if next(upvals) then
				output = output .. string.rep("\t", indent) .. "Upvalues:\n"
				for k, v in pairs(upvals) do
					output = output .. string.rep("\t", indent + 1) .. string.format("[%s] %s = %s\n", 
						typeof(k), tostring(k), smartSerialize(v, 0, 4))
				end
			end
		end
		
		if getconstants then
			local consts = getconstants(func)
			if #consts > 0 then
				output = output .. string.rep("\t", indent) .. string.format("Constants (%d):\n", #consts)
				local grouped = {strings = {}, numbers = {}, booleans = {}, other = {}}
				
				for i, const in ipairs(consts) do
					local cType = type(const)
					if cType == "string" then
						table.insert(grouped.strings, const)
					elseif cType == "number" then
						table.insert(grouped.numbers, const)
					elseif cType == "boolean" then
						table.insert(grouped.booleans, const)
					else
						table.insert(grouped.other, const)
					end
				end
				
				if #grouped.strings > 0 then
					output = output .. string.rep("\t", indent + 1) .. "Strings: "
					for i, s in ipairs(grouped.strings) do
						if i > 20 then
							output = output .. string.format("... (%d more)", #grouped.strings - 20)
							break
						end
						output = output .. smartSerialize(s, 0, 2)
						if i < #grouped.strings then output = output .. ", " end
					end
					output = output .. "\n"
				end
				
				if #grouped.numbers > 0 then
					output = output .. string.rep("\t", indent + 1) .. "Numbers: "
					for i, n in ipairs(grouped.numbers) do
						if i > 30 then
							output = output .. string.format("... (%d more)", #grouped.numbers - 30)
							break
						end
						output = output .. tostring(n)
						if i < #grouped.numbers then output = output .. ", " end
					end
					output = output .. "\n"
				end
			end
		end
		
		local patterns = extractStringPatterns(func)
		if #patterns > 0 then
			output = output .. string.rep("\t", indent) .. "Detected Patterns:\n"
			for _, pattern in ipairs(patterns) do
				output = output .. string.rep("\t", indent + 1) .. string.format("[%s] %s\n", pattern.type, pattern.value)
			end
		end
		
		output = output .. dumpProtos(func, indent)
		output = output .. "\n"
		
		return output
	end
	
	ScriptViewer.DumpFunctions = function(scr)
		processedObjects = {}
		functionRegistry = {}
		
		local header = string.format([[

╔════════════════════════════════════════════════════════════════╗
║           ADVANCED FUNCTION DUMP & ANALYSIS                    ║
║  Script: %-53s ║
║  Timestamp: %-50s ║
╚════════════════════════════════════════════════════════════════╝

]], getPath(scr), os.date("%Y-%m-%d %H:%M:%S"))
		
		local dump = header
		local functionCount = 0
		local startTime = tick()
		
		if getgc then
			for _, obj in pairs(getgc()) do
				if typeof(obj) == "function" then
					local success, fenv = pcall(getfenv, obj)
					if success and fenv and fenv.script and fenv.script == scr then
						functionCount = functionCount + 1
						functionRegistry[obj] = functionCount
						dump = dump .. advancedFunctionDump(obj, 0, "func_" .. functionCount)
					end
				end
			end
		end
		
		local endTime = tick()
		local footer = string.format([[

╔════════════════════════════════════════════════════════════════╗
║  Analysis Complete                                             ║
║  Functions Found: %-44d ║
║  Processing Time: %-43.3fs ║
║  Executor: %-51s ║
╚════════════════════════════════════════════════════════════════╝
]], functionCount, endTime - startTime, executorName .. " " .. executorVersion)
		
		dump = dump .. footer
		
		local currentSource = codeFrame:GetText()
		if functionCount > 0 then
			codeFrame:SetText(currentSource .. "\n" .. dump)
		else
			codeFrame:SetText(currentSource .. "\n\nNo functions found for analysis.")
		end
		
		window:Show()
	end

	ScriptViewer.Init = function()
		window = Lib.Window.new()
		window:SetTitle("Advanced Script Viewer")
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
		copy.TextColor3 = env.setclipboard and Color3.new(1,1,1) or Color3.new(0.5,0.5,0.5)
		copy.Interactable = env.setclipboard ~= nil

		copy.MouseButton1Click:Connect(function()
			env.setclipboard(codeFrame:GetText())
		end)

		local save = Instance.new("TextButton",window.GuiElems.Content)
		save.BackgroundTransparency = 1
		save.Size = UDim2.new(0.33,0,0,20)
		save.Position = UDim2.new(0.33,0,0,0)
		save.Text = "Save to File"
		save.TextColor3 = env.writefile and Color3.new(1,1,1) or Color3.new(0.5,0.5,0.5)
		save.Interactable = env.writefile ~= nil

		save.MouseButton1Click:Connect(function()
			local filename = string.format("Place_%d_Script_%d.txt", game.PlaceId, os.time())
			Lib.SaveAsPrompt(filename, codeFrame:GetText())
		end)
		
		dumpbtn = Instance.new("TextButton",window.GuiElems.Content)
		dumpbtn.BackgroundTransparency = 1
		dumpbtn.Position = UDim2.new(0.7,0,0,0)
		dumpbtn.Size = UDim2.new(0.3,0,0,20)
		dumpbtn.Text = "Deep Analysis"
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
			local success, err = pcall(function()
				env.loadstring(codeFrame:GetText())()
			end)
			if not success then
				warn("Execution error:", err)
			end
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
		local startTime = tick()
		local success, source = pcall(env.decompile or function() error("No decompiler") end, scr)

		if not success or not source then
			PreviousScr = nil
			dumpbtn.TextColor3 = Color3.new(0.5,0.5,0.5)
			dumpbtn.Interactable = false
			
			local errorMsg = string.format([[
╔════════════════════════════════════════════════════════════════╗
║  DECOMPILATION FAILED                                          ║
╠════════════════════════════════════════════════════════════════╣
║  Script: %-53s ║
║  Class: %-54s ║
║  RunContext: %-49s ║
╠════════════════════════════════════════════════════════════════╣
║  REASON:                                                       ║
]], getPath(scr), scr.ClassName, tostring(scr.RunContext or "N/A"))

			if (scr.ClassName == "Script" and (scr.RunContext == Enum.RunContext.Legacy or scr.RunContext == Enum.RunContext.Server)) or not scr:IsA("LocalScript") then
				errorMsg = errorMsg .. "║  ServerSide script - Cannot decompile server scripts         ║\n"
			elseif not env.decompile then
				errorMsg = errorMsg .. "║  No decompiler found in executor environment                 ║\n"
			else
				errorMsg = errorMsg .. "║  Unknown error during decompilation                          ║\n"
			end
			
			errorMsg = errorMsg .. string.format([[
╠════════════════════════════════════════════════════════════════╣
║  Executor: %-51s ║
╚════════════════════════════════════════════════════════════════╝
]], executorName .. " " .. executorVersion)

			codeFrame:SetText(errorMsg)
		else
			PreviousScr = scr
			dumpbtn.TextColor3 = Color3.new(1,1,1)
			dumpbtn.Interactable = true

			local decompTime = tick() - startTime
			local header = string.format([[
╔════════════════════════════════════════════════════════════════╗
║  DECOMPILATION SUCCESS                                         ║
╠════════════════════════════════════════════════════════════════╣
║  Script: %-53s ║
║  Time: %-55.3fs ║
║  Executor: %-51s ║
║  Lines: %-54d ║
╚════════════════════════════════════════════════════════════════╝

]], getPath(scr), decompTime, executorName .. " " .. executorVersion, select(2, source:gsub('\n', '\n')) + 1)

			codeFrame:SetText(header .. source)
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
