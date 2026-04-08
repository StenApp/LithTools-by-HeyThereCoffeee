Decompiled version of LithTools by HeyThereCoffeee

  -primarily fixed is the NOLF PS2 stuff like Level, Model and Texture viewing
  
  -LTA exporting of levels PC and PS2
  
  -viewing of Models in abc/ltb format (tested with NOLF1, NOLF2)
  
  -viewing of Levels dat and ltb format (NOLF1 PS2, NOLF1 PC, NOLF2)

Set up folder containing textures (tex folder) in settings.cfg in LTDatReader folder.

Setting export_to_lta_on_load =true exports the level to an LTA level file (NOLF1 format), now via Menu.
<img width="383" height="232" alt="grafik" src="https://github.com/user-attachments/assets/730379ed-23ae-4507-83c6-1d99b06797a6" />

Texture viewer is only tested for BPP_32 and BPP_32P textures.

Use Godot_v3.5.3-stable_win64.exe with this project
