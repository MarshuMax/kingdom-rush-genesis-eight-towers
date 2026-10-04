# Eight Towers — Kingdom Rush 6: Genesis TD

Eight tower slots in the Tower Room, and the same eight in the in-stage build menu.

Stock KR6 caps you at five. This mod raises it to eight end to end — the Tower Room wheel grows to
eight slots, and the in-stage build ring grows with it, laid out on an even ring so nothing overlaps.
Tapping a built tower still gives you the full upgrade and sell menu.

Stage-specific rules are respected: modes that pick their own towers (Iron and friends) keep their
own set, and a reworked Tower Room lets you swap towers in any of the eight slots as usual.

Traced and tested on **kr6-desktop-1.00.052**.

## Install

Drop `eight_towers_mod.lua` into:

```
%APPDATA%\kingdom_rush_genesis\mods
```

and restart the game.

Requires a mod loader — tested against
[Kingdom Rush Genesis - Modloader](https://ayakamods.com/mods/kingdom-rush-genesis-modloader.4184/).

## Config

Change the number of slots on the first line and restart:

```lua
local SLOTS = 8 -- tower slots: 8, or 5 for the game's own five
```

## Uninstall

Remove the file and restart.

To go back to five slots, set `SLOTS = 5`, start the game once and open the Tower Room, then remove
the mod — the game trims the saved team itself.

## How it works

There are four separate caps between the save file and the build menu, and every one of them has to
be lifted. Three of them are where you would expect. The fourth is not a config value anywhere, and
it is the one that actually keeps the in-stage menu at five.

**1. The saved team size.** `GS.number_of_towers` is 5. It has to be raised before the save is read,
or the save scrub trims everything past the fifth entry.

**2. The Tower Room wheel.** A kui template, `group_towers_wheel`, with five buttons hard-coded —
`button_tower_ring_sel_01..05` — looked up by slot number. Buttons 06..08 are cloned from the first
and laid out on an even ring. `kui_db.get_table` returns a fresh copy on every call, so the template
has to be patched on every call, not once.

**3. The in-stage tower list is not the Tower Room team.** When a stage is initialised the game
replaces `slot.towers.selected` with the stage's own set (`level.data.level_mode_overrides[mode].available_towers`,
or the stage default). Measured: eight in the Tower Room, the stage's seven in `store.selected_towers`.
The list is forced back to the saved team every 15 frames — except when the current mode names its own
`available_towers`, in which case the stage keeps what it asked for.

**4. The one that keeps the in-stage menu at five.** `TowerMenu.show(entity)` takes a single entity and
gets its list from `get_tower_menu_items(entity)`, a local in the same closure. That function returns
every tower the spot can build — all 19 of them — but it only stamps `place` on the first five entries
of the saved team, and `show()` only builds a button for entries that carry a `place`.

At the moment it runs, `GS.number_of_towers`, `store.selected_towers` and `load_slot().towers.selected`
all read 8, so the 5 is not any of them. It lives in that stamping.

This mod takes over the upvalue and stamps `place` on the entries the game skipped. It only adds, never
clears: the same function also serves the "tap a built tower" upgrade menu, whose places belong to the
game, and clearing those removes every upgrade and sell option.

**5. Button positions.** They come from `data.game_gui_data.tower_menu_button_places[place]`. The stock
table has 19 offsets but they are not an even ring (entries 1 and 6 are 20 px apart), so eight of them
overlap. The first eight are laid out on an even ring instead. The table must never be shortened:
`show()` indexes it by slot number, and a short table yields nil, which `vclone(nil)` crashes on.

### A note on the loader interface

The mod uses only `api.log` and `api.when_loaded` from the loader. Frames are taken from
`love.timer.getDelta` directly — that is the one stable per-frame hook, since the game swaps
`love.update` and `love.draw` per scene — so a loader without a frame hook is fine.

## Compatibility

- Tested on kr6-desktop-1.00.052.
- The Tower Room team is only ever read, never written, so swapping towers in the Tower Room works
  normally and the change carries into the next stage.
- Modes with their own tower rules are left untouched.

## License

MIT — see [LICENSE](LICENSE).

---

## 中文

王国保卫战 6：新启程 — 塔房 8 个塔位，战斗内建塔菜单同样是 8 个。

原版卡在 5 个。这个 mod 从存档到建塔菜单整条链都提到 8：塔房圆环扩到 8 个位，战斗内的建塔圆环同步扩到 8 个并重新等分排布，不会重叠。点已建好的塔，升级和出售菜单完整保留。

各关卡自己的规则不动 —— 铁人这类自己指定塔表的模式，以及限制塔池的关卡，一律尊重原样。

**安装**：把 `eight_towers_mod.lua` 丢进 `%APPDATA%\kingdom_rush_genesis\mods`，重启游戏。需要一个 modloader。

**改塔位数量**：改文件第一行的 `SLOTS`，重启游戏。填 5 就是游戏原本的 5 个。

**卸载**：删掉文件重启。想退回 5 个塔位，先把 `SLOTS` 改成 5，启动游戏进一次塔房，再删掉 mod。

原理见上面英文部分的四条限制，文件开头的注释里写得更细。
