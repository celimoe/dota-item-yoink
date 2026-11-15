local protobuf = require("protobuf")
local json = require("assets.JSON")

local stashit = {}

-- #region cosmetic panorama
stashit.js = --[[js]] [==[
	var __celi_stashit;

	(() => {
		const hud = $.GetContextPanel();
		const state = {"enabled": false, "item": null, "icon": null, "row_w": 252};
		const lists = [["inventory_list", 0], ["inventory_list2", 0], ["inventory_backpack_list", 0], ["stash_row", 9]];
		const fake_slot_id = "__celi_stash_fake";

		function fake(row) {
			let panel = row.FindChild(fake_slot_id);
			if (!panel) {
				panel = $.CreatePanel("DOTAAbilityPanel", row, fake_slot_id, {"hittest": "true"});
				$.RegisterEventHandler("DragDrop", panel, () => __celi_stashit.land());
			}

			for (const c of ["InventoryItem", "Stash", "no_ability", "cooldown_ready", "no_mana_cost", "no_health_cost", "no_gold_cost", "no_level", "no_hotkey"]) {
				panel.AddClass(c);
			}

			return panel;
		}

		function tick() {
			hook();

			const stash = hud.FindChildTraverse("StashContainer")?.FindChild("stash");
			for (const id of ["stash_bg", "stash_row", "grab_all_button"]) {
				const panel = stash?.FindChild(id);
				if (panel) panel.style.visibility = state.enabled ? "visible" : null;
			}

			const row = hud.FindChildTraverse("stash_row");
			if (row) {
				let hidden = true;
				for (let i = 0; i < row.GetChildCount(); i++) {
					const slot = row.GetChild(i);
					if (slot.id != fake_slot_id && !slot.BHasClass("Hidden")) hidden = false;
				}

				if (!hidden) {
					state.row_w = row.actuallayoutwidth / row.actualuiscale_x;
				}

				const panel = fake(row);
				panel.visible = state.enabled && hidden;
				panel.style.marginRight = (state.row_w - panel.actuallayoutwidth / panel.actualuiscale_x) / 2 + "px";
			}
		}

		function slots() {
			const all = [];

			for (const [list, base] of lists) {
				const parent = hud.FindChildTraverse(list);

				for (let i = 0; parent && i < parent.GetChildCount(); i++) {
					const panel = parent.GetChild(i);

					if (/^inventory_slot_\d+$/.test(panel.id)) {
						all.push({"panel": panel, "n": parseInt(panel.id.slice(15)) + base});
					}

					if (panel.id == fake_slot_id) {
						all.push({"panel": panel, "n": 99});
					}
				}
			}

			return all;
		}

		function slot_at() {
			const [x, y] = GameUI.GetCursorPosition();

			return slots().find(({panel}) => {
				const pos = panel.GetPositionWithinWindow();
				return panel.visible && x >= pos.x && y >= pos.y && x < pos.x + panel.actuallayoutwidth && y < pos.y + panel.actuallayoutheight;
			});
		}

		function clear() {
			state.icon?.DeleteAsync(0);
			state.item = state.icon = null;

			for (const {panel} of slots()) {
				panel.RemoveClass("dragging_from");
				panel.RemoveClass("potential_drop_target");
			}
		}

		function hover(source) {
			if (state.item === null) {
				return;
			}

			const under = slot_at()?.panel;
			for (const {panel} of slots()) {
				panel.SetHasClass("potential_drop_target", panel == under && panel != source);
			}

			$.DispatchEvent("DOTAHideAbilityTooltip", under ?? source);
			$.Schedule(0.03, () => hover(source));
		}

		function begin(drag) {
			clear();

			const slot = slot_at();
			const panel = slot?.panel;
			const image = panel && (panel.FindChildTraverse("ItemImage") ?? panel.FindChildTraverse("AbilityImage"));

			if (!state.enabled || !image?.itemname || Entities.IsControllableByPlayer(Players.GetLocalPlayerPortraitUnit(), Players.GetLocalPlayer())) {
				return false;
			}

			state.from = slot.n;

			const w = image.actuallayoutwidth / image.actualuiscale_x, h = image.actuallayoutheight / image.actualuiscale_y;
			state.icon = $.CreatePanel("DOTAItemImage", hud, "", {"hittest": "false", "style": "width: " + w + "px; height: " + h + "px;"});
			state.icon.itemname = image.itemname;
			state.item = image.contextEntityIndex;

			panel.AddClass("dragging_from");
			hover(panel);

			drag.displayPanel = state.icon;
			drag.offsetX = 0;
			drag.offsetY = 0;

			return true;
		}

		function land() {
			const slot = slot_at();
			if (state.item === null) {
				return false;
			}
			
			if (slot && slot.n !== state.from) {
				Game.PrepareUnitOrders({
					"OrderType": dotaunitorder_t.DOTA_UNIT_ORDER_PING_ABILITY,
					"UnitIndex": Players.GetPlayerHeroEntityIndex(Players.GetLocalPlayer()),
					"AbilityIndex": state.item,
					"TargetIndex": slot.n + 100,
					"ShowEffects": false
				});
			}

			clear();

			return true;
		}

		function finish() {
			if (state.item === null) {
				return false;
			}

			clear();

			return true;
		}

		function hook() {
			for (const [list] of lists) {
				const parent = hud.FindChildTraverse(list);

				if (!parent || parent.GetAttributeString("__celi_drag", "") != "") {
					continue;
				}

				parent.SetAttributeString("__celi_drag", "1");
				$.RegisterEventHandler("DragStart", parent, (id, drag) => __celi_stashit.begin(drag));
				$.RegisterEventHandler("DragDrop", parent, (id, dragged) => __celi_stashit.land());
				$.RegisterEventHandler("DragEnd", parent, (id, dragged) => __celi_stashit.finish());
			}
		}

		function update(enabled) {
			state.enabled = enabled;
			tick();
		}

		// #region remove later
		function unit_changed() {
			const fake_slot = hud.FindChildTraverse("stash_row")?.FindChild(fake_slot_id);
			if (fake_slot) {
				fake_slot.visible = false;
			}
		}

		for (const id of __celi_stashit?.events ?? []) {
			GameEvents.Unsubscribe(id);
		}

		const events = ["dota_player_update_selected_unit", "dota_player_update_query_unit"].map((name) => GameEvents.Subscribe(name, unit_changed));

		__celi_stashit = {"update": update, "begin": begin, "land": land, "finish": finish, "events": events};
		// #endregion remove later

		__X_Schedule.SetInterval(0.1, tick, "celi|stashit|tick");
	})();
]==]

stashit.js_update = --[[js]] [==[
	(() => {
		const enabled = String("%lua-param%") == "true"; // @lua-param

		if (typeof __celi_stashit != "undefined") {
			__celi_stashit.update(enabled);
		}
	})();
]==]
-- #endregion cosmetic panorama

function stashit:init()
	-- #region menu
	self.ui = {}

	self.ui.menu = Menu.Create("Miscellaneous", "Other", "Stashit")
	self.ui.menu:Icon("\u{f187}")

	self.ui.general_group = self.ui.menu:Create("Main"):Create("General", Enum.GroupSide.FullWidth)

	self.ui.enable = self.ui.general_group:Switch("Enable", true)
	self.ui.enable:Icon("\u{f00c}")
	-- #endregion menu

	-- #region callbacks
	self.ui.enable:SetCallback(function (this)
		local hud = ApiExt.Panorama.GetPanelByPathCached({ "DotaHud", "Hud" })
		if (hud) then
			ApiExt.Panorama.RunScriptF(self.js_update, hud, tostring(this:Get()));
		end
	end)

	CallbacksManager:set("OnGameThreadInit", function ()
		local hud = ApiExt.Panorama.GetPanelByPathCached({ "DotaHud", "Hud" })
		if (hud) then
			ApiExt.Panorama.RunScript(self.js, hud)
			ApiExt.Panorama.RunScriptF(self.js_update, hud, tostring(self.ui.enable:Get()));
		end
	end, "celi.stashit")

	CallbacksManager:set("OnSendNetMessage", function (packet)
		if (not self.ui.enable:Get() or packet.message_id ~= 350) then
			return true;
		end

		local data = json:decode(protobuf.decodeToJSONfromObject(packet.msg_object))
		local changed = false

		for _, order in ipairs(data.orders) do
			if (order.order_type == "DOTA_UNIT_ORDER_PING_ABILITY" and order.target_index >= 100) then
				order.order_type, order.target_index = "DOTA_UNIT_ORDER_MOVE_ITEM", order.target_index - 100
			end

			local item = order.order_type == "DOTA_UNIT_ORDER_MOVE_ITEM" and order.units and order.ability_index and Entity.Get(order.ability_index)
			local hero, src

			for _, owner in ipairs(item and Heroes.GetAll() or {}) do
				for slot = 0, 16 do
					if (NPC.GetItemByIndex(owner, slot) == item) then
						hero, src = owner, slot
					end
				end
			end

			local dst = order.target_index
			if (hero and dst == 99) then
				for slot = 14, 9, -1 do
					if (not NPC.GetItemByIndex(hero, slot)) then
						dst = slot
					end
				end

				order.target_index = dst
			end

			if (dst == 99) then
				return false
			end

			if (hero and (dst >= 9 and dst <= 14 or src >= 9 and src <= 14 or order.units[1] ~= Entity.GetIndex(hero))) then
				order.units, order.position = nil, nil
				changed = true;
			end
		end

		if (not changed) then
			return true
		end

		NetChannel.SendNetMessage("CDOTAClientMsg_ExecuteOrders", json:encode(data))

		return false
	end, "celi.stashit")
	-- #endregion callbacks

	return {}
end

return stashit:init()
