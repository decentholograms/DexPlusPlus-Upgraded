--[[ 
    Script Viewer App Module (Advanced Build)
    Includes: Improved dump + "Fix Code" button
]]

local Main,Lib,Apps,Settings
local Explorer, Properties, ScriptViewer, Notebook
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main          = data.Main
	Lib           = data.Lib
	Apps          = data.Apps
	Settings      = data.Settings

	API           = data.API
	RMD           = data.RMD
	env           = data.env
	service       = data.service
	plr           = data.plr
	create        = data.create
	createSimple  = data.createSimple
end

local function initAfterMain()
	Explorer   = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook   = Apps.Notebook
end

local executorName, executorVersion = "Unknown", "???"
if identifyexecutor then
	executorName, executorVersion = identifyexecutor()
elseif game:GetService("RunService"):IsStudio() then
	executorName = "Studio"
	executorVersion = version()
end

local function getPath(obj)
	return obj.Parent and Explorer.GetInstancePath(obj) or "Nil parented"
end

local function beautifyCode(src)
	local fixed = src

	fixed = fixed:gsub("\t","    ")
	fixed = fixed:gsub(" +\n","\n")
	fixed = fixed:gsub("\n\n\n+","\n\n")
	fixed = fixed:gsub(";+",";")
	fixed = fixed:gsub(",%s*,",", ")

	fixed = fixed:gsub("(%w+)%s*=%s*function","local %1 = function")

	local indent, buf = 0, {}
	for line in fixed:gmatch("[^\n]+") do
		local trimmed = line:match("^%s*(.-)%s*$")

		if trimmed:match("^end") or trimmed:match("^}") then
			indent = math.max(indent - 1, 0)
		end

		table.insert(buf, string.rep("    ", indent) .. trimmed)

		if trimmed:match("then$") 
		or trimmed:match("do$") 
		or trimmed:match("{$") 
		or trimmed:match("^function") then
			indent += 1
		end
	end

	return table.concat(buf, "\n")
end

local function main()
	local ScriptViewer = {}
	local window, codeFrame
	local execute, clear, dumpBtn, fixBtn
	local previousScript = nil

	ScriptViewer.DumpFunctions = function(scr)
		local getgc    = getgc or get_gc_objects
		local getups   = (debug and debug.getupvalues) or getupvalues
		local getconst = (debug and debug.getconstants) or getconstants
		local getinfo  = (debug and (debug.getinfo or debug.info))
		local getfenv  = getfenv or debug.getfenv

		local header = ("\n-- // Function Dumper (Enhanced)\n-- // Script Path: %s\n\n--[[")
			:format(getPath(scr))

		local dump = header
		local visited = { tables={}, functions={} }

		local function add(str, indent, nl)
			dump = dump .. string.rep("        ", indent) .. str .. ((nl ~= false) and "\n" or "")
		end

		local function safeName(fn)
			local info = getinfo(fn)
			return (info and info.name and info.name ~= "") and info.name or "Unknown"
		end

		local function dumpTable(tbl, indent, label)
			if visited.tables[tbl] then
				add(("(%s) [table] (recursive)"):format(label), indent)
				return
			end
			visited.tables[tbl] = true

			add(("[%s] [table]:"):format(label), indent)
			for k,v in pairs(tbl) do
				local t = typeof(v)
				if t == "table" then
					dumpTable(v, indent+1, k)
				elseif t == "function" then
					add(("[function] = %s"):format(safeName(v)), indent+1)
				else
					add(("[%s] = %s"):format(t, tostring(v)), indent+1)
				end
			end
		end

		local function dumpFunction(fn, indent)
			if visited.functions[fn] then
				add("[function reused] " .. safeName(fn), indent)
				return
			end
			visited.functions[fn] = true

			add("",0)
			add("Function: " .. safeName(fn), indent)

			add("Upvalues:", indent)
			for i,v in ipairs(getups(fn)) do
				local t = typeof(v)
				if t=="table" then dumpTable(v, indent+1, i)
				elseif t=="function" then add(("%d [function] = %s"):format(i,safeName(v)), indent+1)
				else add(("%d [%s] = %s"):format(i,t,tostring(v)), indent+1)
				end
			end

			add("Constants:", indent)
			for i,c in ipairs(getconst(fn)) do
				local t = typeof(c)
				if t=="table" then dumpTable(c, indent+1, i)
				elseif t=="function" then add(("%d [function] = %s"):format(i,safeName(c)), indent+1)
				else add(("%d [%s] = %s"):format(i,t,tostring(c)), indent+1)
				end
			end

			add(("="):rep(100), indent, false)
		end

		for _, obj in ipairs(getgc()) do
			if typeof(obj) == "function" then
				local env = getfenv(obj)
				if env and env.script == scr then
					dumpFunction(obj, 0)
				end
			end
		end

		local source = codeFrame:GetText()
		if dump ~= header then
			source = source .. dump .. "]]"
		end

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
		
		local copy = Instance.new("TextButton", window.GuiElems.Content)
		copy.BackgroundTransparency = 1
		copy.Size = UDim2.new(0.25,0,0,20)
		copy.Text = "Copy"
		copy.Position = UDim2.new(0,0,0,0)
		copy.TextColor3 = env.setclipboard and Color3.new(1,1,1) or Color3.new(.5,.5,.5)
		copy.Interactable = env.setclipboard ~= nil
		copy.MouseButton1Click:Connect(function()
			env.setclipboard(codeFrame:GetText())
		end)

		local save = Instance.new("TextButton", window.GuiElems.Content)
		save.BackgroundTransparency = 1
		save.Size = UDim2.new(0.25,0,0,20)
		save.Position = UDim2.new(0.25,0,0,0)
		save.Text = "Save"
		save.TextColor3 = Color3.new(1,1,1)
		save.MouseButton1Click:Connect(function()
			local src = codeFrame:GetText()
			local filename = ("Place_%s_Script_%s.txt"):format(game.PlaceId, os.time())
			Lib.SaveAsPrompt(filename, src)
		end)

		dumpBtn = Instance.new("TextButton", window.GuiElems.Content)
		dumpBtn.BackgroundTransparency = 1
		dumpBtn.Size = UDim2.new(0.25,0,0,20)
		dumpBtn.Position = UDim2.new(0.5,0,0,0)
		dumpBtn.Text = "Dump"
		dumpBtn.TextColor3 = env.getgc and Color3.new(1,1,1) or Color3.new(.5,.5,.5)
		dumpBtn.Interactable = env.getgc ~= nil
		dumpBtn.MouseButton1Click:Connect(function()
			if previousScript then
				pcall(ScriptViewer.DumpFunctions, previousScript)
			end
		end)

		fixBtn = Instance.new("TextButton", window.GuiElems.Content)
		fixBtn.BackgroundTransparency = 1
		fixBtn.Size = UDim2.new(0.25,0,0,20)
		fixBtn.Position = UDim2.new(0.75,0,0,0)
		fixBtn.Text = "Fix Code"
		fixBtn.TextColor3 = Color3.new(1,1,1)
		fixBtn.MouseButton1Click:Connect(function()
			codeFrame:SetText(beautifyCode(codeFrame:GetText()))
		end)

		execute = Instance.new("TextButton", window.GuiElems.Content)
		execute.BackgroundTransparency = 1
		execute.Size = UDim2.new(0.5,0,0,20)
		execute.Position = UDim2.new(0,0,1,-20)
		execute.Text = "Execute"
		execute.TextColor3 = env.loadstring and Color3.new(1,1,1) or Color3.new(.5,.5,.5)
		execute.Interactable = env.loadstring ~= nil
		execute.MouseButton1Click:Connect(function()
			env.loadstring(codeFrame:GetText())()
		end)

		clear = Instance.new("TextButton", window.GuiElems.Content)
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
		local started = tick()
		local ok,source = pcall(env.decompile or function() end, scr)

		if not ok or not source then
			previousScript = nil
			dumpBtn.TextColor3 = Color3.new(.5,.5,.5)

			local msg = "-- Unable to view source.\n"
			msg = msg .. "-- Script Path: "..getPath(scr).."\n"

			if (scr.ClassName=="Script" and 
				(scr.RunContext==Enum.RunContext.Legacy or scr.RunContext==Enum.RunContext.Server))
				or not scr:IsA("LocalScript") then
				msg = msg .. "-- Reason: script no está en el cliente.\n"
			elseif not env.decompile then
				msg = msg .. "-- Reason: executor sin decompiler.\n"
			end

			msg = msg .. "-- Executor: "..executorName.." ("..executorVersion..")"
			codeFrame:SetText(msg)
			window:Show()
			return
		end

		previousScript = scr
		dumpBtn.TextColor3 = Color3.new(1,1,1)

		local out = "-- Script Path: "..getPath(scr).."\n"
		out = out .. ("-- Took %.2fs to decompile.\n"):format(tick()-started)
		out = out .. "-- Executor: "..executorName.." ("..executorVersion..")\n\n"
		out = out .. source

		codeFrame:SetText(out)
		window:Show()
	end

	return ScriptViewer
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
