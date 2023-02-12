local MODNAME = "mesecons_luacontroller_block"
local BASENAME = MODNAME..":luacontroller_block"

------------------
--Digiline Rules--
------------------

-- This is a global variable and is used in the section below, so it must be created on top.
local rules = {{
    x = 1,
    y = 0,
    z = 0
}, {
    x = -1,
    y = 0,
    z = 0
}, {
    x = 0,
    y = 1,
    z = 0
}, {
    x = 0,
    y = -1,
    z = 0
}, {
    x = 0,
    y = 0,
    z = 1
}, {
    x = 0,
    y = 0,
    z = -1
}}

-----------------
--Mesecons Code--
-----------------

local ports = {
    a = { --3
        x = 1,
        y = 0,
        z = 0
    },
    b = { --5
        x = 0,
        y = 0,
        z = 1
    },
    c = { --4
        x = -1,
        y = 0,
        z = 0
    },
    d = { --6
        x = 0,
        y = 0,
        z = -1
    },
    e = { --2
        x = 0,
        y = -1,
        z = 0
    },
    f = { --1
        x = 0,
        y = 1,
        z = 0
    }
}

local port_names = {
    ["100"] = "a",
    ["001"] = "b",
    ["-100"] = "c",
    ["00-1"] = "d",
    ["0-10"] = "e",
    ["010"] = "f"
}

local storage = minetest.get_mod_storage()
local luacontroller_blocks = minetest.deserialize(storage:get_string("luacontroller_blocks")) or {}

local save_luablocks = function()
    storage:set_string("luacontroller_blocks", minetest.serialize(luacontroller_blocks))
end

local function set_owner(pos, player)
    local meta = minetest.get_meta(pos)
    meta:set_string("owner", player:get_player_name())
    meta:set_string("infotext", "Owned by "..player:get_player_name())
end

local function get_owner(pos)
    local meta = minetest.get_meta(pos)
    return meta:get_string("owner")
end

local function has_key(player, pos)
    local wielded_item = player:get_wielded_item()
    if wielded_item:get_name() == "default:key" then
        local secret = minetest.get_meta(pos):get_string("secret")
        local key_secret = wielded_item:get_meta():get_string("secret")
        return key_secret == secret
    end
    return false
end

local function is_authorized(player, pos)
    local name = player:get_player_name()
    local owner = get_owner(pos)
    local is_owner = name == owner
    local has_key = has_key(player, pos)
    local has_protection_bypass = minetest.check_player_privs(name, {protection_bypass=true})
    local authorized = is_owner or has_key or has_protection_bypass
    return authorized
end

local get_node_name = function(ports)
    local _port_names = {"a","b","c","d","e","f"}
    local id = ""
    for _, port in pairs(_port_names) do
        if ports[port] == true then
            id = id.."1"
        elseif not ports[port] then
            id = id.."0"
        end
    end
    if id == "000000" then
        return BASENAME
    end
    return BASENAME.."_"..id
end

local get_input_rules = function(node)
    return minetest.registered_nodes[node.name].mesecons.effector.rules
end

local get_output_rules = function(node)
    return minetest.registered_nodes[node.name].mesecons.receptor.rules
end

local get_ports = function(pos, reset)
    local ports = {a=false,b=false,c=false,d=false,e=false,f=false}
    if not reset then
        local output_rules = get_output_rules(minetest.get_node(pos))
        for _, rule in pairs(output_rules) do
            local port_name = port_names[rule.x..rule.y..rule.z]
            ports[port_name] = true
        end
    end
    return ports
end

local get_pins = function(pos)
    return minetest.deserialize(minetest.get_meta(pos):get_string("pins")) or {
        a = false,
        b = false,
        c = false,
        d = false,
        e = false,
        f = false
    }
end

local set_pin = function(pos, rule_name, new_state)
    local pins = get_pins(pos)
    if rule_name then
        local pin_name = port_names[rule_name.x..rule_name.y..rule_name.z]
        if new_state == "off" then
            pins[pin_name] = false
        elseif new_state == "on" then
            pins[pin_name] = true
        end
    end
    minetest.get_meta(pos):set_string("pins", minetest.serialize(pins))
end

local set_new_state = function(pos, _ports, reset)
    local old_ports = get_ports(pos, false)
    local node_name = minetest.get_node(pos).name
    local pins = get_pins(pos)
    for port_name, state in pairs(_ports) do
        if pins[port_name] == true then
            _ports[port_name] = false
        end
    end
    local new_node_name = get_node_name(_ports)
    minetest.swap_node(pos, {name=new_node_name})
    

    if reset then
        mesecon.receptor_on(pos, get_output_rules({name=new_node_name}))
        mesecon.receptor_off(pos, get_input_rules({name=new_node_name}))
    else
        local input_rules = {}
        local output_rules = {}
        local new_ports = get_ports(pos, false)
        local _port_names = {"a","b","c","d","e","f"}
        for _, port_name in pairs(_port_names) do
            --check if port changed
            if new_ports[port_name] ~= old_ports[port_name] then
                local port = new_ports[port_name]
                if port == true and pins[port_name] ~= true then
                    table.insert(output_rules, ports[port_name])
                else
                    table.insert(input_rules, ports[port_name])
                end
            end
        end
        mesecon.receptor_on(pos, output_rules)
        mesecon.receptor_off(pos, input_rules)
    end
end

local interrupts = {}

local initialize_interrupt_pos = function(pos)
    interrupts[minetest.pos_to_string(pos)] = interrupts[minetest.pos_to_string(pos)] or {}
    return interrupts[minetest.pos_to_string(pos)]
end

local _run_upvalue
local perform_interrupt = function(pos, time, iid)
    local intp = initialize_interrupt_pos(pos)
    time = time or 0
    iid = iid or 0
    if not intp[iid] then
        intp[iid] = true
        minetest.after(time, function()
            if luacontroller_blocks[minetest.pos_to_string(pos)] then
                local data = {
                    type = "interrupt",
                    iid = iid
                }
                _run_upvalue(pos, data)
            end
            intp[iid] = nil
        end)
    end
end

local function remove_functions(x)
	local tp = type(x)
	if tp == "function" then
		return nil
	end

	-- Make sure to not serialize the same table multiple times, otherwise
	-- writing mem.test = mem in the Luacontroller will lead to infinite recursion
	local seen = {}

	local function rfuncs(x)
		if x == nil then return end
		if seen[x] then return end
		seen[x] = true
		if type(x) ~= "table" then return end

		for key, value in pairs(x) do
			if type(key) == "function" or type(value) == "function" then
				x[key] = nil
			else
				if type(key) == "table" then
					rfuncs(key)
				end
				if type(value) == "table" then
					rfuncs(value)
				end
			end
		end
	end

	rfuncs(x)

	return x
end

local set_error = function(pos, error)
    local meta = minetest.get_meta(pos)
    meta:set_string("error", error or "")
end

local console_get = function(pos)
    local meta = minetest.get_meta(pos)
    return minetest.deserialize(meta:get_string("console")) or {}
end

local console_set = function(pos, console)
    local meta = minetest.get_meta(pos)
    meta:set_string("console", minetest.serialize(console))
end

local console_write = function(pos, x)
    local console = console_get(pos)
    local _line = tostring(x)
    table.insert(console, _line)
    console_set(pos, console)
end

local console_read = function(pos, n)
    local count = function(t)
        local c = 0
        for _, _ in pairs(t) do
            c = c + 1
        end
        return c
    end
    local console = console_get(pos)
    local last = count(console)
    if n == nil then n = last end
    if type(n) ~= "number" then
        error("number expected, got "..type(n))
    end
    return console[n]
end

local console_clear = function(pos)
    console_set(pos, {})
end

local load_memory = function(pos)
    local meta = minetest.get_meta(pos)
    return minetest.deserialize(meta:get_string("memory")) or {}
end

local save_memory = function(pos, memory)
    local meta = minetest.get_meta(pos)
    remove_functions(memory)
    meta:set_string("memory", minetest.serialize(memory))
end

--------------
--Networking--
--------------

local networks = minetest.deserialize(storage:get_string("networks")) or {}

local function get_network_by_pos(pos)
    for _name, _pos in pairs(networks) do
        if _pos == minetest.pos_to_string(pos) then
            return _name
        end
    end
end

local function unregister_network_at_pos(pos)
    local name = get_network_by_pos(pos)
    if name then
        networks[name] = nil
    end
    storage:set_string("networks", minetest.serialize(networks))
end

local function register_network(pos, name)
    if networks[name] and (get_network_by_pos(pos) ~= name) then
        error("'"..name.."' is already a registered network.")
    end
    unregister_network_at_pos(pos)
    networks[name] = minetest.pos_to_string(pos)
    storage:set_string("networks", minetest.serialize(networks))
end

local response = nil
local function network_set_response(value)
    response = value
end

local function network_send(pos, network, rdata)
    if type(network) ~= "string" then
        error("Invalid input to argument #1; expected string, got "..type(network))
    end
    if type(rdata) ~= "table" then
        error("Invalid input to argument #2; expected table, got "..type(network))
    end
    local hostpos = networks[network]
    if not hostpos then
        return
    else
        hostpos = minetest.string_to_pos(hostpos)
    end
    local client = get_network_by_pos(pos)
    if not client then client = pos end
    --don't send a request to self
    if network == client then
        error("Cannot send a request to self.")
    end
    --form request
    --all values must garenteed a specific type
    local request = {
        client = client,
        url = "",
        headers = {},
        body = rdata.body
    }
    if type(rdata.url) == "string" then request.url = rdata.url end
    if type(rdata.headers) == "table" then request.headers = rdata.headers end
    local data = {
        type = "netrequest",
        msg = request
    }
    _run_upvalue(hostpos, data)
    local _response = response
    response = nil
    return _response
end


---------------
--Environment--
---------------

local function safe_date()
	return(os.date("*t",os.time()))
end

local function safe_string_rep(str, n)
	if #str * n > mesecon.setting("luacontroller_block_string_rep_max", 64000) then
		debug.sethook() -- Clear hook
		error("string.rep: string length overflow", 2)
	end

	return string.rep(str, n)
end

local function safe_string_find(...)
	if (select(4, ...)) ~= true then
		debug.sethook() -- Clear hook
		error("string.find: 'plain' (fourth parameter) must always be true in a Luacontroller")
	end

	return string.find(...)
end

local function get_print(pos)
    local function _print(x)
        console_write(pos, x)
    end
    return _print
end

local function get_clear(pos)
    local function _clear()
        console_clear(pos)
    end
    return _clear
end

local function get_read(pos)
    local function _read(n)
        return console_read(pos, n)
    end
    return _read
end

local function get_interrupt(pos)
    local function _interrupt(time, iid)
        perform_interrupt(pos, time, iid)
    end
    return _interrupt
end

local function get_digiline_send(pos)
    local _digiline_send = function(channel, msg)
        digiline:receptor_send(pos, rules, channel, msg)
    end
    return _digiline_send
end

local function get_network_send(pos)
    local _network_send = function(network, rdata)
        return network_send(pos, network, rdata)
    end
    return _network_send
end

local function get_register_network(pos)
    local _register_network = function(network)
        register_network(pos, network)
    end
    return _register_network
end

local safe_globals = {
	-- Don't add pcall/xpcall unless willing to deal with the consequences (unless very careful, incredibly likely to allow killing server indirectly)
	"assert", "error", "ipairs", "next", "pairs", "select",
	"tonumber", "tostring", "type", "unpack", "_VERSION"
}

-- Allow other mods to add to the environment
local registered_luacontroller_block_modify_environments = {}
local mods_loaded = false

minetest.register_on_mods_loaded(function()
	mods_loaded = true
end)

-- Prevent the function from being called after mods are loaded.
function mesecon.register_luacontroller_block_modify_environment(func)
	if mods_loaded then
		error("This function can only be called when mods are loading.")
	end
	if type(func) == "function" then
		table.insert(registered_luacontroller_block_modify_environments, func)
	end
end

local function create_environment(pos, mem, event)
    local _print = get_print(pos)
    local _interrupt = get_interrupt(pos)
    local _digiline_send = get_digiline_send(pos)
    local _network_send = get_network_send(pos)
    local _register_network = get_register_network(pos)
    local _read = get_read(pos)
    local _clear = get_clear(pos)
	local env = {
        here = pos,
        pin = get_pins(pos),
        port = get_ports(pos, event.type == "program"),
		event = event,
		mem = mem,
		-- heat = mesecon.get_heat(pos),
		-- heat_max = mesecon.setting("overheat_max", 20),
		print = _print,
		interrupt = _interrupt,
		digiline_send = _digiline_send,
        network_send = _network_send,
        register_network = _register_network,
        network_set_response = network_set_response,
        console = {
            print = _print,
            read = _read,
            clear = _clear,
        },
		string = {
			byte = string.byte,
			char = string.char,
			format = string.format,
			len = string.len,
			lower = string.lower,
			upper = string.upper,
			rep = safe_string_rep,
			reverse = string.reverse,
            split = string.split,
			sub = string.sub,
			find = safe_string_find,
            --may or may not exist
            starts_with = string.starts_with,
            ends_with = string.ends_with,
            uid = string.uid
		},
		math = {
			abs = math.abs,
			acos = math.acos,
			asin = math.asin,
			atan = math.atan,
			atan2 = math.atan2,
			ceil = math.ceil,
			cos = math.cos,
			cosh = math.cosh,
			deg = math.deg,
			exp = math.exp,
			floor = math.floor,
			fmod = math.fmod,
			frexp = math.frexp,
			huge = math.huge,
			ldexp = math.ldexp,
			log = math.log,
			log10 = math.log10,
			max = math.max,
			min = math.min,
			modf = math.modf,
			pi = math.pi,
			pow = math.pow,
			rad = math.rad,
			random = math.random,
			sin = math.sin,
			sinh = math.sinh,
			sqrt = math.sqrt,
			tan = math.tan,
			tanh = math.tanh,
		},
		table = {
			concat = table.concat,
			insert = table.insert,
			maxn = table.maxn,
			remove = table.remove,
			sort = table.sort,
		},
		os = {
			clock = os.clock,
			difftime = os.difftime,
			time = os.time,
			datetable = safe_date,
		},
	}
	env._G = env

	for _, name in pairs(safe_globals) do
		env[name] = _G[name]
	end

	-- Modify environment from other mods
	for _, func in pairs(registered_luacontroller_block_modify_environments) do
		func(pos, env)
	end

	return env
end

------------------
-- Luablock Code--
------------------

local function clean_event(event)
    event.channel = event.channel or ""
    --handle event.type
    local msg = event.msg
    if type(event.msg) == "table" then
        event.type = event.type or "action"
        if type(msg.type) == "string" then event.type = msg.type end
    end
end

local timeout = function()
    debug.sethook()
    error("Timed out.")
end

local function create_sandbox(pos, data)
    --load the code into a function and return it
    local event = {
        type = data.type,
        iid = data.iid,
        channel = data.channel,
        msg = data.msg
    }
    clean_event(event)

    local mem = load_memory(pos)
    local env = create_environment(pos, mem, event)
    local code = luacontroller_blocks[minetest.pos_to_string(pos)].code or ""
    
    if code:byte(1) == 27 then
        set_error(pos, "Binary code prohibited.")
        return
    end

    local _sandbox, error = loadstring(code)

    if not _sandbox then
        set_error(pos, tostring(error))
        return
    end

    local function sandbox()
        -- Set hook
        debug.sethook(timeout, "", 45000)

        --Do the actual sandbox first
        
        setfenv(_sandbox, env)
        _sandbox()

        --Remove hook
        debug.sethook()
    
        --Configure stuff after running the code

        -- save memory 
        save_memory(pos, env.mem or {})

        -- set ports
        local reset = env.event.type == "program"
        if env.reset_ports == true then
            reset = true
        end
        set_new_state(pos, env.port or {}, reset)
    end

    return sandbox
end

local function run(pos, data)
    --Do not run if the node is not a lua controller block
    local node = minetest.get_node(pos)
    local nodedef = minetest.registered_nodes[node.name]
    if nodedef.is_luacontroller_block ~= true then
        return
    end

    --Run code
    --Clear the error before the code is loaded and run
    --If there are no errors, then it will still be cleared
    set_error(pos, "")
    local sandbox = create_sandbox(pos, data)
    if type(sandbox) == "function" then
        local result, err = pcall(sandbox)
        debug.sethook() --Remove hook
        if not result then
            set_error(pos, tostring(err))
        end
    end
end

--make 'run' locally available up higher.
_run_upvalue = run

local function set_program(pos)
    local data = {
        type = "program"
    }
    run(pos, data)
end

------------
--Formspec--
------------

-- formspec_version[6]
-- size[16,17]
-- textarea[0.9,0.9;14.2,9.4;code;Code;]
-- label[0.9,10.7;Console]
-- textlist[0.9,10.9;14.2,2;;;1;false]
-- textarea[0.9,13.5;14.2,2;error;Error;]
-- button[3.9,15.7;4,0.8;reset;Reset]
-- button[8.1,15.7;4,0.8;execute;Execute]

local FORMSPEC_BASENAME = MODNAME..":_formspec"

--- Wrapper for 'minetest.formspec_escape'
---@param content string
local function fs_escape(content)
    return minetest.formspec_escape(content)
end

local function get_formspec(pos)
    local node = minetest.get_node(pos)
    local nodedef = minetest.registered_nodes[node.name]
    if nodedef.is_luacontroller_block ~= true then
        return
    end

    local meta = minetest.get_meta(pos)
    local code = luacontroller_blocks[minetest.pos_to_string(pos)].code or ""
    local error = meta:get_string("error")

    local console = console_get(pos)
    local console_items = {}
    for _, item in pairs(console) do
        table.insert(console_items, fs_escape(item))
    end
    console_items = table.concat(console_items, ",")

    local formspec =  "formspec_version[6]"..
        "size[16,17]"..
        "textarea[0.9,0.9;14.2,9.4;code;Code;"..fs_escape(code).."]"..
        "label[0.9,10.7;Console]"..
        "textlist[0.9,10.9;14.2,2;console;"..console_items..";1;false]"..
        "textarea[0.9,13.5;14.2,2;error;Error;"..fs_escape(error).."]"..
        "button[3.9,15.7;4,0.8;reset;Reset]"..
        "button[8.1,15.7;4,0.8;execute;Execute]"

    return formspec
end

local function show_formspec(player, pos)
    local name = player:get_player_name()
    local formspec = get_formspec(pos)
    if formspec then
        local meta = player:get_meta()
        meta:set_string(FORMSPEC_BASENAME.."_pos", minetest.serialize(pos))
        minetest.show_formspec(name, FORMSPEC_BASENAME.."_"..name, formspec)
    end
end

local function show_formspec_if_authorized(player, pos)
    local name = player:get_player_name()
    if is_authorized(player, pos) then
        show_formspec(player, pos)
    else
        minetest.chat_send_player(name, "You cannot view the code of this Lua Controller Block because you do not own it.")
    end
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()
    if formname == FORMSPEC_BASENAME.."_"..name then
        local meta = player:get_meta()
        local pos = minetest.deserialize(meta:get_string(FORMSPEC_BASENAME.."_pos"))
        local node_meta = minetest.get_meta(pos)
        if fields.execute then
            node_meta:set_string("channel", fields.channel)
            luacontroller_blocks[minetest.pos_to_string(pos)].code = fields.code
            save_luablocks()
            set_program(pos)
            show_formspec(player, pos)
        elseif fields.reset then
            console_clear(pos)
            show_formspec(player, pos)
        end
    end
end)

----------------------
--Node Registeration--
----------------------

local nodedef = {
    description = "Lua Controller Block",
    groups = {
        cracky = 3,
        stone = 2,
        oddly_breakable_by_hand = 3,
    },
    digiline = {
        receptor = {},
        wire = {
            rules = rules
        },
        effector = {
            action = function(pos, node, channel, msg)
                local data = {
                    type = "action",
                    channel = channel,
                    msg = msg
                }
                run(pos, data)
            end
        }
    },
    
    is_luacontroller_block = true,

    -- preserve_metadata = preserve_metadata,

    after_place_node = function(pos, placer, itemstack)
        set_owner(pos, placer)
        luacontroller_blocks[minetest.pos_to_string(pos)] = {code=""}
    end,

    -- can_dig = function(pos, player)
    -- end,

    on_rightclick = function(pos, node, clicker, itemstack)
        show_formspec_if_authorized(clicker, pos)
    end,

    after_destruct = function(pos, oldnode)
        luacontroller_blocks[minetest.pos_to_string(pos)] = nil
        unregister_network_at_pos(pos)
    end,

    on_skeleton_key_use = function(pos, user, newsecret)
        local name = user:get_player_name()
        local owner = get_owner(pos)
        local meta = minetest.get_meta(pos)
        local current_secret = meta:get_string("secret")
        local secret
        if name == owner then
            if current_secret == "" then
                secret = newsecret
                current_secret = secret
                meta:set_string("secret", secret)
            end
            secret = current_secret
        else
            minetest.chat_send_player(name, "You do not own this Lua Controller Block.")
        end
        return secret
    end
}

for a = 0, 1 do
    for b = 0, 1 do
    for c = 0, 1 do
    for d = 0, 1 do
    for e = 0, 1 do
    for f = 0, 1 do
      local states = { a=a, b=b, c=c, d=d, e=e, f=f }
      local id = a..b..c..d..e..f
      local name = BASENAME.."_"..id
      if id == "000000" then
          name = BASENAME
      end
      local state = mesecon.state.off
      local paramtype
      local light_source
      local drop
      if id ~= "000000" then
          state = mesecon.state.on
          paramtype = "light"
          light_source = 7
          drop = {
              items = {{
                  items = {BASENAME}
              }}
          }
      end
      local output_rules = {}
      local input_rules = {}
      for port_name, _state in pairs(states) do
        if _state == 0 then
            table.insert(input_rules, ports[port_name])
        elseif _state == 1 then
            table.insert(output_rules, ports[port_name])
        end
      end
      local mesecons = {
            receptor = {
                state = state,
                rules = output_rules
            },
            effector = {
                rules = input_rules,
                action_change = function (pos, node, rule_name, new_state)
                    set_pin(pos, rule_name, new_state)
                    local port = port_names[rule_name.x..rule_name.y..rule_name.z]
                    local data = {
                        type = new_state,
                        msg = {
                            port = port
                        }
                    }
                    run(pos, data)
                end
            }
      }
      -- Textures of node; +Y, -Y, +X, -X, +Z, -Z
      local tiles = {}
      local tile_indexes = {a=3,b=5,c=4,d=6,e=2,f=1}
      for k, v in pairs(states) do
        local tile_index = tile_indexes[k]
        if v == 0 then
            tiles[tile_index] = MODNAME.."_off.png^"..MODNAME.."_port_"..k..".png"
        elseif v == 1 then
            tiles[tile_index] = MODNAME.."_on.png^"..MODNAME.."_port_"..k..".png"
        end
      end
    
      --node definition
      --create a shallow copy of the definition
      local def = {}
      for k, v in pairs(nodedef) do
        def[k] = v
      end
      def.tiles = tiles
      def.paramtype = paramtype
      def.light_source = light_source
      def.drop = drop
      def.mesecons = mesecons
      def.groups = {}
      for k, v in pairs(nodedef.groups) do
        def.groups[k] = v
      end
      if name ~= BASENAME then
          def.groups.not_in_creative_inventory = 1
      end
    
      --register the node here
      minetest.register_node(name, def)
    end
    end
    end
    end
    end
    end

    ------------
    --Crafting--
    ------------

    minetest.register_craft({
        type = "shapeless",
        recipe = {
            "default:mese",
            "mesecons_luacontroller:luacontroller0000"
        },
        output = BASENAME
    })