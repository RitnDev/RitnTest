---------------------------------------------------------------------------------------------
-- RITNTEST : INTERFACE
---------------------------------------------------------------------------------------------
-- FR : Interface de test générique, chargée par le mod testé dans sa propre VM Lua :
--        if script.active_mods["RitnTest"] then require("__RitnTest__.interface") end
--      (à placer au chargement du control.lua du mod testé, pas dans un évènement).
--      Elle ajoute l'interface remote « RitnTest_<mod> », appelée par RCON (tools/rcon.py), qui :
--        - envoie de faux évènements GUI (clic, case, texte, sélection, curseur, onglet, fermeture)
--          et de faux raccourcis aux gestionnaires du mod, retrouvés par script.get_event_handler :
--          c'est le même code qu'un vrai clic, sur de vrais éléments ;
--        - décrit l'arbre GUI d'un joueur (noms, types, légendes, styles, tags...) ;
--        - prend une capture d'écran avec l'interface (script-output/RitnTest/) ;
--        - évalue une expression Lua dans la VM du mod (ex. lire son storage).
--      Ne fait rien tant qu'un mod ne le charge pas. Outil de développement : jamais publié.
-- EN : Generic test interface, loaded by the tested mod inside its own Lua VM:
--        if script.active_mods["RitnTest"] then require("__RitnTest__.interface") end
--      (to put at the tested mod control.lua loading, not inside an event).
--      It adds the remote interface "RitnTest_<mod>", called through RCON (tools/rcon.py), which:
--        - sends fake GUI events (click, box, text, selection, slider, tab, closing)
--          and fake shortcuts to the mod handlers, found through script.get_event_handler:
--          it is the same code as a real click, on real elements;
--        - describes a player's GUI tree (names, types, captions, styles, tags...);
--        - takes a screenshot with the interface (script-output/RitnTest/);
--        - evaluates a Lua expression inside the mod VM (e.g. read its storage).
--      Does nothing as long as no mod loads it. Development tool: never published.
---------------------------------------------------------------------------------------------
-- FR : Sélecteur d'élément (paramètre « selector » des fonctions) :
--        - un nom : l'élément de ce nom, cherché dans toute la GUI du joueur
--          (screen, left, top, center, goal, relative) ;
--        - une liste d'étapes, depuis la première : { "nom", 2, { key = "beta" }, "nom" }
--            « nom »          : descendant de ce nom ;
--            nombre           : enfant à cette position ;
--            table de tags    : descendant dont les tags ont ces valeurs (lignes sans nom).
-- EN : Element selector ("selector" parameter of the functions):
--        - a name: the element of this name, searched in the whole player GUI
--          (screen, left, top, center, goal, relative);
--        - a list of steps, from the first one: { "name", 2, { key = "beta" }, "name" }
--            "name"           : descendant of this name;
--            number           : child at this position;
--            tags table       : descendant whose tags have these values (unnamed rows).
---------------------------------------------------------------------------------------------

-- FR : Nom de l'interface : un par mod testé (ex. RitnTest_gvv)
-- EN : Interface name: one per tested mod (e.g. RitnTest_gvv)
local INTERFACE_NAME = "RitnTest_" .. script.mod_name

-- FR : Racines de la GUI d'un joueur, dans l'ordre de recherche
-- EN : Roots of a player's GUI, in the search order
local GUI_ROOTS = { "screen", "left", "top", "center", "goal", "relative" }

-- FR : Dossier des captures, dans script-output
-- EN : Screenshots folder, inside script-output
local SCREENSHOT_FOLDER = "RitnTest/"

-- FR : Nombre de lignes au plus renvoyées par describe (une réponse RCON trop longue est pénible à lire)
-- EN : Maximum number of lines returned by describe (a too long RCON answer is hard to read)
local DESCRIBE_MAX_LINES = 400

-- FR : Propriétés décrites selon le type d'élément (en plus de la légende, de l'état, du style et des tags)
-- EN : Properties described according to the element type (on top of caption, state, style and tags)
local TYPE_KEYS = {
    ["checkbox"] = { "state" },
    ["radiobutton"] = { "state" },
    ["textfield"] = { "text" },
    ["text-box"] = { "text" },
    ["list-box"] = { "selected_index" },
    ["drop-down"] = { "selected_index" },
    ["tabbed-pane"] = { "selected_tab_index" },
    ["slider"] = { "slider_value" },
    ["sprite"] = { "sprite" },
    ["sprite-button"] = { "sprite" },
}

-- FR : Options de serpent : une ligne, sans commentaires, sans code de fonction
-- EN : serpent options: one line, without comments, without function code
local SERPENT_LINE = { comment = false, nocode = true }


---------------------------------------------------------------------------------------------
-- FR : RECHERCHE D'ÉLÉMENTS
-- EN : ELEMENTS SEARCH
---------------------------------------------------------------------------------------------

-- FR : Joueur par son index ; erreur claire s'il n'existe pas
-- EN : Player by its index; clear error if it doesn't exist
local function getPlayer(player_index)
    local player = game.get_player(player_index)

    -- FR : Joueur inconnu (ex. personne n'a rejoint la partie)
    -- EN : Unknown player (e.g. nobody joined the game)
    if player == nil then
        error("RitnTest: no player " .. tostring(player_index))
    end
    return player
end


-- FR : Vrai si les tags de l'élément ont toutes les valeurs du filtre
-- EN : True if the element tags have all the filter values
local function tagsMatch(element, filter)
    local tags = element.tags
    for key, value in pairs(filter) do
        if tags[key] ~= value then
            return false
        end
    end
    return true
end


-- FR : Premier descendant (en profondeur) qui vérifie test, ou nil
-- EN : First descendant (depth first) that passes test, or nil
local function findDescendant(element, test)
    for _, child in ipairs(element.children) do
        -- FR : L'enfant lui-même
        -- EN : The child itself
        if test(child) then
            return child
        end

        -- FR : Puis ses propres descendants
        -- EN : Then its own descendants
        local found = findDescendant(child, test)
        if found ~= nil then
            return found
        end
    end
    return nil
end


-- FR : Fonction de test pour une étape « nom » ou « table de tags »
-- EN : Test function for a "name" or "tags table" step
local function stepTest(step)
    if type(step) == "table" then
        return function(element)
            return tagsMatch(element, step)
        end
    end
    return function(element)
        return element.name == step
    end
end


-- FR : Élément désigné par un sélecteur (voir l'en-tête) ; erreur claire si une étape manque
-- EN : Element pointed by a selector (see the header); clear error if a step is missing
local function resolve(player, selector)
    -- FR : Un nom seul : liste d'une étape
    -- EN : A single name: one step list
    local steps = selector
    if type(selector) ~= "table" or selector[1] == nil then
        steps = { selector }
    end

    local current = nil
    for index, step in ipairs(steps) do
        if index == 1 then
            -- FR : Première étape : cherchée dans chaque racine de la GUI du joueur
            -- EN : First step: searched inside each root of the player GUI
            if type(step) == "number" then
                error("RitnTest: the first step can't be a position")
            end
            local test = stepTest(step)
            for _, root_name in ipairs(GUI_ROOTS) do
                current = findDescendant(player.gui[root_name], test)
                if current ~= nil then
                    break
                end
            end
        elseif type(step) == "number" then
            -- FR : Enfant à cette position
            -- EN : Child at this position
            current = current.children[step]
        else
            -- FR : Descendant de ce nom, ou dont les tags correspondent
            -- EN : Descendant of this name, or whose tags match
            current = findDescendant(current, stepTest(step))
        end

        -- FR : Étape introuvable : on le dit, avec l'étape en cause
        -- EN : Step not found: say so, with the step concerned
        if current == nil then
            error("RitnTest: step " .. index .. " not found: " .. serpent.line(step, SERPENT_LINE))
        end
    end
    return current
end


---------------------------------------------------------------------------------------------
-- FR : ENVOI D'ÉVÈNEMENTS
-- EN : EVENTS SENDING
---------------------------------------------------------------------------------------------

-- FR : Touches de modification à partir d'un texte comme « shift+control »
-- EN : Modifier keys from a text like "shift+control"
local function readModifiers(modifiers)
    local text = modifiers or ""
    return {
        alt = text:find("alt") ~= nil,
        control = text:find("control") ~= nil,
        shift = text:find("shift") ~= nil,
    }
end


-- FR : Évènement de base : nom, tick, joueur, élément
-- EN : Base event: name, tick, player, element
local function baseEvent(event_id, player, element)
    return {
        name = event_id,
        tick = game.tick,
        player_index = player.index,
        element = element,
    }
end


-- FR : Envoie l'évènement au gestionnaire du mod. Renvoie « ok », « no handler » (le mod n'écoute pas
--      cet évènement) ou « error: ... » si le gestionnaire a levé une erreur.
-- EN : Sends the event to the mod handler. Returns "ok", "no handler" (the mod doesn't listen to
--      this event) or "error: ..." if the handler raised an error.
local function fire(event_id, event)
    local handler = script.get_event_handler(event_id)

    -- FR : Le mod n'écoute pas cet évènement
    -- EN : The mod doesn't listen to this event
    if handler == nil then
        return "no handler"
    end

    -- FR : Appel protégé : l'erreur est renvoyée au lieu d'interrompre la commande
    -- EN : Protected call: the error is returned instead of stopping the command
    local success, message = pcall(handler, event)
    if not success then
        return "error: " .. tostring(message)
    end
    return "ok"
end


-- FR : Vrai si le filtre de boutons de souris de l'élément accepte ce bouton (comme le ferait le jeu).
--      Un élément sans filtre (pas un bouton) accepte tout.
-- EN : True if the element mouse button filter accepts this button (as the game would).
--      An element without filter (not a button) accepts everything.
local function buttonAccepted(element, button)
    local has_filter, filter = pcall(function() return element.mouse_button_filter end)
    if not has_filter or type(filter) ~= "table" or next(filter) == nil then
        return true
    end
    return filter[button] == true
end


---------------------------------------------------------------------------------------------
-- FR : DESCRIPTION
-- EN : DESCRIPTION
---------------------------------------------------------------------------------------------

-- FR : Texte d'une légende : la chaîne entre guillemets, ou le texte localisé en une ligne
-- EN : Caption text: the string within quotes, or the localised string on one line
local function captionText(caption)
    if type(caption) == "string" then
        return string.format("%q", caption)
    end
    return serpent.line(caption, SERPENT_LINE)
end


-- FR : Une ligne de description d'un élément : position ou nom, type, puis les propriétés utiles
-- EN : One description line of an element: position or name, type, then the useful properties
local function describeLine(element, position)
    local parts = {}

    -- FR : Nom, ou position pour un élément sans nom
    -- EN : Name, or position for an unnamed element
    if element.name ~= "" then
        parts[#parts + 1] = element.name
    else
        parts[#parts + 1] = "#" .. position
    end
    parts[#parts + 1] = "[" .. element.type .. "]"

    -- FR : Propriétés lues sans erreur (chaque type n'a pas toutes les propriétés)
    -- EN : Properties read without error (each type doesn't have all the properties)
    local function read(key)
        local success, value = pcall(function() return element[key] end)
        if success then
            return value
        end
        return nil
    end

    -- FR : Légende, état visible / actif, style
    -- EN : Caption, visible / enabled state, style
    local caption = read("caption")
    if caption ~= nil and caption ~= "" then
        parts[#parts + 1] = "caption=" .. captionText(caption)
    end
    if element.visible == false then
        parts[#parts + 1] = "visible=false"
    end
    if element.enabled == false then
        parts[#parts + 1] = "enabled=false"
    end
    parts[#parts + 1] = "style=" .. element.style.name

    -- FR : Valeurs propres au type de l'élément (case, texte, liste, onglets, curseur, image)
    -- EN : Values specific to the element type (box, text, list, tabs, slider, image)
    for _, key in ipairs(TYPE_KEYS[element.type] or {}) do
        local value = read(key)
        if value ~= nil and value ~= "" then
            parts[#parts + 1] = key .. "=" .. serpent.line(value, SERPENT_LINE)
        end
    end
    local items = read("items")
    if type(items) == "table" and #items > 0 then
        parts[#parts + 1] = "items=" .. #items
    end

    -- FR : Tags (données des éléments dynamiques)
    -- EN : Tags (dynamic elements data)
    local tags = element.tags
    if next(tags) ~= nil then
        parts[#parts + 1] = "tags=" .. serpent.line(tags, SERPENT_LINE)
    end
    return table.concat(parts, " ")
end


-- FR : Ajoute aux lignes la description d'un élément et de ses enfants, jusqu'à la profondeur donnée
-- EN : Adds to the lines the description of an element and its children, down to the given depth
local function describeTree(lines, element, position, indent, depth)
    -- FR : Limite de lignes atteinte : on s'arrête
    -- EN : Lines limit reached: stop
    if #lines >= DESCRIBE_MAX_LINES then
        return
    end
    lines[#lines + 1] = string.rep("  ", indent) .. describeLine(element, position)

    -- FR : Profondeur atteinte : seulement le nombre d'enfants
    -- EN : Depth reached: only the children count
    local children = element.children
    if depth <= 0 then
        if #children > 0 then
            lines[#lines + 1] = string.rep("  ", indent + 1) .. "(" .. #children .. " children)"
        end
        return
    end

    -- FR : Chaque enfant, un niveau plus bas
    -- EN : Each child, one level down
    for index, child in ipairs(children) do
        describeTree(lines, child, index, indent + 1, depth - 1)
    end
end


---------------------------------------------------------------------------------------------
-- FR : FONCTIONS DE L'INTERFACE
-- EN : INTERFACE FUNCTIONS
---------------------------------------------------------------------------------------------

local interface = {}


---FR : Vérifie que l'interface répond : renvoie le nom du mod testé.
---EN : Checks that the interface answers: returns the tested mod name.
---@return string
function interface.ping()
    return script.mod_name
end


---FR : Clic sur un élément. button : « left » (par défaut), « right » ou « middle » ;
---     modifiers : ex. « shift+control ». Refusé (« filtered ») si le filtre de l'élément
---     n'accepte pas ce bouton, comme dans le jeu.
---EN : Click on an element. button: "left" (default), "right" or "middle";
---     modifiers: e.g. "shift+control". Refused ("filtered") if the element filter
---     doesn't accept this button, as in the game.
---@return string
function interface.click(player_index, selector, button, modifiers)
    local player = getPlayer(player_index)
    local element = resolve(player, selector)
    button = button or "left"

    -- FR : Bouton de souris refusé par l'élément : le jeu n'enverrait pas l'évènement
    -- EN : Mouse button refused by the element: the game wouldn't send the event
    if not buttonAccepted(element, button) then
        return "filtered"
    end

    -- FR : Évènement de clic, avec le bouton et les touches de modification
    -- EN : Click event, with the button and the modifier keys
    local event = baseEvent(defines.events.on_gui_click, player, element)
    event.button = defines.mouse_button_type[button]
    event.cursor_display_location = { x = 0, y = 0 }
    for key, value in pairs(readModifiers(modifiers)) do
        event[key] = value
    end
    return fire(defines.events.on_gui_click, event)
end


---FR : Coche ou décoche une case (ou un bouton radio), puis envoie l'évènement.
---EN : Checks or unchecks a box (or a radio button), then sends the event.
---@return string
function interface.check(player_index, selector, state)
    local player = getPlayer(player_index)
    local element = resolve(player, selector)
    element.state = state
    return fire(defines.events.on_gui_checked_state_changed,
        baseEvent(defines.events.on_gui_checked_state_changed, player, element))
end


---FR : Écrit un texte dans un champ, puis envoie l'évènement de texte modifié.
---EN : Writes a text inside a field, then sends the text changed event.
---@return string
function interface.text(player_index, selector, text)
    local player = getPlayer(player_index)
    local element = resolve(player, selector)
    element.text = text
    local event = baseEvent(defines.events.on_gui_text_changed, player, element)
    event.text = text
    return fire(defines.events.on_gui_text_changed, event)
end


---FR : Valide un champ (touche Entrée).
---EN : Confirms a field (Enter key).
---@return string
function interface.confirm(player_index, selector)
    local player = getPlayer(player_index)
    local element = resolve(player, selector)
    local event = baseEvent(defines.events.on_gui_confirmed, player, element)
    for key, value in pairs(readModifiers(nil)) do
        event[key] = value
    end
    return fire(defines.events.on_gui_confirmed, event)
end


---FR : Choisit une ligne d'une liste ou d'un menu déroulant, puis envoie l'évènement.
---EN : Chooses a line of a list or drop-down, then sends the event.
---@return string
function interface.select(player_index, selector, index)
    local player = getPlayer(player_index)
    local element = resolve(player, selector)
    element.selected_index = index
    return fire(defines.events.on_gui_selection_state_changed,
        baseEvent(defines.events.on_gui_selection_state_changed, player, element))
end


---FR : Change l'onglet affiché d'un panneau d'onglets, puis envoie l'évènement.
---EN : Changes the displayed tab of a tabbed pane, then sends the event.
---@return string
function interface.tab(player_index, selector, index)
    local player = getPlayer(player_index)
    local element = resolve(player, selector)
    element.selected_tab_index = index
    return fire(defines.events.on_gui_selected_tab_changed,
        baseEvent(defines.events.on_gui_selected_tab_changed, player, element))
end


---FR : Déplace un curseur (slider), puis envoie l'évènement.
---EN : Moves a slider, then sends the event.
---@return string
function interface.slide(player_index, selector, value)
    local player = getPlayer(player_index)
    local element = resolve(player, selector)
    element.slider_value = value
    return fire(defines.events.on_gui_value_changed,
        baseEvent(defines.events.on_gui_value_changed, player, element))
end


---FR : Ferme un élément (touche Échap sur une fenêtre ouverte).
---EN : Closes an element (Escape key on an opened window).
---@return string
function interface.close(player_index, selector)
    local player = getPlayer(player_index)
    local element = resolve(player, selector)
    local event = baseEvent(defines.events.on_gui_closed, player, element)
    event.gui_type = defines.gui_type.custom
    return fire(defines.events.on_gui_closed, event)
end


---FR : Raccourci clavier du mod (custom-input), ex. « toggle-main-frame_gvv-mod ».
---EN : Mod keyboard shortcut (custom-input), e.g. "toggle-main-frame_gvv-mod".
---@return string
function interface.input(player_index, input_name)
    local player = getPlayer(player_index)
    local event = {
        name = input_name,
        input_name = input_name,
        tick = game.tick,
        player_index = player.index,
        cursor_position = player.position,
    }
    return fire(input_name, event)
end


---FR : Vrai si l'élément existe (sans erreur s'il manque).
---EN : True if the element exists (without error if it is missing).
---@return boolean
function interface.exists(player_index, selector)
    local player = getPlayer(player_index)
    local success = pcall(resolve, player, selector)
    return success
end


---FR : Décrit un élément et ses enfants, une ligne par élément (profondeur 3 par défaut).
---EN : Describes an element and its children, one line per element (depth 3 by default).
---@return string
function interface.describe(player_index, selector, depth)
    local player = getPlayer(player_index)
    local element = resolve(player, selector)
    local lines = {}
    describeTree(lines, element, element.get_index_in_parent(), 0, depth or 3)

    -- FR : Limite atteinte : on le signale
    -- EN : Limit reached: say so
    if #lines >= DESCRIBE_MAX_LINES then
        lines[#lines + 1] = "... (limit of " .. DESCRIBE_MAX_LINES .. " lines)"
    end
    return table.concat(lines, "\n")
end


---FR : Capture d'écran du joueur, interface comprise, dans script-output/RitnTest/<name>.png.
---     Le fichier est écrit à la fin du tick : attendre qu'il apparaisse avant de le lire.
---EN : Screenshot of the player, interface included, inside script-output/RitnTest/<name>.png.
---     The file is written at the end of the tick: wait for it to appear before reading it.
---@return string
function interface.screenshot(player_index, name)
    local player = getPlayer(player_index)
    local path = SCREENSHOT_FOLDER .. (name or "screenshot") .. ".png"
    game.take_screenshot({
        player = player,
        by_player = player,
        show_gui = true,
        resolution = player.display_resolution,
        path = path,
    })
    return path
end


---FR : Évalue une expression Lua dans la VM du mod testé (ex. « storage.players[1].show_func »)
---     et renvoie le résultat en une ligne. Accepte aussi des instructions (sans résultat).
---EN : Evaluates a Lua expression inside the tested mod VM (e.g. "storage.players[1].show_func")
---     and returns the result on one line. Also accepts statements (without result).
---@return string
function interface.eval(code)
    -- FR : D'abord comme expression, sinon comme instructions
    -- EN : First as an expression, otherwise as statements
    local chunk, message = load("return " .. code)
    if chunk == nil then
        chunk, message = load(code)
    end
    if chunk == nil then
        return "error: " .. tostring(message)
    end

    -- FR : Exécution protégée, résultat en une ligne
    -- EN : Protected run, result on one line
    local success, result = pcall(chunk)
    if not success then
        return "error: " .. tostring(result)
    end
    return serpent.line(result, { comment = false, nocode = true, maxlevel = 4 })
end


---------------------------------------------------------------------------------------------
-- FR : Enregistrement de l'interface (une seule fois, même si le fichier est chargé deux fois)
-- EN : Interface registration (only once, even if the file is loaded twice)
if not remote.interfaces[INTERFACE_NAME] then
    remote.add_interface(INTERFACE_NAME, interface)
end
