--[[
	Loader.luau

	Builds a world's Instance tree from the Rojo project on disk, following
	Rojo 7 conventions:
	  X.server.luau / X.server.lua  -> Script
	  X.client.luau / X.client.lua  -> LocalScript
	  X.luau / X.lua                -> ModuleScript
	  X.json                        -> ModuleScript returning the decoded table
	  X.txt                         -> StringValue
	  X.model.json                  -> instance(s) described in JSON
	  X.rbxm / X.rbxmx              -> model file (via @lune/roblox)
	  directory                     -> Folder, or the init script's class when it
	                                   contains init.luau / init.server.luau / init.client.luau
	  init.meta.json / X.meta.json  -> className / properties / attributes overrides

	Lune's filesystem API yields to Lune's own scheduler, so every file is read
	up front by Loader.preload() on the main thread; building worlds later only
	touches the in-memory cache.
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Instance = require("./Instance")
local Reflection = require("./Reflection")
local Types = require("./Types")

local Loader = {}

local cache = {} -- root -> { project = table?, files = { [path] = node } }

local function joinPath(a: string, b: string): string
	if a == "" or a == "." then
		return b
	end
	if string.sub(a, -1) == "/" then
		return a .. b
	end
	return a .. "/" .. b
end

local function readTree(path: string)
	if fs.isDir(path) then
		local entries = fs.readDir(path)
		table.sort(entries)
		local children = {}
		for _, name in ipairs(entries) do
			if string.sub(name, 1, 1) ~= "." then
				children[name] = readTree(joinPath(path, name))
			end
		end
		return { kind = "dir", path = path, children = children }
	elseif fs.isFile(path) then
		return { kind = "file", path = path, contents = fs.readFile(path) }
	end
	return nil
end

-- Reads default.project.json (if present) and every referenced $path. Main thread only.
function Loader.preload(root: string)
	if cache[root] then
		return cache[root]
	end
	local entry = { root = root, project = nil, trees = {} }
	local projectPath = joinPath(root, "default.project.json")
	if fs.isFile(projectPath) then
		entry.project = serde.decode("json", fs.readFile(projectPath))
		local function collect(node)
			if type(node) ~= "table" then
				return
			end
			local p = node["$path"]
			if type(p) == "string" and not entry.trees[p] then
				entry.trees[p] = readTree(joinPath(root, p))
			end
			for key, child in pairs(node) do
				if type(key) == "string" and string.sub(key, 1, 1) ~= "$" then
					collect(child)
				end
			end
		end
		collect(entry.project.tree)
	else
		-- Fallback: map src/<ServiceName> directly.
		local srcPath = joinPath(root, "src")
		local tree = {}
		if fs.isDir(srcPath) then
			for _, name in ipairs(fs.readDir(srcPath)) do
				if fs.isDir(joinPath(srcPath, name)) then
					local p = "src/" .. name
					entry.trees[p] = readTree(joinPath(root, p))
					tree[name] = { ["$path"] = p }
				end
			end
		end
		-- StarterPlayerScripts lives below StarterPlayer.
		if tree.StarterPlayer then
			local sp = entry.trees["src/StarterPlayer"]
			tree.StarterPlayer = {}
			if sp and sp.children then
				for childName in pairs(sp.children) do
					local p = "src/StarterPlayer/" .. childName
					entry.trees[p] = readTree(joinPath(root, p))
					tree.StarterPlayer[childName] = { ["$path"] = p }
				end
			end
		end
		entry.project = { name = "fallback", tree = tree }
	end
	cache[root] = entry
	return entry
end

-- Property conversion (Rojo implicit + explicit forms) ---------------------------------------------

local function convertValue(className: string, propName: string, raw: any)
	local member = Reflection.member(className, propName)
	if not member or member.kind ~= "property" then
		return nil, "unknown property"
	end
	local datatype = member.datatype or ""
	local value = raw
	if type(raw) == "table" and not raw[1] then
		local typeName, inner = next(raw)
		if type(typeName) == "string" then
			datatype = if typeName == "Enum" then datatype else typeName
			value = inner
		end
	end
	if string.sub(datatype, 1, 5) == "Enum." then
		local enumName = string.sub(datatype, 6)
		local enum = (roblox.Enum :: any)[enumName]
		if type(value) == "number" then
			for _, item in ipairs(enum:GetEnumItems()) do
				if item.Value == value then
					return item
				end
			end
		elseif type(value) == "string" then
			return enum[value]
		end
		return nil, "bad enum"
	elseif datatype == "Color3" then
		return roblox.Color3.new(value[1], value[2], value[3])
	elseif datatype == "Color3uint8" then
		return roblox.Color3.fromRGB(value[1], value[2], value[3])
	elseif datatype == "Vector3" then
		return roblox.Vector3.new(value[1], value[2], value[3])
	elseif datatype == "Vector2" then
		return roblox.Vector2.new(value[1], value[2])
	elseif datatype == "UDim" then
		return roblox.UDim.new(value[1], value[2])
	elseif datatype == "UDim2" then
		return roblox.UDim2.new(value[1][1], value[1][2], value[2][1], value[2][2])
	elseif datatype == "CFrame" then
		if type(value) == "table" and value.position then
			local p = value.position
			local o = value.orientation
			local cf = roblox.CFrame.new(p[1], p[2], p[3])
			if o then
				cf = roblox.CFrame.fromMatrix(
					cf.Position,
					roblox.Vector3.new(o[1][1], o[2][1], o[3][1]),
					roblox.Vector3.new(o[1][2], o[2][2], o[3][2]),
					roblox.Vector3.new(o[1][3], o[2][3], o[3][3])
				)
			end
			return cf
		end
		return nil, "bad CFrame"
	elseif datatype == "NumberRange" then
		return roblox.NumberRange.new(value[1], value[2])
	elseif datatype == "Bool" or datatype == "String" or datatype == "Content" or datatype == "ContentId" then
		return value
	elseif datatype == "Float32" or datatype == "Float64" or datatype == "Int32" or datatype == "Int64" then
		return value
	end
	if type(value) == "number" or type(value) == "string" or type(value) == "boolean" then
		return value
	end
	return nil, "unsupported datatype " .. datatype
end

local function applyProperties(world, inst, properties, source: string)
	if type(properties) ~= "table" then
		return
	end
	local st = Instance.state(inst)
	for propName, raw in pairs(properties) do
		local value, err = convertValue(st.className, propName, raw)
		if value == nil then
			world:log("warn", string.format("Loader: skipped property %s.%s from %s (%s)", st.className, propName, source, tostring(err)))
		else
			local member = Reflection.member(st.className, propName)
			local ok, coerced = pcall(Reflection.coerce, member, value, Instance.is)
			if ok then
				Instance.setProperty(st, propName, coerced)
			else
				world:log("warn", "Loader: " .. tostring(coerced))
			end
		end
	end
end

local function applyAttributes(inst, attributes)
	if type(attributes) ~= "table" then
		return
	end
	local st = Instance.state(inst)
	for name, value in pairs(attributes) do
		Instance.setAttribute(st, name, value)
	end
end

-- Files -------------------------------------------------------------------------------------------

local SCRIPT_SUFFIXES = {
	{ ".server.luau", "Script" },
	{ ".server.lua", "Script" },
	{ ".client.luau", "LocalScript" },
	{ ".client.lua", "LocalScript" },
	{ ".luau", "ModuleScript" },
	{ ".lua", "ModuleScript" },
}

local function scriptKind(fileName: string): (string?, string?)
	for _, pair in ipairs(SCRIPT_SUFFIXES) do
		local suffix, className = pair[1], pair[2]
		if #fileName > #suffix and string.sub(fileName, -#suffix) == suffix then
			return string.sub(fileName, 1, #fileName - #suffix), className
		end
	end
	return nil, nil
end

local function makeScript(world, className: string, name: string, node)
	local inst = Instance.create(world, className, true)
	local st = Instance.state(inst)
	st.name = name
	st.internal.source = node.contents
	st.internal.path = node.path
	return inst
end

local buildDirectoryChildren

local function fromModelJson(world, data, fallbackName: string)
	local className = data.className or data.ClassName or "Folder"
	local inst = Instance.create(world, className, true)
	local st = Instance.state(inst)
	st.name = data.name or data.Name or fallbackName
	applyProperties(world, inst, data.properties or data.Properties, fallbackName)
	applyAttributes(inst, data.attributes or data.Attributes)
	for _, childData in ipairs(data.children or data.Children or {}) do
		local child = fromModelJson(world, childData, childData.name or childData.Name or "Instance")
		Instance.setParent(Instance.state(child), inst)
	end
	return inst
end

-- Converts a Lune roblox Instance (from a model file) into a mock Instance.
local function fromLuneInstance(world, luneInst)
	local className = luneInst.ClassName
	local inst = Instance.create(world, className, true)
	local st = Instance.state(inst)
	st.name = luneInst.Name
	for _, owner in ipairs(Reflection.chain(className)) do
		local class = Reflection.database:GetClass(owner)
		if class then
			for propName, prop in pairs(class.Properties) do
				if prop.Scriptability == "ReadWrite" and prop.Datatype ~= "Ref" and propName ~= "Parent" and propName ~= "Name" then
					local ok, value = pcall(function()
						return luneInst[propName]
					end)
					if ok and value ~= nil then
						st.props[propName] = value
					end
				end
			end
		end
	end
	if Reflection.isA(className, "LuaSourceContainer") then
		local ok, source = pcall(function()
			return luneInst.Source
		end)
		st.internal.source = if ok then source else ""
		st.internal.path = "model:" .. luneInst.Name
	end
	local okAttr, attrs = pcall(function()
		return luneInst:GetAttributes()
	end)
	if okAttr then
		for k, v in pairs(attrs) do
			st.attributes[k] = v
		end
	end
	for _, child in ipairs(luneInst:GetChildren()) do
		local mock = fromLuneInstance(world, child)
		Instance.setParent(Instance.state(mock), inst)
	end
	return inst
end

local function buildFile(world, fileName: string, node, siblings)
	if string.sub(fileName, -10) == ".meta.json" then
		return nil
	end
	local base, scriptClass = scriptKind(fileName)
	local inst
	if base then
		if base == "init" then
			return nil -- handled by the directory
		end
		inst = makeScript(world, scriptClass :: string, base, node)
	elseif string.sub(fileName, -11) == ".model.json" then
		base = string.sub(fileName, 1, -12)
		inst = fromModelJson(world, serde.decode("json", node.contents), base)
	elseif string.sub(fileName, -5) == ".json" and not string.find(fileName, "%.project%.json$") then
		base = string.sub(fileName, 1, -6)
		inst = Instance.create(world, "ModuleScript", true)
		local st = Instance.state(inst)
		st.name = base
		st.internal.jsonValue = serde.decode("json", node.contents)
		st.internal.path = node.path
	elseif string.sub(fileName, -4) == ".txt" then
		base = string.sub(fileName, 1, -5)
		inst = Instance.create(world, "StringValue", true)
		local st = Instance.state(inst)
		st.name = base
		st.props.Value = node.contents
	elseif string.sub(fileName, -5) == ".rbxm" or string.sub(fileName, -6) == ".rbxmx" then
		local roots = roblox.deserializeModel(node.contents)
		base = string.gsub(fileName, "%.rbxmx?$", "")
		if #roots == 1 then
			inst = fromLuneInstance(world, roots[1])
			Instance.state(inst).name = base
		else
			inst = Instance.create(world, "Folder", true)
			Instance.state(inst).name = base
			for _, r in ipairs(roots) do
				Instance.setParent(Instance.state(fromLuneInstance(world, r)), inst)
			end
		end
	else
		return nil -- unknown file types are ignored like Rojo does
	end
	local meta = siblings[base .. ".meta.json"]
	if meta and meta.kind == "file" then
		local data = serde.decode("json", meta.contents)
		applyProperties(world, inst, data.properties, meta.path)
		applyAttributes(inst, data.attributes)
	end
	return inst
end

local function buildDirectory(world, name: string, node)
	local children = node.children
	local inst
	for _, initName in ipairs({ "init.server.luau", "init.server.lua", "init.client.luau", "init.client.lua", "init.luau", "init.lua" }) do
		local initNode = children[initName]
		if initNode then
			local _, className = scriptKind(initName)
			inst = makeScript(world, className :: string, name, initNode)
			break
		end
	end
	local meta = children["init.meta.json"]
	local metaData = if meta and meta.kind == "file" then serde.decode("json", meta.contents) else nil
	if not inst then
		local className = (metaData and metaData.className) or "Folder"
		inst = Instance.create(world, className, true)
		Instance.state(inst).name = name
	end
	if metaData then
		applyProperties(world, inst, metaData.properties, meta.path)
		applyAttributes(inst, metaData.attributes)
	end
	buildDirectoryChildren(world, inst, node)
	return inst
end

buildDirectoryChildren = function(world, parentInst, node)
	local names = {}
	for childName in pairs(node.children) do
		table.insert(names, childName)
	end
	table.sort(names)
	for _, childName in ipairs(names) do
		local child = node.children[childName]
		local inst
		if child.kind == "dir" then
			inst = buildDirectory(world, childName, child)
		else
			inst = buildFile(world, childName, child, node.children)
		end
		if inst then
			Instance.setParent(Instance.state(inst), parentInst)
		end
	end
end

-- Project nodes --------------------------------------------------------------------------------------

local function buildNode(world, entry, parentInst, key: string, node)
	local className = node["$className"]
	local path = node["$path"]
	local tree = path and entry.trees[path]
	local inst = nil
	local childrenBuilt = false
	local parentState = Instance.state(parentInst)
	if parentState.className == "DataModel" then
		inst = world:service(className or key)
	else
		for _, child in ipairs(parentState.children) do
			if child.name == key then
				inst = child.proxy
				break
			end
		end
		if not inst then
			if tree and tree.kind == "file" then
				inst = buildFile(world, string.match(path, "[^/]+$"), tree, {})
				if inst then
					Instance.state(inst).name = key
				end
				childrenBuilt = true
			elseif tree and tree.kind == "dir" and not className then
				inst = buildDirectory(world, key, tree)
				childrenBuilt = true
			else
				inst = Instance.create(world, className or key, true)
				Instance.state(inst).name = key
			end
			if inst then
				Instance.setParent(Instance.state(inst), parentInst)
			end
		end
	end
	if not inst then
		return
	end
	if tree and tree.kind == "dir" and not childrenBuilt then
		buildDirectoryChildren(world, inst, tree)
	end
	applyProperties(world, inst, node["$properties"], "project " .. key)
	applyAttributes(inst, node["$attributes"])
	for childKey, childNode in pairs(node) do
		if type(childKey) == "string" and string.sub(childKey, 1, 1) ~= "$" and type(childNode) == "table" then
			buildNode(world, entry, inst, childKey, childNode)
		end
	end
	return Instance.state(inst)
end

-- Builds the whole project into `world`. Call Loader.preload(root) on the main thread first.
function Loader.build(world, root: string)
	local entry = cache[root]
	if not entry then
		error("Harness: Loader.preload('" .. root .. "') must run on the main thread before building worlds", 2)
	end
	local tree = entry.project.tree
	for key, node in pairs(tree) do
		if type(key) == "string" and string.sub(key, 1, 1) ~= "$" and type(node) == "table" then
			buildNode(world, entry, world.game, key, node)
		end
	end
end

Loader.convertValue = convertValue
Loader.Types = Types

return Loader
