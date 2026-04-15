Decompiled version of LithTools by HeyThereCoffeee

- primarily fixed is the NOLF PS2 stuff like Level, Model and Texture viewing  
- LTA exporting of levels PC and PS2
- viewing of Models in abc/ltb format (tested with Blood2, NOLF1, NOLF2)  
- viewing of Levels dat and ltb format (Blood2, Die Hard, NOLF1 PS2, NOLF1 PC, NOLF2)
- skipping lightmap reading stuff since it's not used by Godot, which makes it very fast in loading and saving LTA

Set up folder containing textures (tex folder) in settings.cfg in LTDatReader root folder.

Setting export_to_lta_on_load =true exports the level to an LTA level file (NOLF1 format), now via Menu.
<img width="383" height="232" alt="grafik" src="https://github.com/user-attachments/assets/730379ed-23ae-4507-83c6-1d99b06797a6" />

Texture viewer is  tested for BBP_8P, BPP_32 and BPP_32P textures. Needs verification for other types.

Use Godot_v3.6.2-stable_win64.exe with this project
