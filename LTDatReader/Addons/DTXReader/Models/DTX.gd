extends Node

class DTX:
	
	# Versioning
	# Ints in godot are 64-bit, so no overflow...
	const DTX_VERSION_LT1  = 4294967294 # -2
	const DTX_VERSION_LT15 = 4294967293 # -3
	const DTX_VERSION_LT2  = 4294967291 # -5
	
	const MAX_UINT = 4294967296
	
	# From io_scene_abc
	# Resource Types
	const RESOURCE_TYPE_DTX = 0
	const RESOURCE_TYPE_MODEL = 1
	const RESOURCE_TYPE_SPRITE = 2
	
	# Flags
	const DTX_FULLBRITE       = (1 << 0)  # This DTX has fullbrite colors.
	const DTX_PREFER16BIT     = (1 << 1)  # Use 16-bit, even if in 32-bit mode.
	const DTX_MIPSALLOCED     = (1 << 2)  # Used to make some of the tools stuff easier..this means each TextureMipData has its texture data allocated.
	const DTX_SECTIONSFIXED   = (1 << 3)  # The sections count was screwed up originally.  This flag is set in all the textures from now on when the count is fixed.
	const DTX_NOSYSCACHE      = (1 << 6)  # tells it to not put the texture in the texture cache list.
	const DTX_PREFER4444      = (1 << 7)  # If in 16-bit mode, use a 4444 texture for this.
	const DTX_PREFER5551      = (1 << 8)  # Use 5551 if 16-bit.
	const DTX_32BITSYSCOPY    = (1 << 9)  # If there is a sys copy - don't convert it to device specific format (keep it 32 bit).
	const DTX_CUBEMAP         = (1 << 10) # Cube environment map.  +x is stored in the normal data area, -x,+y,-y,+z,-z are stored in their own sections
	const DTX_BUMPMAP         = (1 << 11) # Bump mapped texture, this has 8 bit U and V components for the bump normal
	const DTX_LUMBUMPMAP      = (1 << 12) # Bump mapped texture with luminance, this has 8 bits for luminance, U and V
	const DTX_FLAGSAVEMASK    = (DTX_FULLBRITE | DTX_32BITSYSCOPY | DTX_PREFER16BIT | DTX_SECTIONSFIXED | DTX_PREFER4444 | DTX_PREFER5551 | DTX_CUBEMAP | DTX_BUMPMAP | DTX_LUMBUMPMAP | DTX_NOSYSCACHE)
	
	const DTX_COMMANDSTRING_LENGTH = 128

	# Pixel format identifiers (BPPIdent from pixelformat.h)
	# g_PixelBytes[] = {1, 1, 2, 4, 0, 0, 0, 1, 3} (bytes per pixel)
	# Special: m_Extra[2]==0 in header means BPP_32, not BPP_8P (see GetBPPIdent())
	#
	# Wert | Name          | Bytes/Pixel | Format            | Spiele
	# -----+---------------+-------------+-------------------+------------------
	#   0  | BPP_8P        | 1 (index)   | 8-bit palettiert  | LT1/LT1.5 (Blood2, Shogo)
	#   1  | BPP_8         | 1           | 8-bit Graustufen  | LT1/LT1.5
	#   2  | BPP_16        | 2           | RGB565            | LT1/LT1.5
	#   3  | BPP_32        | 4           | BGRA 32-bit       | NOLF1/2 (haeufigstes Format)
	#   4  | BPP_S3TC_DXT1 | w*h/2       | DXT1 komprimiert  | NOLF1/2
	#   5  | BPP_S3TC_DXT3 | w*h         | DXT3 komprimiert  | NOLF1/2
	#   6  | BPP_S3TC_DXT5 | w*h         | DXT5 komprimiert  | NOLF1/2
	#   7  | BPP_32P       | 1 (index)   | 32-bit Palette    | NOLF1 PS2
	#   8  | BPP_24        | 3           | BGR 24-bit        | selten
	const BPP_8P = 0
	const BPP_8 = 1
	const BPP_16 = 2
	const BPP_32 = 3
	const BPP_S3TC_DXT1 = 4
	const BPP_S3TC_DXT3 = 5
	const BPP_S3TC_DXT5 = 6
	const BPP_32P = 7
	const BPP_24 = 8
	
	# Header
	var resource_type = 0
	var version = 0
	var width = 0
	var height = 0
	var mipmap_count = 0
	var section_count = 0
	var flags = 0
	var user_flags = 0
	# Extra data
	var texture_group = 0
	var mipmaps_to_use = 0
	var bytes_per_pixel = 0
	var mipmap_offset = 0
	var mipmap_tex_coord_offset = 0
	var texture_priority = 0
	var detail_texture_scale = 0.0
	var detail_texture_angle = 0
	var command_string = ""
	
	var image : Image
	
	func _init():
		pass
	# End Func
	
	enum IMPORT_RETURN{SUCCESS, ERROR}
	
	func read(f : File):
		self.image = null
		
		self.resource_type = f.get_32()
		
		if (self.resource_type != 0):
			f.seek(0)
		
		self.version = f.get_32()
		
		var nice_version = MAX_UINT - self.version
		
		#print("DTX Version: " + str(nice_version))
				
		if [DTX_VERSION_LT1, DTX_VERSION_LT15, DTX_VERSION_LT2].has(self.version) == false:
			return self._make_response(IMPORT_RETURN.ERROR, 'Unsupported file version (' + str(nice_version) + ')')
				
		
		self.width = f.get_16()
		self.height = f.get_16()
		self.mipmap_count = f.get_16()
		self.section_count = f.get_16()
		self.flags = f.get_32()
		self.user_flags = f.get_32()
		
		# Extra data - this may be not be entirely correct for DTX_VERSION_LT1
		self.texture_group = f.get_8()
		self.mipmaps_to_use = f.get_8()
		self.bytes_per_pixel = f.get_8()
		self.mipmap_offset = f.get_8()
		self.mipmap_tex_coord_offset = f.get_8()
		self.texture_priority = f.get_8()
		self.detail_texture_scale = f.get_float()
		self.detail_texture_angle = f.get_16()
		
		if [DTX_VERSION_LT15, DTX_VERSION_LT2].has(self.version):
			self.command_string = f.get_buffer(DTX_COMMANDSTRING_LENGTH).get_string_from_ascii()
			
		self.image = self.read_texture_data(f)
		
		if self.image == null:
			return self._make_response(IMPORT_RETURN.ERROR, "Couldn't create image. BPP value: " + str(self.bytes_per_pixel))
		
		return self._make_response(IMPORT_RETURN.SUCCESS)
		

		
	# End Func
	
	# Entspricht DtxHeader::GetBPPIdent() aus dtxmgr.h:
	# m_Extra[2]==0 bedeutet BPP_32 (nicht BPP_8P!).
	# Hintergrund: SetBPPIdent(BPP_32) schreibt 3, GetBPPIdent() gibt bei 0 als Default BPP_32 zurueck.
	func get_bpp_ident() -> int:
		return BPP_32 if self.bytes_per_pixel == 0 else self.bytes_per_pixel

	func read_texture_data(f : File):
		var image = null
		var bpp = self.get_bpp_ident()
		
		# LT1/LT1.5: nur BPP_8P (palettiert) wird mit dem alten Format gelesen
		# LT1 kann aber auch andere Formate haben (DXT etc.) - bpp entscheidet
		if [DTX_VERSION_LT1, DTX_VERSION_LT15].has(self.version) and bpp == BPP_8P:
			image = self.read_8bit_palette(f)
		elif [BPP_S3TC_DXT1, BPP_S3TC_DXT3, BPP_S3TC_DXT5].has(bpp):
			image = self.read_compressed(f)
		elif bpp == BPP_32:
			image = self.read_32bit_texture(f)
		elif bpp == BPP_8P:
			image = self.read_8bit_palette(f)
		elif bpp == BPP_32P:
			image = self.read_32bit_palette(f)
		elif bpp == BPP_8:
			image = self.read_8bit_greyscale(f)
		elif bpp == BPP_16:
			image = self.read_16bit_texture(f)
		elif bpp == BPP_24:
			image = self.read_24bit_texture(f)
		else:
			print("DTX: Unsupported BPP: ", bpp)
		
		return image
		
	#
	# Read in a DXT compressed texture
	# Godot does the heavy lifting here!
	#
	# BPP_S3TC_DXT1/3/5: S3TC-komprimiert
	# CalcImageSize: DXT1 = w*h/2, DXT3/5 = w*h bytes
	# Quelle: pixelformat.cpp CalcImageSize()
	func read_compressed(f : File):
		var image = Image.new()
		
		# DXT1 - Defaults
		var format = Image.FORMAT_DXT1
		var scale = 8 # Extra bytes needed in the decoding process
		
		var bpp_dxt = self.get_bpp_ident()
		if bpp_dxt == BPP_S3TC_DXT3:
			format = Image.FORMAT_DXT3
			scale = 16
		elif bpp_dxt == BPP_S3TC_DXT5:
			format = Image.FORMAT_DXT5
			scale = 16
			
		var compressed_width = int((self.width + 3) / 4)
		var compressed_height = int((self.height + 3) / 4)
		
		var data = f.get_buffer(compressed_width * compressed_height * scale)
		
		image.create_from_data(self.width, self.height, false, format, data)
		
		return image
		
	
	# BPP_32: 4 bytes/pixel, gespeichert als BGRA, Alpha=0 bei Fullbrite-Texturen
	# Quelle: dtxmgr.cpp dtx_Create(), dtx_RevRGBOrder() nur auf PS2
	func read_32bit_texture(f : File):
		var image = Image.new()
		var raw_data = f.get_buffer(self.width * self.height * 4)
		
		# Try swapping just red and blue channels (BGRA -> RGBA)
		var rgba_data = PoolByteArray()
		var i = 0
		while i < raw_data.size():
			var r = raw_data[i]     # What we think is Red
			var g = raw_data[i + 1] # Green
			var b = raw_data[i + 2] # What we think is Blue
			var a = raw_data[i + 3] # Alpha
			
			# BGRA -> RGBA swap, force alpha=255 if 0 (fullbrite textures)
			rgba_data.append(b)
			rgba_data.append(g)
			rgba_data.append(r)
			rgba_data.append(255 if a == 0 else a)
			
			i += 4
		
		image.create_from_data(self.width, self.height, false, Image.FORMAT_RGBA8, rgba_data)
		return image
	# End Func
		
	# BPP_32P: 1 byte/pixel Index, Palette als Section-Data gespeichert
	# pitch = width (1 byte/pixel), Palette = 256 * 4 bytes BGRA
	# Quelle: dtxmgr.cpp dtx_Alloc() (pitch=width), dtx_Create() (sections)
	# SectionHeader: char m_Type[15] + char m_Name[10] + uint32 m_DataLen = 29 bytes
	func read_32bit_palette(f : File):
		var image = Image.new()
		var palette = []
		
		# Read main mipmap pixel indices (1 byte/pixel, BPP_32P pitch = width)
		var data = f.get_buffer(self.width * self.height)
		var colour_data = PoolByteArray()
		
		# Skip remaining mipmaps (each also 1 byte/pixel)
		var mip_width = self.width
		var mip_height = self.height
		for _i in range(self.mipmap_count - 1):
			mip_width /= 2
			mip_height /= 2
			f.get_buffer(mip_width * mip_height)
		
		# Read sections - palette is stored as section data
		# SectionHeader: char m_Type[15] + char m_Name[10] + uint32 m_DataLen = 29 bytes
		for _s in range(self.section_count):
			# Section header = 32 bytes total:
			# m_Type (15) + padding (13) + m_DataLen (4)
			# Verified empirically with ps2_baron_action_hat.dtx and hero_thief.dtx
			var _section_type = f.get_buffer(15)
			var _section_padding = f.get_buffer(13)
			var section_length = f.get_32()
			var palette_entries = section_length / 4  # 4 bytes per BGRA entry
			for _i in range(palette_entries):
				var packed_data = f.get_32()
				var unpacked = self.convert_32_to_8_bit(packed_data)
				palette.append(Quat(unpacked.x, unpacked.y, unpacked.z, unpacked.w))
		
		if palette.size() == 0:
			print("DTX BPP_32P: No palette found in sections (section_count=", self.section_count, ")")
			return null
		
		var i = 0

		# Apply the palette
		while (i < data.size() ):
			colour_data.append( palette[data[i]].x )  # R
			colour_data.append( palette[data[i]].y )  # G
			colour_data.append( palette[data[i]].z )  # B
			colour_data.append( palette[data[i]].w )  # A
			i += 1
		# End While
		
		image.create_from_data(self.width, self.height, false, Image.FORMAT_RGBA8, colour_data)
		return image
		
	#
	# Read in a 8-bit palettized texture
	# Basically for Lithtech 1.0 games.
	#
	func read_8bit_palette(f : File):
		var image = Image.new()
		var palette = []
		
		# Two unknown ints!
		# Used for the internal get palette function in LT1
		var _palette_header_1 = f.get_32()
		var _palette_header_2 = f.get_32()

		# Palette: Format ist ARGB laut pixelformat.h RPaletteColor { uchar a,r,g,b }
		for _i in range(256):
			var a = f.get_8()
			var r = f.get_8()
			var g = f.get_8()
			var b = f.get_8()
			palette.append( Quat(r, g, b, a) )
		# End For

		var data = f.get_buffer(self.width * self.height * 1)
		var colour_data = PoolByteArray()
		
		var i = 0
		
		# Apply the palette
		while (i < data.size() ):
			colour_data.append( palette[data[i]].x )  # R
			colour_data.append( palette[data[i]].y )  # G
			colour_data.append( palette[data[i]].z )  # B
			colour_data.append( palette[data[i]].w )  # A
			i += 1
		# End While
		
		image.create_from_data(self.width, self.height, false, Image.FORMAT_RGBA8, colour_data)
		
		return image
	# End Func
		
	# BPP_8: 8-bit greyscale, 1 byte/pixel
	func read_8bit_greyscale(f : File):
		var image = Image.new()
		var data = f.get_buffer(self.width * self.height)
		var rgba = PoolByteArray()
		for i in range(data.size()):
			var v = data[i]
			rgba.append(v)
			rgba.append(v)
			rgba.append(v)
			rgba.append(255)
		image.create_from_data(self.width, self.height, false, Image.FORMAT_RGBA8, rgba)
		return image

	# BPP_16: RGB565, 2 bytes/pixel
	# Masks: R=0xF800, G=0x07E0, B=0x001F
	func read_16bit_texture(f : File):
		var image = Image.new()
		var data = f.get_buffer(self.width * self.height * 2)
		var rgba = PoolByteArray()
		var i = 0
		while i < data.size():
			var pixel = data[i] | (data[i+1] << 8)
			var r = ((pixel >> 11) & 0x1F) * 255 / 31
			var g = ((pixel >> 5)  & 0x3F) * 255 / 63
			var b = (pixel & 0x1F) * 255 / 31
			rgba.append(r)
			rgba.append(g)
			rgba.append(b)
			rgba.append(255)
			i += 2
		image.create_from_data(self.width, self.height, false, Image.FORMAT_RGBA8, rgba)
		return image

	# BPP_24: RGB, 3 bytes/pixel
	func read_24bit_texture(f : File):
		var image = Image.new()
		var data = f.get_buffer(self.width * self.height * 3)
		var rgba = PoolByteArray()
		var i = 0
		while i < data.size():
			rgba.append(data[i+2])  # R (BGR->RGB)
			rgba.append(data[i+1])  # G
			rgba.append(data[i])    # B
			rgba.append(255)
			i += 3
		image.create_from_data(self.width, self.height, false, Image.FORMAT_RGBA8, rgba)
		return image

	#
	# Helpers
	# 
	func _make_response(code, message = ''):
		return { 'code': code, 'message': message }
	# End Func
	
	func convert_32_to_8_bit(value):
		# Standard RGBA unpacking
		var r = (value & 0x000000ff)        
		var g = (value & 0x0000ff00) >>  8  
		var b = (value & 0x00ff0000) >> 16  
		var a = (value & 0xff000000) >> 24  

		# Apply same red-blue swap as 32-bit texture
		return Quat(b, g, r, a)  # Swap R and B for Godot
	# End Func
	
	func read_string(file : File, is_length_a_short = true):
		var length = 0
		if is_length_a_short:
			length = file.get_16() 
		else:
			length = file.get_32() # Sometimes it's 32-bit...
		# End If
			
		return file.get_buffer(length).get_string_from_ascii()
	# End Func
	
	func read_vector2(file : File):
		var vec2 = Vector2()
		vec2.x = file.get_float()
		vec2.y = file.get_float()
		return vec2
	# End Func
		
	func read_vector3(file : File):
		var vec3 = Vector3()
		vec3.x = file.get_float()
		vec3.y = file.get_float()
		vec3.z = file.get_float()
		return vec3
	# End Func
	
	func read_quat(file : File):
		var quat = Quat()
		quat.w = file.get_float()
		quat.x = file.get_float()
		quat.y = file.get_float()
		quat.z = file.get_float()
		return quat
		
	func read_matrix(file : File):
		var matrix_4x4 = []
		for _i in range(16):
			matrix_4x4.append(file.get_float())
			
		return self.convert_4x4_to_transform(matrix_4x4)
	# End Func
	
	func convert_4x4_to_transform(matrix):
		return Transform(
			Vector3( matrix[0], matrix[4], matrix[8]  ),
			Vector3( matrix[1], matrix[5], matrix[9]  ),
			Vector3( matrix[2], matrix[6], matrix[10] ),
			Vector3( matrix[3], matrix[7], matrix[11] )
		)
	
