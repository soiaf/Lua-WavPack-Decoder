--[[
** WavPack.lua
**
** Implementation of WavPack decoder written in Lua
**
** Copyright (c) 2013 Peter McQuillan
**
** All Rights Reserved.
**                       
** Distributed under the BSD Software License (see license.txt)  
**
--]]


-- Change the following value to an even number to reflect the maximum number of samples to be processed
-- per call to WavpackUnpackSamples()

SAMPLE_BUFFER_SIZE = 256

BYTES_STORED = 3       -- 1-4 bytes/sample
MONO_FLAG  = 4       -- not stereo
HYBRID_FLAG = 8       -- hybrid mode
FALSE_STEREO = 0x40000000      -- block is stereo, but data is mono

SHIFT_LSB = 13
SHIFT_MASK = bit32.lshift(0x1F, SHIFT_LSB)

FLOAT_DATA  = 0x80   -- ieee 32-bit floating point data

SRATE_LSB = 23
SRATE_MASK = bit32.lshift(0xF, SRATE_LSB)

FINAL_BLOCK = 0x1000  -- final block of multichannel segment

MIN_STREAM_VERS = 0x402       -- lowest stream version we'll decode
MAX_STREAM_VERS = 0x410       -- highest stream version we'll decode


ID_DUMMY            =    0x0
ID_ENCODER_INFO     =    0x1
ID_DECORR_TERMS     =    0x2
ID_DECORR_WEIGHTS   =    0x3
ID_DECORR_SAMPLES   =    0x4
ID_ENTROPY_VARS     =    0x5
ID_HYBRID_PROFILE   =    0x6
ID_SHAPING_WEIGHTS  =    0x7
ID_FLOAT_INFO       =    0x8
ID_INT32_INFO       =    0x9
ID_WV_BITSTREAM     =    0xa
ID_WVC_BITSTREAM    =    0xb
ID_WVX_BITSTREAM    =    0xc
ID_CHANNEL_INFO     =    0xd

JOINT_STEREO  =  0x10    -- joint stereo
CROSS_DECORR  =  0x20    -- no-delay cross decorrelation
HYBRID_SHAPE  =  0x40    -- noise shape (hybrid mode only)

INT32_DATA     = 0x100   -- special extended int handling
HYBRID_BITRATE = 0x200   -- bitrate noise (hybrid mode only)
HYBRID_BALANCE = 0x400   -- balance noise (hybrid stereo mode only)

INITIAL_BLOCK  = 0x800   -- initial block of multichannel segment

FLOAT_SHIFT_ONES = 1      -- bits left-shifted into float = '1'
FLOAT_SHIFT_SAME = 2      -- bits left-shifted into float are the same
FLOAT_SHIFT_SENT = 4      -- bits shifted into float are sent literally
FLOAT_ZEROS_SENT = 8      -- "zeros" are not all real zeros
FLOAT_NEG_ZEROS  = 0x10   -- contains negative zeros
FLOAT_EXCEPTIONS = 0x20   -- contains exceptions (inf, nan, etc.)


ID_OPTIONAL_DATA      =  0x20
ID_ODD_SIZE           =  0x40
ID_LARGE              =  0x80

MAX_NTERMS = 16
MAX_TERM = 8

MAG_LSB = 18
MAG_MASK = bit32.lshift(0x1F, MAG_LSB)

ID_RIFF_HEADER   = 0x21
ID_RIFF_TRAILER  = 0x22
ID_REPLAY_GAIN   = 0x23
ID_CUESHEET      = 0x24
ID_CONFIG_BLOCK    = 0x25
ID_MD5_CHECKSUM  = 0x26
ID_SAMPLE_RATE   = 0x27

CONFIG_BYTES_STORED    = 3       -- 1-4 bytes/sample
CONFIG_MONO_FLAG       = 4       -- not stereo
CONFIG_HYBRID_FLAG     = 8       -- hybrid mode
CONFIG_JOINT_STEREO    = 0x10    -- joint stereo
CONFIG_CROSS_DECORR    = 0x20    -- no-delay cross decorrelation
CONFIG_HYBRID_SHAPE    = 0x40    -- noise shape (hybrid mode only)
CONFIG_FLOAT_DATA      = 0x80    -- ieee 32-bit floating point data
CONFIG_FAST_FLAG       = 0x200   -- fast mode
CONFIG_HIGH_FLAG       = 0x800   -- high quality mode
CONFIG_VERY_HIGH_FLAG  = 0x1000  -- very high
CONFIG_BITRATE_KBPS    = 0x2000  -- bitrate is kbps, not bits / sample
CONFIG_AUTO_SHAPING    = 0x4000  -- automatic noise shaping
CONFIG_SHAPE_OVERRIDE  = 0x8000  -- shaping mode specified
CONFIG_JOINT_OVERRIDE  = 0x10000 -- joint-stereo mode specified
CONFIG_CREATE_EXE      = 0x40000 -- create executable
CONFIG_CREATE_WVC      = 0x80000 -- create correction file
CONFIG_OPTIMIZE_WVC    = 0x100000 -- maximize bybrid compression
CONFIG_CALC_NOISE      = 0x800000 -- calc noise in hybrid mode
CONFIG_LOSSY_MODE      = 0x1000000 -- obsolete (for information)
CONFIG_EXTRA_MODE      = 0x2000000 -- extra processing mode
ONFIG_SKIP_WVX        = 0x4000000 -- no wvx stream w/ floats & big ints
CONFIG_MD5_CHECKSUM    = 0x8000000 -- compute & store MD5 signature
CONFIG_OPTIMIZE_MONO   = 0x80000000 -- optimize for mono streams posing as stereo

MODE_WVC        = 0x1
MODE_LOSSLESS   = 0x2
MODE_HYBRID     = 0x4
MODE_FLOAT      = 0x8
MODE_VALID_TAG  = 0x10
MODE_HIGH       = 0x20
MODE_FAST       = 0x40


sample_rates = {6000, 8000, 9600, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 64000, 88200, 96000, 192000}


LIMIT_ONES = 16  -- maximum consecutive 1s sent for "div" data

-- these control the time constant "slow_level" which is used for hybrid mode
-- that controls bitrate as a function of residual level (HYBRID_BITRATE).
SLS = 8
SLO = bit32.lshift(1,(SLS-1))


-- these control the time constant of the 3 median level breakpoints
DIV0 = 128   -- 5/7 of samples
DIV1 = 64    -- 10/49 of samples
DIV2 = 32    -- 20/343 of samples



nbits_table = {
0, 1, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4,      -- 0 - 15
5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,      -- 16 - 31
6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,      -- 32 - 47
6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,      -- 48 - 63
7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,      -- 64 - 79
7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,      -- 80 - 95
7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,      -- 96 - 111
7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,      -- 112 - 127
8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,      -- 128 - 143
8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,      -- 144 - 159
8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,      -- 160 - 175
8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,      -- 176 - 191
8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,      -- 192 - 207
8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,      -- 208 - 223
8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,      -- 224 - 239
8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8}      -- 240 - 255



log2_table = {
0x00, 0x01, 0x03, 0x04, 0x06, 0x07, 0x09, 0x0a, 0x0b, 0x0d, 0x0e, 0x10, 0x11, 0x12, 0x14, 0x15,
0x16, 0x18, 0x19, 0x1a, 0x1c, 0x1d, 0x1e, 0x20, 0x21, 0x22, 0x24, 0x25, 0x26, 0x28, 0x29, 0x2a,
0x2c, 0x2d, 0x2e, 0x2f, 0x31, 0x32, 0x33, 0x34, 0x36, 0x37, 0x38, 0x39, 0x3b, 0x3c, 0x3d, 0x3e,
0x3f, 0x41, 0x42, 0x43, 0x44, 0x45, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4d, 0x4e, 0x4f, 0x50, 0x51,
0x52, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5c, 0x5d, 0x5e, 0x5f, 0x60, 0x61, 0x62, 0x63,
0x64, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x74, 0x75,
0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0x7f, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85,
0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95,
0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4,
0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb2,
0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xb9, 0xba, 0xbb, 0xbc, 0xbd, 0xbe, 0xbf, 0xc0, 0xc0,
0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xcb, 0xcb, 0xcc, 0xcd, 0xce,
0xcf, 0xd0, 0xd0, 0xd1, 0xd2, 0xd3, 0xd4, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd8, 0xd9, 0xda, 0xdb,
0xdc, 0xdc, 0xdd, 0xde, 0xdf, 0xe0, 0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0xe4, 0xe5, 0xe6, 0xe7, 0xe7,
0xe8, 0xe9, 0xea, 0xea, 0xeb, 0xec, 0xed, 0xee, 0xee, 0xef, 0xf0, 0xf1, 0xf1, 0xf2, 0xf3, 0xf4,
0xf4, 0xf5, 0xf6, 0xf7, 0xf7, 0xf8, 0xf9, 0xf9, 0xfa, 0xfb, 0xfc, 0xfc, 0xfd, 0xfe, 0xff, 0xff}


exp2_table = {
0x00, 0x01, 0x01, 0x02, 0x03, 0x03, 0x04, 0x05, 0x06, 0x06, 0x07, 0x08, 0x08, 0x09, 0x0a, 0x0b,
0x0b, 0x0c, 0x0d, 0x0e, 0x0e, 0x0f, 0x10, 0x10, 0x11, 0x12, 0x13, 0x13, 0x14, 0x15, 0x16, 0x16,
0x17, 0x18, 0x19, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1d, 0x1e, 0x1f, 0x20, 0x20, 0x21, 0x22, 0x23,
0x24, 0x24, 0x25, 0x26, 0x27, 0x28, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2c, 0x2d, 0x2e, 0x2f, 0x30,
0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3a, 0x3b, 0x3c, 0x3d,
0x3e, 0x3f, 0x40, 0x41, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x48, 0x49, 0x4a, 0x4b,
0x4c, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a,
0x5b, 0x5c, 0x5d, 0x5e, 0x5e, 0x5f, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0x7f, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x87, 0x88, 0x89, 0x8a,
0x8b, 0x8c, 0x8d, 0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b,
0x9c, 0x9d, 0x9f, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad,
0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xbc, 0xbd, 0xbe, 0xbf, 0xc0,
0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc8, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf, 0xd0, 0xd2, 0xd3, 0xd4,
0xd6, 0xd7, 0xd8, 0xd9, 0xdb, 0xdc, 0xdd, 0xde, 0xe0, 0xe1, 0xe2, 0xe4, 0xe5, 0xe6, 0xe8, 0xe9,
0xea, 0xec, 0xed, 0xee, 0xf0, 0xf1, 0xf2, 0xf4, 0xf5, 0xf6, 0xf8, 0xf9, 0xfa, 0xfc, 0xfd, 0xff }



ones_count_table = {
0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,5,
0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,6,
0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,5,
0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,7,
0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,5,
0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,6,
0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,5,
0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,8}


entropy_data = {}		
function entropy_data:new()
	local object = {
		slow_level = 0,
		median = {},
		error_limit = 0
	}
	object.median[0] = 0
	object.median[1] = 0
	object.median[2] = 0

	setmetatable(object,self)
	self.__index = self
	return object
end			

words_data = {
    bitrate_delta = {},
    bitrate_acc = {},
    pend_data = 0,
    holding_one = 0,
    zeros_acc = 0,
    holding_zero = 0,
    pend_count = 0,
    temp_ed1 = entropy_data:new(),
    temp_ed2 = entropy_data:new(),
    c = {}
}
function words_data:new()
	o = {}
	setmetatable(o,self)
	self.__index = self
	self.bitrate_delta[2] = 0
	self.bitrate_acc[2] = 0
	self.c[0] = self.temp_ed1
	self.c[1] = self.temp_ed2
	return o
end	

decorr_pass = {}
function decorr_pass:new()
	local object = {
		term = 0,
		delta = 0,
		weight_A = 0,
		weight_B = 0,
		samples_A = {},
		samples_B = {}
	}
	object.samples_A[MAX_TERM] = 0
	object.samples_B[MAX_TERM] = 0
	
	setmetatable(object,self)
	self.__index = self
	return object
end			

WavpackHeader = {
    ckID = {},
    ckSize = 0,    
    version = 0,
    track_no = 0,
    index_no = 0,   
    total_samples = 0,
    block_index = 0,
    block_samples = 0,
    flags = 0,
    crc = 0,    
    status = 0    -- 1 means error
}	
function WavpackHeader:new()
	o = {}
	setmetatable(o,self)
	self.__index = self
	self.ckID[4]=0
	return o
end

WavpackMetadata = {
    byte_length = 0,
    data = {},
    id = 0,
    hasdata = 0,    -- 0 does not have data, 1 has data
    status = 0    -- 0 ok, 1 error
}
function WavpackMetadata:new()
	o = {}
	setmetatable(o,self)
	self.__index = self
	self.data[1024] = 0
	return o
end

WavpackConfig = {
    bits_per_sample = 0,
    bytes_per_sample = 0,
    num_channels = 0,
    norm_exp = 0,
    flags = 0,
    sample_rate = 0,
    channel_mask = 0,
}
function WavpackConfig:new()
	o = {}
	setmetatable(o,self)
	self.__index = self
	return o
end	

Bitstream = {
    bs_end = 0,
    ptr = 0,
    file_bytes = 0,
    sr = 0,
    error = 0,
    bc = 0,
    file,
    bitval = 0,
    buf={},
    buf_index = 0
}
function Bitstream:new()
	o = {}
	setmetatable(o,self)
	self.__index = self
	self.buf[1024] = 0
	return o
end		


WavpackStream = {
    wphdr = WavpackHeader:new(),
    wvbits = Bitstream:new(),
    w = words_data:new(),

    num_terms = 0,
    mute_error = 0,
    sample_index = 0,
    crc = 0,

    int32_sent_bits = 0,
    int32_zeros = 0,
    int32_ones = 0,
    int32_dups = 0, 
    float_flags = 0,
    float_shift = 0,
    float_max_exp = 0,
    float_norm_exp = 0,
     
    dp1 =  decorr_pass:new(),
    dp2 =  decorr_pass:new(),
    dp3 =  decorr_pass:new(),
    dp4 =  decorr_pass:new(),
    dp5 =  decorr_pass:new(),
    dp6 =  decorr_pass:new(),
    dp7 =  decorr_pass:new(),
    dp8 =  decorr_pass:new(),
    dp9 =  decorr_pass:new(),
    dp10 =  decorr_pass:new(),
    dp11 =  decorr_pass:new(),
    dp12 =  decorr_pass:new(),
    dp13 =  decorr_pass:new(),
    dp14 =  decorr_pass:new(),
    dp15 =  decorr_pass:new(),
    dp16 =  decorr_pass:new(),

	decorr_passes = {}

}
function WavpackStream:new()
	o = {}
	setmetatable(o,self)
	self.__index = self
	self.decorr_passes[0] = self.dp1
	self.decorr_passes[1] = self.dp2
	self.decorr_passes[2] = self.dp3
	self.decorr_passes[3] = self.dp4
	self.decorr_passes[4] = self.dp5
	self.decorr_passes[5] = self.dp6
	self.decorr_passes[6] = self.dp7
	self.decorr_passes[7] = self.dp8
	self.decorr_passes[8] = self.dp9
	self.decorr_passes[9] = self.dp10
	self.decorr_passes[10] = self.dp11
	self.decorr_passes[11] = self.dp12
	self.decorr_passes[12] = self.dp13
	self.decorr_passes[13] = self.dp14
	self.decorr_passes[14] = self.dp15
	self.decorr_passes[15] = self.dp16
	return o
end		

		
WavpackContext = {
    config = WavpackConfig:new(),
    stream = WavpackStream:new(),
    READ_BUFFER_SIZE = 1024,

    read_buffer = {},
    error_message = "",
    error = false,
    infile,
    total_samples = 0,
    crc_errors = 0,
    first_flags = 0,        
    open_flags = 0,
    norm_offset = 0,
    reduced_channels = 0,
    lossy_blocks = 0,
    status = 0    -- 0 ok, 1 error
}

function WavpackContext:new()
	o = {}
	setmetatable(o,self)
	self.__index = self
	self.read_buffer[self.READ_BUFFER_SIZE] = 0
	return o
end	

-- This function reads data from the specified stream in search of a valid
-- WavPack 4.0 audio block. If this fails in 1 megabyte (or an invalid or
-- unsupported WavPack block is encountered) then an appropriate message is
-- copied to "error" and NULL is returned, otherwise a pointer to a
-- WavpackContext structure is returned (which is used to call all other
-- functions in this module). This can be initiated at the beginning of a
-- WavPack file, or anywhere inside a WavPack file. To determine the exact
-- position within the file use WavpackGetSampleIndex().  Also,
-- this function will not handle "correction" files, plays only the first
-- two channels of multi-channel files, and is limited in resolution in some
-- large integer or floating point files (but always provides at least 24 bits
-- of resolution).


function WavpackOpenFileInput(infile)
    wpc = WavpackContext:new()
    wps = wpc.stream

    wpc.infile = infile
    wpc.total_samples = -1
    wpc.norm_offset = 0
    wpc.open_flags = 0
	
    -- open the source file for reading and store the size

    while (wps.wphdr.block_samples == 0) do
        wps.wphdr = read_next_header(wpc.infile, wps.wphdr)

        if (wps.wphdr.status == 1) then
            wpc.error_message = "not compatible with this version of WavPack file!"
            wpc.error = true
            return (wpc)
		end	

        if (wps.wphdr.block_samples > 0 and wps.wphdr.total_samples ~= -1) then
            wpc.total_samples = wps.wphdr.total_samples
		end	

        -- lets put the stream back in the context

        wpc.stream = wps

        if ((unpack_init(wpc)) == false) then
            wpc.error = true
            return wpc
		end
		
	end

	wpc.config.flags = bit32.band(wpc.config.flags, bit32.bnot(0xFF))
	wpc.config.flags = bit32.bor(wpc.config.flags, bit32.band(wps.wphdr.flags, 0xff))

	wpc.config.bytes_per_sample = bit32.band(wps.wphdr.flags, BYTES_STORED) + 1
    wpc.config.float_norm_exp = wps.float_norm_exp

	wpc.config.bits_per_sample = ((wpc.config.bytes_per_sample * 8) - bit32.rshift(bit32.band(wps.wphdr.flags,SHIFT_MASK), SHIFT_LSB))

	if (bit32.btest(wpc.config.flags, FLOAT_DATA)) then
        wpc.config.bytes_per_sample = 3
        wpc.config.bits_per_sample = 24
	end	

    if (wpc.config.sample_rate == 0) then
        if (wps.wphdr.block_samples == 0 or bit32.band(wps.wphdr.flags, SRATE_MASK) == SRATE_MASK) then
            wpc.config.sample_rate = 44100
        else
            wpc.config.sample_rate = sample_rates[(bit32.rshift(bit32.band(wps.wphdr.flags,SRATE_MASK), SRATE_LSB))+1]
		end
	end

    if (wpc.config.num_channels == 0) then
		if (bit32.btest(wps.wphdr.flags, MONO_FLAG)) then
            wpc.config.num_channels = 1
        else
            wpc.config.num_channels = 2
		end	

        wpc.config.channel_mask = 0x5 - wpc.config.num_channels
	end	
	
	if(bit32.band(wps.wphdr.flags, FINAL_BLOCK) == 0 ) then
		if (bit32.band(wps.wphdr.flags, MONO_FLAG) ~= 0) then
            wpc.reduced_channels = 1
        else
            wpc.reduced_channels = 2
		end	
	end

    return wpc
end		

-- This function obtains general information about an open file and returns
-- a mask with the following bit values:

-- MODE_LOSSLESS:  file is lossless (pure lossless only)
-- MODE_HYBRID:  file is hybrid mode (lossy part only)
-- MODE_FLOAT:  audio data is 32-bit ieee floating point (but will provided
--               in 24-bit integers for convenience)
-- MODE_HIGH:  file was created in "high" mode (information only)
-- MODE_FAST:  file was created in "fast" mode (information only)


function WavpackGetMode (wpc)
    
    mode = 0

    if (nil ~= wpc) then 
        if ( bit32.band(wpc.config.flags, CONFIG_HYBRID_FLAG) ~= 0) then
            mode = bit32.bor(mode,MODE_HYBRID)
        elseif (bit32.band(wpc.config.flags, CONFIG_LOSSY_MODE)==0) then
            mode = bit32.bor(mode,MODE_LOSSLESS)
		end	

        if (wpc.lossy_blocks ~= 0) then
            mode = bit32.band(mode, bit32.bnot(MODE_LOSSLESS))
		end	

        if ( bit32.band(wpc.config.flags, CONFIG_FLOAT_DATA) ~= 0) then
            mode = bit32.bor(mode, MODE_FLOAT)
		end	

        if ( bit32.band(wpc.config.flags, CONFIG_HIGH_FLAG) ~= 0) then
            mode = bit32.bor(mode, MODE_HIGH)
		end	

        if ( bit32.band(wpc.config.flags, CONFIG_FAST_FLAG) ~= 0) then
            mode = bit32.bor(mode, MODE_FAST)
		end	
	end
	
    return mode
end

-- Unpack the specified number of samples from the current file position.
-- Note that "samples" here refers to "complete" samples, which would be
-- 2 longs for stereo files. The audio data is returned right-justified in
-- 32-bit longs in the endian mode native to the executing processor. So,
-- if the original data was 16-bit, then the values returned would be
-- +/-32k. Floating point data will be returned as 24-bit integers (and may
-- also be clipped). The actual number of samples unpacked is returned,
-- which should be equal to the number requested unless the end of fle is
-- encountered or an error occurs.

function  WavpackUnpackSamples(wpc, buffer, samples)
    wps = wpc.stream
    local samples_unpacked = 0
    local samples_to_unpack = 0
    local num_channels = wpc.config.num_channels
    local bcounter = 0

    local temp_buffer = {}
    local buf_idx = 0
    local bytes_returned = 0
	local tempcount = 0


    while (samples > 0) do
        if (wps.wphdr.block_samples == 0 or bit32.band(wps.wphdr.flags, INITIAL_BLOCK) == 0
            or wps.sample_index >= wps.wphdr.block_index + wps.wphdr.block_samples) then

            wps.wphdr = read_next_header(wpc.infile, wps.wphdr)

            if (wps.wphdr.status == 1) then
                break
			end	

            if (wps.wphdr.block_samples == 0 or wps.sample_index == wps.wphdr.block_index) then
                if ((unpack_init(wpc)) == false) then			
                    break
				end
			end
		end			

        if (wps.wphdr.block_samples == 0 or bit32.band(wps.wphdr.flags, INITIAL_BLOCK) == 0
            or wps.sample_index >= wps.wphdr.block_index + wps.wphdr.block_samples) then			
            goto continue
		end	

        if (wps.sample_index < wps.wphdr.block_index) then
            samples_to_unpack = wps.wphdr.block_index - wps.sample_index

            if (samples_to_unpack > samples) then
                samples_to_unpack = samples
			end	

            wps.sample_index = wps.sample_index + samples_to_unpack
            samples_unpacked = samples_unpacked + samples_to_unpack
            samples = samples - samples_to_unpack

            if (wpc.reduced_channels > 0) then
                samples_to_unpack = samples_to_unpack * wpc.reduced_channels
            else
                samples_to_unpack = samples_to_unpack * num_channels
			end	

            while (samples_to_unpack > 0) do
                temp_buffer[bcounter] = 0
                bcounter = bcounter + 1
                samples_to_unpack = samples_to_unpack - 1
			end	

            goto continue
		end		
	
        samples_to_unpack = wps.wphdr.block_index + wps.wphdr.block_samples - wps.sample_index

        if (samples_to_unpack > samples) then
            samples_to_unpack = samples
		end	

        for mycleanup = 0,256 ,1 do
            temp_buffer[mycleanup] = 0
		end	
        
        unpack_samples(wpc, temp_buffer, samples_to_unpack)

        if (wpc.reduced_channels > 0) then
            bytes_returned = (samples_to_unpack * wpc.reduced_channels)
        else
            bytes_returned = (samples_to_unpack * num_channels)
		end	

        tempcount = 0
        for mycount = buf_idx, buf_idx+bytes_returned-1, 1 do
            buffer[mycount] = temp_buffer[tempcount]
            tempcount = tempcount + 1
		end	

        buf_idx = buf_idx + bytes_returned

        samples_unpacked = samples_unpacked + samples_to_unpack
        samples = samples - samples_to_unpack

        if (wps.sample_index == wps.wphdr.block_index + wps.wphdr.block_samples) then
            if (check_crc_error(wpc) > 0) then
                wpc.crc_errors = wpc.crc_errors + 1
			end	
		end	

        if (wps.sample_index == wpc.total_samples) then	
            break
		end
	::continue::
	end
    return (samples_unpacked)
end

-- Get total number of samples contained in the WavPack file, or -1 if unknown

function WavpackGetNumSamples(wpc)
    -- -1 would mean an unknown number of samples

    if( nil ~= wpc) then
        return (wpc.total_samples)
    else
        return -1
	end	
end

-- Get the current sample index position, or -1 if unknown

function WavpackGetSampleIndex (wpc)
    if (nil ~= wpc) then
        return wpc.stream.sample_index
	end
	
    return -1
end

-- Get the number of errors encountered so far

function WavpackGetNumErrors(wpc)
    if( nil ~= wpc) then
        return wpc.crc_errors
    else
        return 0
	end	
end

-- return if any uncorrected lossy blocks were actually written or read

function WavpackLossyBlocks (wpc)
    if(nil ~= wpc) then
         return wpc.lossy_blocks
    else 
        return 0
	end	
end

-- Returns the sample rate of the specified WavPack file

function WavpackGetSampleRate(wpc)
    if ( nil ~= wpc and wpc.config.sample_rate ~= 0) then
        return wpc.config.sample_rate
    else 
        return 44100
	end
end
        
-- Returns the number of channels of the specified WavPack file. Note that
-- this is the actual number of channels contained in the file, but this
-- version can only decode the first two.

function WavpackGetNumChannels(wpc)
    if ( nil ~= wpc and wpc.config.num_channels ~= 0) then
        return wpc.config.num_channels
    else
        return 2
	end	
end

-- Returns the actual number of valid bits per sample contained in the
-- original file, which may or may not be a multiple of 8. Floating data
-- always has 32 bits, integers may be from 1 to 32 bits each. When this
-- value is not a multiple of 8, then the "extra" bits are located in the
-- LSBs of the results. That is, values are right justified when unpacked
-- into longs, but are left justified in the number of bytes used by the
-- original data.

function WavpackGetBitsPerSample(wpc)
    if (nil ~= wpc and wpc.config.bits_per_sample ~= 0) then
        return wpc.config.bits_per_sample
    else
        return 16
	end	
end

-- Returns the number of bytes used for each sample (1 to 4) in the original
-- file. This is required information for the user of this module because the
-- audio data is returned in the LOWER bytes of the long buffer and must be
-- left-shifted 8, 16, or 24 bits if normalized longs are required.

function WavpackGetBytesPerSample(wpc) 
    if ( nil ~= wpc and wpc.config.bytes_per_sample ~= 0) then
        return wpc.config.bytes_per_sample
    else
        return 2
	end	
end

-- This function will return the actual number of channels decoded from the
-- file (which may or may not be less than the actual number of channels, but
-- will always be 1 or 2). Normally, this will be the front left and right
-- channels of a multi-channel file.

function WavpackGetReducedChannels(wpc)
    if (nil ~= wpc and wpc.reduced_channels ~= 0) then
        return wpc.reduced_channels
    elseif (nil ~= wpc and wpc.config.num_channels ~= 0) then
        return wpc.config.num_channels
    else
        return 2
	end	
end

-- Read from current file position until a valid 32-byte WavPack 4.0 header is
-- found and read into the specified pointer. If no WavPack header is found within 1 meg,
-- then an error is returned. No additional bytes are read past the header. 

function read_next_header(infile, wphdr)
	local buffer = {}
    buffer[32] = 0 -- 32 is the size of a WavPack Header

    local bytes_skipped = 0
    local bleft = 0  -- bytes left in buffer
    local counter = 0

    while (true) do
		for i =0,bleft-1,1 do
            buffer[i] = buffer[32 - bleft + i]
		end

        counter = 0

        local temp = infile:read(32 - bleft)
        if not temp then
            wphdr.status = 1
            return wphdr
		end
		
        -- Check if we are at the end of the file
		-- # gives the length
        if #temp < (32-bleft) then
            wphdr.status = 1
            return wphdr
		end

		for i=0, (32-bleft)-1,1 do
            buffer[bleft + i] = string.byte(temp,(i+1))
		end

        bleft = 32

        local buf4 = (buffer[4])
        local buf6 = (buffer[6])
        local buf7 = (buffer[7])
        local buf8 = (buffer[8])
        local buf9 = (buffer[9])
        
		-- wvpk = 119,118,112,107
        if  buffer[0] == 119 and buffer[1] == 118 and buffer[2] == 112 and buffer[3] == 107 and bit32.band(buf4,1) == 0 and buf6 < 16 and buf7 == 0 and buf9 == 4 and buf8 >= bit32.band(MIN_STREAM_VERS,0xff) and buf8 <= bit32.band(MAX_STREAM_VERS,0xff) then
            wphdr.ckID[0] = 'w'
            wphdr.ckID[1] = 'v'
            wphdr.ckID[2] = 'p'
            wphdr.ckID[3] = 'k'

            wphdr.ckSize =  bit32.lshift(bit32.band(buffer[7],0xFF),24)
            wphdr.ckSize = wphdr.ckSize + bit32.lshift(bit32.band(buffer[6], 0xFF), 16)
            wphdr.ckSize = wphdr.ckSize + bit32.lshift(bit32.band(buffer[5], 0xFF), 8)
            wphdr.ckSize = wphdr.ckSize + bit32.band(buffer[4], 0xFF)

            wphdr.version =  bit32.lshift(buffer[9], 8)
            wphdr.version = wphdr.version + buffer[8]

            wphdr.track_no = buffer[10]
            wphdr.index_no = buffer[11]

            wphdr.total_samples =  bit32.lshift(bit32.band(buffer[15], 0xFF), 24)
            wphdr.total_samples = wphdr.total_samples + bit32.lshift(bit32.band(buffer[14], 0xFF), 16)
            wphdr.total_samples = wphdr.total_samples + bit32.lshift(bit32.band(buffer[13], 0xFF), 8)
            wphdr.total_samples = wphdr.total_samples + bit32.band(buffer[12], 0xFF)

            wphdr.block_index =  bit32.lshift(bit32.band(buffer[19], 0xFF), 24)
            wphdr.block_index = wphdr.block_index + bit32.lshift(bit32.band(buffer[18], 0xFF), 16)
            wphdr.block_index = wphdr.block_index + bit32.lshift(bit32.band(buffer[17], 0xFF), 8)
            wphdr.block_index = wphdr.block_index + bit32.band(buffer[16], 0xFF)

            wphdr.block_samples =  bit32.lshift(bit32.band(buffer[23], 0xFF), 24)
            wphdr.block_samples = wphdr.block_samples + bit32.lshift(bit32.band(buffer[22], 0xFF), 16)
            wphdr.block_samples = wphdr.block_samples + bit32.lshift(bit32.band(buffer[21], 0xFF), 8)
            wphdr.block_samples = wphdr.block_samples + bit32.band(buffer[20], 0XFF)

            wphdr.flags =  bit32.lshift(bit32.band(buffer[27], 0xFF), 24)
            wphdr.flags = wphdr.flags + bit32.lshift(bit32.band(buffer[26], 0xFF), 16)
            wphdr.flags = wphdr.flags + bit32.lshift(bit32.band(buffer[25], 0xFF), 8)
            wphdr.flags = wphdr.flags + bit32.band(buffer[24], 0xFF)

            wphdr.crc =  bit32.lshift(bit32.band(buffer[31], 0xFF), 24)
            wphdr.crc = wphdr.crc + bit32.lshift(bit32.band(buffer[30], 0xFF), 16)
            wphdr.crc = wphdr.crc + bit32.lshift(bit32.band(buffer[29], 0xFF), 8)
            wphdr.crc = wphdr.crc + bit32.band(buffer[28], 0xFF)

            wphdr.status = 0

            return wphdr
        else
            counter = counter + 1
            bleft = bleft - 1
		end

        while (bleft > 0 and buffer[counter] ~= 119) do
            counter = counter + 1
            bleft = bleft - 1
		end	

        bytes_skipped = bytes_skipped + counter

        if (bytes_skipped > 1048576) then	
            wphdr.status = 1
            return wphdr
		end	
	end		
end

function getbit(bs)			
    local uns_buf = 0

    if (bs.bc > 0) then
        bs.bc = bs.bc - 1
    else
        bs.ptr = bs.ptr + 1
        bs.buf_index = bs.buf_index + 1
        bs.bc = 7

        if (bs.ptr == bs.bs_end) then
            -- wrap call here			
            bs = bs_read(bs)
		end
		
        uns_buf = bit32.band(bs.buf[bs.buf_index], 0xff)
        bs.sr = uns_buf
	end
		
    bs.bitval = bit32.band(bs.sr, 1)
    bs.sr = bit32.rshift(bs.sr, 1)

    return bs
end	

function getbits(nbits, bs)
    local uns_buf = 0
    local value = 0

    while (nbits > bs.bc) do
        bs.ptr = bs.ptr + 1
        bs.buf_index = bs.buf_index + 1

        if (bs.ptr == bs.bs_end) then
            bs = bs_read(bs)
		end	
        uns_buf = bit32.band(bs.buf[bs.buf_index], 0xff)
        bs.sr = bit32.bor(bs.sr, bit32.lshift(uns_buf, bs.bc)) -- values in buffer must be unsigned
        bs.sr = bit32.band(bs.sr, 0xffffffff) -- bs.sr is unsigned 32 bit
        bs.bc = bs.bc + 8
	end

    value = bs.sr

    if (bs.bc > 32) then
        bs.bc = bs.bc - nbits
        bs.sr = bit32.rshift(bit32.band(bs.buf[bs.buf_index], 0xff), (8 - bs.bc))
    else 
        bs.bc = bs.bc - nbits
        bs.sr = bit32.rshift(bs.sr,nbits)
	end	

    return (value)
end

function bs_open_read(stream, buffer_start, buffer_end, file, file_bytes, passed) 
    bs = Bitstream:new()

	for i =0, (#stream - 1), 1 do
		bs.buf[i] = string.byte(stream,(i+1))
	end
    bs.buf_index = buffer_start
    bs.bs_end = buffer_end
    bs.sr = 0
    bs.bc = 0

    if (passed ~= 0) then
        bs.ptr = bs.bs_end - 1
        bs.file_bytes = file_bytes
        bs.file = file
    else 
        -- Strange to set an index to -1, but the very first call to getbit will iterate this 
        bs.buf_index = -1
        bs.ptr = -1
	end
	
    return bs
end

function bs_read(bs)
    if (bs.file_bytes > 0) then
        bytes_read = 0
        bytes_to_read = 1024

        if (bytes_to_read > bs.file_bytes) then
            bytes_to_read = bs.file_bytes
		end	

		temp = bs.file:read(bytes_to_read)
		if(nil==temp) then
			bytes_read = 0
		else
			internal_counter = 0
			for i=1,bytes_to_read,1 do
				bs.buf[internal_counter] = string.byte(temp,i)
				internal_counter = internal_counter + 1
			end	
			bytes_read = bytes_to_read
			bs.buf_index = 0
		end	


        if (bytes_read > 0) then
            bs.bs_end = bytes_read
            bs.file_bytes = bs.file_bytes - bytes_read
        else 
            for i = 0, bs.bs_end - bs.buf_index - 1, 1 do
                bs.buf[i] = -1
			end	
            bs.error = 1
		end	
    else 
        bs.error = 1
	end	

    if (bs.error > 0) then
        for i = 0,bs.bs_end - bs.buf_index - 1, 1 do
            bs.buf[i] = -1
		end	
	end
	
    bs.ptr = 0
    bs.buf_index = 0

    return bs
end

function read_float_info (wps, wpmd) 
    local bytecnt = wpmd.byte_length
    local byteptr = wpmd.data
    local counter = 1

    if bytecnt ~= 4 then
        return false
	end	

    wps.float_flags = string.byte(byteptr,counter)
    counter = counter + 1
    wps.float_shift = string.byte(byteptr,counter)
    counter = counter + 1
    wps.float_max_exp = string.byte(byteptr,counter)
    counter = counter + 1
    wps.float_norm_exp = string.byte(byteptr,counter)

    return true
end

function float_values (wps, values, num_values)
    local shift = wps.float_max_exp - wps.float_norm_exp + wps.float_shift
    local value_counter = 0

    if (shift > 32) then
        shift = 32
    elseif (shift < -32) then
        shift = -32
	end	

    while (num_values>0) do
        if (shift > 0) then
            values[value_counter] = bit32.lshift(values[value_counter],shift)
        elseif (shift < 0) then
            --values[value_counter] = bit32.rshift(values[value_counter], -shift)
			values[value_counter] = signed_rshift(values[value_counter], -shift)
		end	

        if (values[value_counter] > 8388607) then
            values[value_counter] = 8388607
        elseif (values[value_counter] < -8388608) then
            values[value_counter] = -8388608
		end	

        value_counter = value_counter + 1
        num_values = num_values - 1
	end	

    return values
end

function read_metadata_buff(wpc, wpmd)
    local bytes_to_read = 0
	local bytes_read = 0
    local tchar = 0

    wpmd.id = wpc.infile:read(1)
    tchar =   wpc.infile:read(1)
    
	if(wpmd.id == nil or tchar == nil) then
        wpmd.status = 1
        return false
	end
	
	wpmd.id = string.byte(wpmd.id)
    tchar =   string.byte(tchar)

    wpmd.byte_length = bit32.lshift(tchar, 1)

    if (bit32.band(wpmd.id, ID_LARGE) ~= 0) then
        wpmd.id = bit32.band(wpmd.id, bit32.bnot(ID_LARGE))

        tchar = wpc.infile:read(1)
		
        if(tchar == nil) then
            wpmd.status = 1
            return false
		end

		tchar = string.byte(tchar)

        wpmd.byte_length = wpmd.byte_length + bit32.lshift(tchar, 9)

        tchar = wpc.infile:read(1)
        if(tchar == nil) then
            wpmd.status = 1
            return false
		end
		
		tchar = string.byte(tchar)

        wpmd.byte_length = wpmd.byte_length + bit32.lshift(tchar, 17)
	end	

    if (bit32.band(wpmd.id, ID_ODD_SIZE) ~= 0) then
        wpmd.id = bit32.band(wpmd.id, bit32.bnot(ID_ODD_SIZE))
        wpmd.byte_length = wpmd.byte_length - 1
	end	

    if (wpmd.byte_length == 0 or wpmd.id == ID_WV_BITSTREAM) then
        wpmd.hasdata = false
        return true
	end	

    bytes_to_read = wpmd.byte_length + bit32.band(wpmd.byte_length, 1)
    
    if (bytes_to_read > wpc.READ_BUFFER_SIZE) then
        bytes_read = 0
        wpmd.hasdata = false

        while (bytes_to_read > wpc.READ_BUFFER_SIZE) do

            wpc.read_buffer = wpc.infile:read( wpc.READ_BUFFER_SIZE )
			if(wpc.read_buffer == nil) then
				return false
			end
			
            bytes_read = #wpc.read_buffer
            if(bytes_read ~= wpc.READ_BUFFER_SIZE) then
                return false
			end	

            bytes_to_read = bytes_to_read - wpc.READ_BUFFER_SIZE
		end	
    else
        wpmd.hasdata = true
        wpmd.data = wpc.read_buffer
	end	

    if (bytes_to_read ~= 0) then
        bytes_read = 0

        wpc.read_buffer = wpc.infile:read(bytes_to_read)
		if(wpc.read_buffer == nil) then
			wpmd.hasdata = false
			return false
		end
        wpmd.data = wpc.read_buffer
        bytes_read = #wpc.read_buffer
		if(bytes_read ~=  bytes_to_read) then
            wpmd.hasdata = false
            return false
		end	

	end		

    return true
end	


function process_metadata(wpc, wpmd) 
    wps = wpc.stream

    if(wpmd.id == ID_DUMMY) then
        return true

    elseif (wpmd.id == ID_DECORR_TERMS) then
        return read_decorr_terms(wps, wpmd)

    elseif (wpmd.id == ID_DECORR_WEIGHTS) then
        return read_decorr_weights(wps, wpmd)

    elseif (wpmd.id == ID_DECORR_SAMPLES) then
        return read_decorr_samples(wps, wpmd)

    elseif (wpmd.id == ID_ENTROPY_VARS) then
        return read_entropy_vars(wps, wpmd)

    elseif (wpmd.id == ID_HYBRID_PROFILE) then
        return read_hybrid_profile(wps, wpmd)

    elseif (wpmd.id == ID_FLOAT_INFO) then
        return read_float_info(wps, wpmd)

    elseif (wpmd.id == ID_INT32_INFO) then
        return read_int32_info(wps, wpmd)

    elseif (wpmd.id == ID_CHANNEL_INFO) then
        return read_channel_info(wpc, wpmd)

    elseif (wpmd.id == ID_SAMPLE_RATE) then
        return read_sample_rate(wpc, wpmd)

    elseif (wpmd.id == ID_CONFIG_BLOCK) then
        return read_config_info(wpc, wpmd)

    elseif (wpmd.id == ID_WV_BITSTREAM) then
        return init_wv_bitstream(wpc, wpmd)
	
	elseif (wpmd.id == ID_SHAPING_WEIGHTS) then
        return true	

	elseif (wpmd.id == ID_WVC_BITSTREAM) then
        return true	

	elseif (wpmd.id == ID_WVX_BITSTREAM) then
        return true			
	
	else
        if (bit32.band(wpmd.id, ID_OPTIONAL_DATA) ~= 0) then
            return true
        else
            return false
		end
	end
end


-- This function initializes everything required to unpack a WavPack block
-- and must be called before unpack_samples() is called to obtain audio data.
-- It is assumed that the WavpackHeader has been read into the wps.wphdr
-- (in the current WavpackStream). This is where all the metadata blocks are
-- scanned up to the one containing the audio bitstream.

function unpack_init(wpc)
    wps = wpc.stream
    wpmd = WavpackMetadata:new()

    if (wps.wphdr.block_samples > 0 and wps.wphdr.block_index ~= -1) then
        wps.sample_index = wps.wphdr.block_index
	end	

    wps.mute_error = 0
    wps.crc = 0xffffffff
    wps.wvbits.sr = 0

    while ((read_metadata_buff(wpc, wpmd)) == true) do
        if ((process_metadata(wpc, wpmd)) == false) then
            wpc.error = true
            wpc.error_message = "invalid metadata!"
            return false
		end	

        if (wpmd.id == ID_WV_BITSTREAM) then
            break
		end
	end	

    
    if (wps.wphdr.block_samples ~= 0 and (None == wps.wvbits.file) ) then
        wpc.error_message = "invalid WavPack file!"
        wpc.error = true
        return false
	end	

    if (wps.wphdr.block_samples ~= 0) then
        if (bit32.band(wps.wphdr.flags, INT32_DATA) ~= 0 and wps.int32_sent_bits ~= 0) then
            wpc.lossy_blocks = 1
		end	

        if (bit32.band(wps.wphdr.flags, FLOAT_DATA) ~= 0 and bit32.band(wps.float_flags, bit32.bor(FLOAT_EXCEPTIONS, FLOAT_ZEROS_SENT, FLOAT_SHIFT_SENT, FLOAT_SHIFT_SAME)) ~= 0) then
            wpc.lossy_blocks = 1
		end
	end	

    wpc.error = false
    wpc.stream = wps
    return true
end	

-- This function initialzes the main bitstream for audio samples, which must
-- be in the "wv" file.

function init_wv_bitstream(wpc, wpmd)
    wps = wpc.stream

    if (wpmd.hasdata == true) then
        wps.wvbits = bs_open_read(wpmd.data, 0, wpmd.byte_length, wpc.infile, 0, 0)
    elseif (wpmd.byte_length > 0) then
        blen = bit32.band(wpmd.byte_length, 1)
        wps.wvbits = bs_open_read(wpc.read_buffer, -1, #wpc.read_buffer, wpc.infile, (wpmd.byte_length + blen), 1)
	end
    return true
end

-- Read decorrelation terms from specified metadata block into the
-- decorr_passes array. The terms range from -3 to 8, plus 17 & 18;
-- other values are reserved and generate errors for now. The delta
-- ranges from 0 to 7 with all values valid. Note that the terms are
-- stored in the opposite order in the decorr_passes array compared
-- to packing.

function read_decorr_terms(wps, wpmd)
    termcnt = wpmd.byte_length
    byteptr = wpmd.data
    local tmpwps = WavpackStream:new()
    
    local counter = 1		--arrays start at 1 in Lua

    if (termcnt > MAX_NTERMS) then
        return false
	end	
    
    tmpwps.num_terms = termcnt

    for dcounter = termcnt-1,0,-1 do
        tmpwps.decorr_passes[dcounter].term =   bit32.band(string.byte(byteptr,counter), 0x1f) - 5
        tmpwps.decorr_passes[dcounter].delta =  bit32.band(bit32.rshift(string.byte(byteptr,counter), 5), 0x7)
        
        counter = counter + 1
    
        if (tmpwps.decorr_passes[dcounter].term < -3 
            or (tmpwps.decorr_passes[dcounter].term > MAX_TERM and tmpwps.decorr_passes[dcounter].term < 17) 
            or tmpwps.decorr_passes[dcounter].term > 18) then
            return false
		end	

	end
	
    wps.decorr_passes = tmpwps.decorr_passes
    wps.num_terms = tmpwps.num_terms

    return true
end
	
-- Read decorrelation weights from specified metadata block into the
-- decorr_passes array. The weights range +/-1024, but are rounded and
-- truncated to fit in signed chars for metadata storage. Weights are
-- separate for the two channels and are specified from the "last" term
-- (first during encode). Unspecified weights are set to zero.

function read_decorr_weights(wps, wpmd)
    local termcnt = wpmd.byte_length
    local tcount = 0
    local byteptr = wpmd.data
    local dpp = decorr_pass:new()
    local counter = 1	
    local dpp_idx = 0
    local myiterator = 0

    if (bit32.band(wps.wphdr.flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then
		termcnt = termcnt / 2
	end

    if (termcnt > wps.num_terms) then
        return false
	end	
	
	-- need to ensure all weights are reset to 0 before starting
	for internalc=0,MAX_NTERMS-1,1 do
        wps.decorr_passes[internalc].weight_A = 0
        wps.decorr_passes[internalc].weight_B = 0
	end

    myiterator = wps.num_terms
	
    while (termcnt > 0) do
        dpp_idx = myiterator - 1
        
        -- We need the input to restore_weight to be a signed value
        
        signedCalc1 = string.byte(byteptr, counter)

        if bit32.band(signedCalc1, 0x80) == 0x80 then
            signedCalc1 = bit32.band(signedCalc1, 0x7F)
            signedCalc1 = signedCalc1 - 0x80
		end	
                
        dpp.weight_A = restore_weight(signedCalc1)

        wps.decorr_passes[dpp_idx].weight_A = dpp.weight_A

        counter = counter + 1

        if (bit32.band(wps.wphdr.flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then
            -- We need the input to restore_weight to be a signed value

            signedCalc1 = string.byte(byteptr,counter)

            if bit32.band(signedCalc1, 0x80) == 0x80 then
                signedCalc1 = bit32.band(signedCalc1, 0x7F)
                signedCalc1 = signedCalc1 - 0x80
			end

            dpp.weight_B = restore_weight( signedCalc1 )
            counter = counter + 1
		end	

        wps.decorr_passes[dpp_idx].weight_B = dpp.weight_B

        myiterator = myiterator - 1
        termcnt = termcnt - 1
	end
	
    dpp_idx = dpp_idx - 1
    while dpp_idx >= 0 do
        wps.decorr_passes[dpp_idx].weight_A = 0
        wps.decorr_passes[dpp_idx].weight_B = 0
        dpp_idx = dpp_idx - 1
	end
	
    return true
end

-- Read decorrelation samples from specified metadata block into the
-- decorr_passes array. The samples are signed 32-bit values, but are
-- converted to signed log2 values for storage in metadata. Values are
-- stored for both channels and are specified from the "last" term
-- (first during encode) with unspecified samples set to zero. The
-- number of samples stored varies with the actual term value, so
-- those must obviously come first in the metadata.

function read_decorr_samples(wps, wpmd)
    byteptr = wpmd.data
    local dpp = decorr_pass:new()
    local counter = 1
    local dpp_index = 0
    local uns_buf0 = 0
    local uns_buf1 = 0
    local uns_buf2 = 0
    local uns_buf3 = 0

	for tcount = 0, wps.num_terms-1,1 do
        dpp.term = wps.decorr_passes[dpp_index].term

        for internalc=0,MAX_TERM-1,1 do
            dpp.samples_A[internalc] = 0
            dpp.samples_B[internalc] = 0
            wps.decorr_passes[dpp_index].samples_A[internalc] = 0
            wps.decorr_passes[dpp_index].samples_B[internalc] = 0
		end
		
        dpp_index = dpp_index + 1 
	end

    if (wps.wphdr.version == 0x402 and bit32.band(wps.wphdr.flags, HYBRID_FLAG) ~= 0) then
        counter = counter + 2

        if (bit32.band(wps.wphdr.flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then
            counter = counter + 2
		end
	end
	
    dpp_index = dpp_index - 1
 
    while (counter <= wpmd.byte_length) do
        if (dpp.term > MAX_TERM) then
		
            uns_buf0 =  bit32.band(string.byte(byteptr,counter), 0xff)
            uns_buf1 =  bit32.band(string.byte(byteptr,(counter + 1)), 0xff)
            uns_buf2 =  bit32.band(string.byte(byteptr,(counter + 2)), 0xff)
            uns_buf3 =  bit32.band(string.byte(byteptr,(counter + 3)), 0xff)

            -- We need to convert to 16-bit signed values
            -- 0x8000 represents the left most bit in a 16-bit value
            -- 0x7fff masks all bits except the leftmost in 16 bits
            
            signedCalc1 = uns_buf0 + bit32.lshift(uns_buf1, 8)
            if bit32.band(signedCalc1, 0x8000) == 0x8000 then
                signedCalc1 = bit32.band(signedCalc1, 0x7FFF)
                signedCalc1 = signedCalc1 - 0x8000
			end	

            signedCalc2 = uns_buf2 + bit32.lshift(uns_buf3, 8)
            if bit32.band(signedCalc2, 0x8000) == 0x8000 then
                signedCalc2 = bit32.band(signedCalc2, 0x7FFF)
                signedCalc2 = signedCalc2 - 0x8000
			end	

            dpp.samples_A[0] = exp2s( signedCalc1 )
            dpp.samples_A[1] = exp2s( signedCalc2 )
			
            counter = counter + 4

            if (bit32.band(wps.wphdr.flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then
                uns_buf0 =  bit32.band(string.byte(byteptr,counter), 0xff)
                uns_buf1 =  bit32.band(string.byte(byteptr,(counter + 1)), 0xff)
                uns_buf2 =  bit32.band(string.byte(byteptr,(counter + 2)), 0xff)
                uns_buf3 =  bit32.band(string.byte(byteptr,(counter + 3)), 0xff)

                signedCalc1 = uns_buf0 + bit32.lshift(uns_buf1, 8)
                if bit32.band(signedCalc1, 0x8000) == 0x8000 then
                    signedCalc1 = bit32.band(signedCalc1, 0x7FFF)
                    signedCalc1 = signedCalc1 - 0x8000
				end	

                signedCalc2 = uns_buf2 + bit32.lshift(uns_buf3, 8)
                if bit32.band(signedCalc2, 0x8000) == 0x8000 then
                    signedCalc2 = bit32.band(signedCalc2, 0x7FFF)
                    signedCalc2 = signedCalc2 - 0x8000
				end
					
                dpp.samples_B[0] = exp2s( signedCalc1 )
                dpp.samples_B[1] = exp2s( signedCalc2 )
				
                counter = counter + 4
			end
			
        elseif (dpp.term < 0) then
            
            uns_buf0 =  bit32.band(string.byte(byteptr,counter), 0xff)
            uns_buf1 =  bit32.band(string.byte(byteptr,(counter + 1)), 0xff)
            uns_buf2 =  bit32.band(string.byte(byteptr,(counter + 2)), 0xff)
            uns_buf3 =  bit32.band(string.byte(byteptr,(counter + 3)), 0xff)

            signedCalc1 = uns_buf0 + bit32.lshift(uns_buf1, 8)
            if bit32.band(signedCalc1, 0x8000) == 0x8000 then
                signedCalc1 = bit32.band(signedCalc1, 0x7FFF)
                signedCalc1 = signedCalc1 - 0x8000
			end	
                
            signedCalc2 = uns_buf2 + bit32.lshift(uns_buf3, 8)
            if bit32.band(signedCalc2, 0x8000) == 0x8000 then
                signedCalc2 = bit32.band(signedCalc2, 0x7FFF)
                signedCalc2 = signedCalc2 - 0x8000
			end
			
            dpp.samples_A[0] = exp2s( signedCalc1 )
            dpp.samples_B[0] = exp2s( signedCalc2 )

            counter = counter + 4
        else

            m = 0
            cnt = dpp.term

            while (cnt > 0) do
                uns_buf0 =  bit32.band(string.byte(byteptr,counter), 0xff)
                uns_buf1 =  bit32.band(string.byte(byteptr,(counter + 1)), 0xff)

                signedCalc1 = uns_buf0 + bit32.lshift(uns_buf1, 8)
                if bit32.band(signedCalc1, 0x8000) == 0x8000 then
                    signedCalc1 = bit32.band(signedCalc1, 0x7FFF)
                    signedCalc1 = signedCalc1 - 0x8000
				end	

                dpp.samples_A[m] = exp2s(signedCalc1)
                counter = counter + 2

                if (bit32.band(wps.wphdr.flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then
                    uns_buf0 =  bit32.band(string.byte(byteptr,counter), 0xff)
                    uns_buf1 =  bit32.band(string.byte(byteptr,(counter + 1)), 0xff)

                    signedCalc1 = uns_buf0 + bit32.lshift(uns_buf1, 8)
                    if bit32.band(signedCalc1, 0x8000) == 0x8000 then
                        signedCalc1 = bit32.band(signedCalc1, 0x7FFF)
                        signedCalc1 = signedCalc1 - 0x8000
                    end
					
                    dpp.samples_B[m] = exp2s( signedCalc1 )
                    counter = counter + 2
				end
				
                m = m + 1
                cnt = cnt - 1
			end	
		end
		
        for sample_counter=0,MAX_TERM-1,1 do		
            wps.decorr_passes[dpp_index].samples_A[sample_counter] = dpp.samples_A[sample_counter]
            wps.decorr_passes[dpp_index].samples_B[sample_counter] = dpp.samples_B[sample_counter]	
		end

        dpp_index = dpp_index - 1
	end

    return true
end


-- Read the int32 data from the specified metadata into the specified stream.
-- This data is used for integer data that has more than 24 bits of magnitude
-- or, in some cases, used to eliminate redundant bits from any audio stream.

function read_int32_info( wps, wpmd) 

    local bytecnt = wpmd.byte_length
    local byteptr = wpmd.data
    local counter = 1

    if (bytecnt ~= 4) then
        return false
	end	

    wps.int32_sent_bits = string.byte(byteptr,counter)
    counter = counter + 1
    wps.int32_zeros = string.byte(byteptr,counter)
    counter = counter + 1
    wps.int32_ones = string.byte(byteptr,counter)
    counter = counter + 1
    wps.int32_dups = string.byte(byteptr,counter)

    return true
end


-- Read multichannel information from metadata. The first byte is the total
-- number of channels and the following bytes represent the channel_mask
-- as described for Microsoft WAVEFORMATEX.

function read_channel_info(wpc, wpmd)

    local bytecnt = wpmd.byte_length
    local shift = 0
    local byteptr = wpmd.data
    local counter = 1
    local mask = 0

    if (bytecnt == 0 or bytecnt > 5) then
        return false
	end	

    wpc.config.num_channels = string.byte(byteptr,counter)
    counter = counter + 1

    while (bytecnt >= 0) do
        mask = bit32.bor(mask, bit32.lshift(bit32.band((string.byte(byteptr,counter)), 0xFF), shift))
        counter = counter + 1
        shift = shift + 8
        bytecnt = bytecnt - 1
	end	

    wpc.config.channel_mask = mask
    return true
end

-- Read configuration information from metadata.

function read_config_info(wpc, wpmd) 

    bytecnt = wpmd.byte_length
    byteptr = wpmd.data
    local counter = 1

    if (bytecnt >= 3) then
        wpc.config.flags = bit32.band(wpc.config.flags, 0xff)
        wpc.config.flags = bit32.bor(wpc.config.flags,(bit32.lshift(bit32.band(string.byte(byteptr,counter), 0xFF), 8)))
        counter = counter + 1
        wpc.config.flags = bit32.bor(wpc.config.flags,(bit32.lshift(bit32.band(string.byte(byteptr,counter), 0xFF), 16)))
        counter = counter + 1
        wpc.config.flags = bit32.bor(wpc.config.flags,(bit32.lshift(bit32.band(string.byte(byteptr,counter), 0xFF), 24)))
	end
	
    return true
end

-- Read non-standard sampling rate from metadata.

function read_sample_rate(wpc, wpmd)
    bytecnt = wpmd.byte_length
    byteptr = wpmd.data
    local counter = 1

    if (bytecnt == 3) then
        wpc.config.sample_rate = bit32.band(string.byte(byteptr,counter), 0xFF)
        counter = counter + 1
        wpc.config.sample_rate = bit32.bor(wpc.config.sample_rate, bit32.lshift(bit32.band(string.byte(byteptr,counter), 0xFF), 8))
        counter = counter + 1
		wpc.config.sample_rate = bit32.bor(wpc.config.sample_rate, bit32.lshift(bit32.band(string.byte(byteptr,counter), 0xFF), 16))
	end	
    
    return true
end

-- This monster actually unpacks the WavPack bitstream(s) into the specified
-- buffer as 32-bit integers or floats (depending on original data). Lossy
-- samples will be clipped to their original limits (i.e. 8-bit samples are
-- clipped to -128/+127) but are still returned in ints. It is up to the
-- caller to potentially reformat this for the final output including any
-- multichannel distribution, block alignment or endian compensation. The
-- function unpack_init() must have been called and the entire WavPack block
-- must still be visible (although wps.blockbuff will not be accessed again).
-- For maximum clarity, the function is broken up into segments that handle
-- various modes. This makes for a few extra infrequent flag checks, but
-- makes the code easier to follow because the nesting does not become so
-- deep. For maximum efficiency, the conversion is isolated to tight loops
-- that handle an entire buffer. The function returns the total number of
-- samples unpacked, which can be less than the number requested if an error
-- occurs or the end of the block is reached.

function unpack_samples(wpc, mybuffer, sample_count)
    wps = wpc.stream
    local flags = wps.wphdr.flags
    local i = 0
    crc = wps.crc
    mute_limit = (bit32.lshift(1, bit32.rshift(bit32.band(flags, MAG_MASK), MAG_LSB)) + 2)	
    dpp = decorr_pass:new()
    tcount = 0
    local buffer_counter = 0
	
    samples_processed = 0

    if (wps.sample_index + sample_count > wps.wphdr.block_index + wps.wphdr.block_samples) then
        sample_count = wps.wphdr.block_index + wps.wphdr.block_samples - wps.sample_index
	end	

    if (wps.mute_error > 0) then
        tempc = 0

        if (bit32.band(flags, MONO_FLAG) ~= 0) then
            tempc = sample_count
        else 
            tempc = 2 * sample_count
		end	

        while (tempc > 0) do
            mybuffer[buffer_counter] = 0
            tempc = tempc - 1
            buffer_counter = buffer_counter + 1
		end	

        wps.sample_index = wps.sample_index + sample_count

        return sample_count
	end	

    if (bit32.band(flags, HYBRID_FLAG) ~= 0) then
        mute_limit = mute_limit * 2
	end	


    -- ///////////////////// handle version 4 mono data /////////////////////////

    if (bit32.band(flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) ~= 0) then
        dpp_index = 0

        i = get_words(sample_count, flags, wps.w, wps.wvbits, mybuffer)	

        for tcount = 0, wps.num_terms-1, 1 do
            dpp = wps.decorr_passes[dpp_index]
            decorr_mono_pass(dpp, mybuffer, sample_count, buffer_counter)
            dpp_index = dpp_index + 1
		end	

        bf_abs = 0

        for q =0, (sample_count-1), 1 do
            if mybuffer[q] < 0 then
                bf_abs = -mybuffer[q]
            else
                bf_abs = mybuffer[q]
			end	

            if (bf_abs > mute_limit) then
                i = q			
                break
			end	
            
            crcstep1 = bit32.band((crc * 3), 0xffffffff)
            crc = bit32.band((crcstep1 + mybuffer[q]), 0xffffffff)	
 
		end	

    -- //////////////////// handle version 4 stereo data ////////////////////////

    else       
        samples_processed = get_words(sample_count, flags, wps.w, wps.wvbits, mybuffer)

        i = samples_processed

        if (sample_count < 16) then 
            dpp_index = 0
			
            for tcount = 0, wps.num_terms-1, 1 do
                dpp = wps.decorr_passes[dpp_index]				
                decorr_stereo_pass(dpp, mybuffer, sample_count, buffer_counter)
                wps.decorr_passes[dpp_index] = dpp
                dpp_index = dpp_index + 1
			end	
        else
            dpp_index = 0

			for tcount = 0, wps.num_terms-1, 1 do

                dpp = wps.decorr_passes[dpp_index]
                decorr_stereo_pass(dpp, mybuffer, 8, buffer_counter)				
                decorr_stereo_pass_cont(dpp, mybuffer, sample_count - 8, buffer_counter + 16)				
                wps.decorr_passes[dpp_index] = dpp

                dpp_index = dpp_index + 1
			end
		end		

        if (bit32.band(flags, JOINT_STEREO) ~= 0) then		
            bf_abs = 0
            bf1_abs = 0

            for buffer_counter = 0,(sample_count * 2)-1,2 do

				mybuffer[buffer_counter + 1] = mybuffer[buffer_counter + 1] - signed_rshift(mybuffer[buffer_counter], 1)
                mybuffer[buffer_counter] = mybuffer[buffer_counter] + mybuffer[buffer_counter + 1]

                if mybuffer[buffer_counter] < 0 then
                    bf_abs = -mybuffer[buffer_counter]
                else 
                    bf_abs = mybuffer[buffer_counter]
				end	
                
                if mybuffer[buffer_counter + 1] < 0 then
                    bf1_abs = -mybuffer[buffer_counter + 1]
                else
                    bf1_abs = mybuffer[buffer_counter + 1]
				end	

                if (bf_abs > mute_limit or bf1_abs > mute_limit) then				
                    i = buffer_counter / 2
                    break
				end	

                crcstep1 = bit32.band((crc * 3), 0xffffffff)
                crcstep2 = bit32.band((crcstep1 + mybuffer[buffer_counter]), 0xffffffff)
                crcstep3 = bit32.band((crcstep2 * 3), 0xffffffff)

                crc = bit32.band((crcstep3 + mybuffer[buffer_counter + 1] ), 0xffffffff)
			end				
        else
            bf_abs = 0
            bf1_abs = 0

            for buffer_counter = 0,(sample_count * 2)-1,2 do
                if mybuffer[buffer_counter] < 0 then
                    bf_abs = -mybuffer[buffer_counter]
                else
                    bf_abs = mybuffer[buffer_counter]
				end	
                    
                if mybuffer[buffer_counter + 1] < 0 then
                    bf1_abs = -mybuffer[buffer_counter + 1]
                else
                    bf1_abs = mybuffer[buffer_counter + 1]
				end	

                if (bf_abs > mute_limit or bf1_abs > mute_limit) then					
                    i = buffer_counter / 2
                    break
				end	

                crcstep1 = bit32.band((crc * 3), 0xffffffff)
                crcstep2 = bit32.band((crcstep1 + mybuffer[buffer_counter]), 0xffffffff)
                crcstep3 = bit32.band((crcstep2 * 3), 0xffffffff)

                crc = bit32.band((crcstep3 + mybuffer[buffer_counter + 1] ), 0xffffffff)
			end			
		end	
	end
	
    if (i ~= sample_count) then
        sc = 0
       
        if (bit32.band(flags, MONO_FLAG) ~= 0) then
            sc = sample_count
        else
            sc = 2 * sample_count
		end	
            
        buffer_counter = 0

        while (sc > 0) do		
            mybuffer[buffer_counter] = 0
            sc = sc -1
            buffer_counter = buffer_counter + 1
		end	

        wps.mute_error = 1
        i = sample_count
	end	

    mybuffer = fixup_samples(wps, mybuffer, i)

    if (bit32.band(flags, FALSE_STEREO) ~= 0) then
        dest_idx = i * 2
        src_idx = i
        c = i

        dest_idx = dest_idx - 1
        src_idx = src_idx - 1

        while (c > 0) do
            mybuffer[dest_idx] = mybuffer[src_idx]
            dest_idx = dest_idx - 1
            mybuffer[dest_idx] = mybuffer[src_idx]
            dest_idx = dest_idx - 1
            src_idx = src_idx - 1
            c = c -1
		end
	end	

    wps.sample_index = wps.sample_index + i
    wps.crc = crc

    return i
end


function signed_rshift(val, shift)
	if(val>=0) then
		return (bit32.rshift(val,shift))
	else
		local iterator = bit32.bnot(math.abs(val)) + 1
		local leftmostbit = 0x80000000	-- in 32 bits, this is the leftmost bit
		-- when right shifting a negative number, you want the leftmost bit to always be set
		-- so instead of one shift, we do a series of right shifts, each time setting the leftmost bit
		for i=1, shift,1 do
			iterator = bit32.bor(bit32.rshift(iterator,1), leftmostbit)
		end
		return (iterator - (2^32))
	end
end

function signed_xor(val1, val2)
	local neg_present = false

	if(val1<0 or val2<0) then
		neg_present = true
	end
	if(neg_present == true and val1<0 and val2<0) then
		neg_present = false
	end
	
	if(neg_present==false) then
		return(bit32.bxor(val1,val2))
	else
		local xor_result = bit32.bxor(val1,val2)
		return (xor_result - (2^32))
	end
	
end

function signed_lshift(val, shift)
	if(val<0) then
		result = -bit32.lshift(-val,shift)
	else	
		result = bit32.lshift(val,shift)
	end
	return result
end	

-- This is a help routine for apply weight. It works with negative and postive numbers

function apply_weight_helper(sample)
	local result = 0
	
	if(sample>=0) then
		result = bit32.rshift(bit32.band(sample, 0xFFFF0000), 9)
	else	
		local res1 = bit32.band(sample, 0xFFFF0000) - (2^32)
		result = signed_rshift(res1, 9)
	end
	
	return(result)
end

function decorr_stereo_pass(dpp, mybuffer, sample_count, buf_idx) 
    delta = dpp.delta
    weight_A = dpp.weight_A
    weight_B = dpp.weight_B
    sam_A = 0
    sam_B = 0
    m = 0
    k = 0
    bptr_counter = 0
	local end_index = (buf_idx + sample_count * 2)-1
	
    if(dpp.term == 17) then
        for bptr_counter = buf_idx, end_index, 2 do		
            sam_A = 2 * dpp.samples_A[0] - dpp.samples_A[1]
            dpp.samples_A[1] = dpp.samples_A[0]
            --dpp.samples_A[0] =  signed_rshift((weight_A * sam_A + 512), 10) + mybuffer[bptr_counter]
			dpp.samples_A[0] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_A), 9) + ( apply_weight_helper(sam_A) * weight_A) + 1), 1) + mybuffer[bptr_counter]

            if (sam_A ~= 0 and mybuffer[bptr_counter] ~= 0) then	
                if (signed_xor(sam_A, mybuffer[bptr_counter]) < 0) then
                    weight_A = weight_A - delta
                else
                    weight_A = weight_A + delta
				end
			end

            mybuffer[bptr_counter] = dpp.samples_A[0]
					
            sam_A = 2 * dpp.samples_B[0] - dpp.samples_B[1]
            dpp.samples_B[1] = dpp.samples_B[0]

            --dpp.samples_B[0] =  signed_rshift((weight_B *sam_A + 512), 10) + mybuffer[bptr_counter + 1]
			dpp.samples_B[0] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_B), 9) + ( apply_weight_helper(sam_A) * weight_B) + 1), 1) + mybuffer[bptr_counter + 1]

            if (sam_A ~= 0 and mybuffer[bptr_counter + 1] ~= 0) then
                if (signed_xor(sam_A, mybuffer[bptr_counter + 1]) < 0) then			
                    weight_B = weight_B - delta
                else
                    weight_B = weight_B + delta
				end
			end

            mybuffer[bptr_counter + 1] = dpp.samples_B[0]
		end
    elseif(dpp.term == 18) then 
        for bptr_counter = buf_idx, end_index, 2 do	
            sam_A = signed_rshift((3 * dpp.samples_A[0] - dpp.samples_A[1]), 1)
            dpp.samples_A[1] = dpp.samples_A[0]		
            --dpp.samples_A[0] =  signed_rshift((weight_A * sam_A + 512), 10) + mybuffer[bptr_counter]
			dpp.samples_A[0] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_A), 9) + ( apply_weight_helper(sam_A) * weight_A) + 1), 1) + mybuffer[bptr_counter]
			
            if (sam_A ~= 0 and mybuffer[bptr_counter] ~= 0) then
                if (signed_xor(sam_A, mybuffer[bptr_counter]) < 0) then
                    weight_A = weight_A - delta
                else
                    weight_A = weight_A + delta
				end
			end

            mybuffer[bptr_counter] = dpp.samples_A[0]

            sam_A = signed_rshift((3 * dpp.samples_B[0] - dpp.samples_B[1]), 1)
            dpp.samples_B[1] = dpp.samples_B[0]
            --dpp.samples_B[0] = signed_rshift((weight_B * sam_A + 512), 10) + mybuffer[bptr_counter + 1]
			dpp.samples_B[0] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_B), 9) + ( apply_weight_helper(sam_A) * weight_B) + 1), 1) + mybuffer[bptr_counter + 1]

            if (sam_A ~= 0 and mybuffer[bptr_counter + 1] ~= 0) then
                if (signed_xor(sam_A, mybuffer[bptr_counter + 1]) < 0) then
                    weight_B = weight_B - delta
                else
                    weight_B = weight_B + delta
				end
			end

            mybuffer[bptr_counter + 1] = dpp.samples_B[0]
		end
		
    elseif(dpp.term == -1) then
        for bptr_counter = buf_idx, end_index, 2 do
            --sam_A = mybuffer[bptr_counter] + signed_rshift((weight_A * dpp.samples_A[0] + 512), 10)
			sam_A = signed_rshift(( signed_rshift((bit32.band(dpp.samples_A[0], 0xffff) * weight_A), 9) + ( apply_weight_helper(dpp.samples_A[0]) * weight_A) + 1), 1) + mybuffer[bptr_counter]

            if (signed_xor(dpp.samples_A[0], mybuffer[bptr_counter]) < 0) then
                if (dpp.samples_A[0] ~= 0 and mybuffer[bptr_counter] ~= 0 ) then
                    weight_A = weight_A - delta
                    if weight_A < -1024 then
                        weight_A = -1024
					end
				end
            else
                if (dpp.samples_A[0] ~= 0 and mybuffer[bptr_counter] ~= 0 ) then
                    weight_A = weight_A + delta
                    if weight_A > 1024 then
                        weight_A = 1024
					end
				end
			end

            mybuffer[bptr_counter] = sam_A
            --dpp.samples_A[0] = mybuffer[bptr_counter + 1] +  signed_rshift((weight_B * sam_A + 512), 10)
			dpp.samples_A[0] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_B), 9) + ( apply_weight_helper(sam_A) * weight_B) + 1), 1) + mybuffer[bptr_counter + 1]

            if (signed_xor(sam_A, mybuffer[bptr_counter + 1]) < 0) then
                if (sam_A ~= 0 and mybuffer[bptr_counter + 1] ~= 0 ) then
                    weight_B = weight_B - delta
                    if weight_B < -1024 then
                        weight_B = -1024
					end
				end
            else
                if (sam_A ~= 0 and mybuffer[bptr_counter + 1] ~= 0 ) then
                    weight_B = weight_B + delta
                    if weight_B > 1024 then
                        weight_B = 1024
					end
				end
			end

            mybuffer[bptr_counter + 1] = dpp.samples_A[0]
		end
		
    elseif(dpp.term == -2) then
        sam_B = 0
        sam_A = 0

        for bptr_counter = buf_idx, end_index, 2 do
            --sam_B = mybuffer[bptr_counter + 1] + signed_rshift((weight_B * dpp.samples_B[0] + 512), 10)
			sam_B = signed_rshift(( signed_rshift((bit32.band(dpp.samples_B[0], 0xffff) * weight_B), 9) + ( apply_weight_helper(dpp.samples_B[0]) * weight_B) + 1), 1) + mybuffer[bptr_counter + 1]

            if (signed_xor(dpp.samples_B[0], mybuffer[bptr_counter + 1]) < 0) then
                if (dpp.samples_B[0] ~= 0 and mybuffer[bptr_counter + 1] ~= 0 ) then
                    weight_B = weight_B - delta
                    if weight_B < -1024 then
                        weight_B = -1024
					end
				end	
            else 
                if (dpp.samples_B[0] ~= 0 and mybuffer[bptr_counter + 1] ~= 0 ) then
                    weight_B = weight_B + delta
                    if weight_B > 1024 then
                        weight_B = 1024
					end
				end
			end

            mybuffer[bptr_counter + 1] = sam_B

            --dpp.samples_B[0] = mybuffer[bptr_counter] + signed_rshift((weight_A * sam_B + 512), 10)
			dpp.samples_B[0] = signed_rshift(( signed_rshift((bit32.band(sam_B, 0xffff) * weight_A), 9) + ( apply_weight_helper(sam_B) * weight_A) + 1), 1) + mybuffer[bptr_counter]

            if (signed_xor(sam_B, mybuffer[bptr_counter]) < 0) then
                if (sam_B ~= 0 and mybuffer[bptr_counter] ~= 0 ) then
                    weight_A = weight_A - delta
                    if weight_A < -1024 then
                        weight_A = -1024
					end
				end
            else 
                if (sam_B ~= 0 and mybuffer[bptr_counter] ~= 0 ) then
                    weight_A = weight_A + delta
                    if weight_A > 1024 then
                        weight_A = 1024
					end	
				end
			end
			
            mybuffer[bptr_counter] = dpp.samples_B[0]
		end

    elseif(dpp.term == -3) then
        sam_A = 0

        for bptr_counter = buf_idx, end_index, 2 do
            --sam_A = mybuffer[bptr_counter] + signed_rshift((weight_A * dpp.samples_A[0] + 512), 10)
			sam_A = signed_rshift(( signed_rshift((bit32.band(dpp.samples_A[0], 0xffff) * weight_A), 9) + ( apply_weight_helper(dpp.samples_A[0]) * weight_A) + 1), 1) + mybuffer[bptr_counter]

            if (signed_xor(dpp.samples_A[0], mybuffer[bptr_counter]) < 0) then
                if (dpp.samples_A[0] ~= 0 and mybuffer[bptr_counter] ~= 0 ) then
                    weight_A = weight_A - delta
                    if weight_A < -1024 then
                        weight_A = -1024
					end
				end	
            else 
                if (dpp.samples_A[0] ~= 0 and mybuffer[bptr_counter] ~= 0 ) then
                    weight_A = weight_A + delta
                    if weight_A > 1024 then
                        weight_A = 1024
					end
				end
			end

            --sam_B = mybuffer[bptr_counter + 1] + signed_rshift((weight_B * dpp.samples_B[0] + 512), 10)
			sam_B = signed_rshift(( signed_rshift((bit32.band(dpp.samples_B[0], 0xffff) * weight_B), 9) + ( apply_weight_helper(dpp.samples_B[0]) * weight_B) + 1), 1) + mybuffer[bptr_counter + 1]

            if (signed_xor(dpp.samples_B[0], mybuffer[bptr_counter + 1]) < 0) then
                if (dpp.samples_B[0] ~= 0 and mybuffer[bptr_counter + 1] ~= 0 ) then
                    weight_B = weight_B - delta
                    if weight_B < -1024 then
                        weight_B = -1024
					end
				end
            else 
                if (dpp.samples_B[0] ~= 0 and mybuffer[bptr_counter + 1] ~= 0 ) then
                    weight_B = weight_B + delta
                    if weight_B > 1024 then
                        weight_B = 1024
					end
				end
			end

			dpp.samples_B[0] = sam_A
            mybuffer[bptr_counter] = sam_A
			dpp.samples_A[0] = sam_B
            mybuffer[bptr_counter + 1] = sam_B
		end	

    else

        sam_A = 0
        m = 0
        k = bit32.band(dpp.term, (MAX_TERM - 1))

        for bptr_counter = buf_idx, end_index, 2 do
            sam_A = dpp.samples_A[m]
            --dpp.samples_A[k] = signed_rshift((weight_A * sam_A + 512), 10) + mybuffer[bptr_counter]
			dpp.samples_A[k] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_A), 9) + ( apply_weight_helper(sam_A) * weight_A) + 1), 1) + mybuffer[bptr_counter]

            if (sam_A ~= 0 and mybuffer[bptr_counter] ~= 0) then
                if (signed_xor(sam_A, mybuffer[bptr_counter]) < 0) then
                    weight_A = weight_A - delta
                else 
                    weight_A = weight_A + delta
				end
			end

            mybuffer[bptr_counter] = dpp.samples_A[k]

            sam_A = dpp.samples_B[m]
	
            --dpp.samples_B[k] = signed_rshift((weight_B * sam_A + 512), 10) + mybuffer[bptr_counter + 1]
			dpp.samples_B[k] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_B), 9) + ( apply_weight_helper(sam_A) * weight_B) + 1), 1) + mybuffer[bptr_counter + 1]
   
            if (sam_A ~= 0 and mybuffer[bptr_counter + 1] ~= 0) then
                if (signed_xor(sam_A, mybuffer[bptr_counter + 1]) < 0) then
                    weight_B = weight_B - delta
                else
                    weight_B = weight_B + delta
				end
			end

            mybuffer[bptr_counter + 1] = dpp.samples_B[k]

            m = bit32.band((m + 1), (MAX_TERM - 1))
            k = bit32.band((k + 1), (MAX_TERM - 1))
		end	

        if (m ~= 0) then
            temp_samples = {}

            for t = 0, #dpp.samples_A,1 do
                temp_samples[t] = dpp.samples_A[t]
			end
			
            for k = 0,MAX_TERM-1,1 do
                dpp.samples_A[k] = temp_samples[bit32.band(m, (MAX_TERM - 1))]
                m = m + 1
			end
			
            for tmpiter = 0,MAX_TERM-1,1 do
                temp_samples[tmpiter] = dpp.samples_B[tmpiter]
			end
			
            for k = 0,MAX_TERM-1,1 do
                dpp.samples_B[k] = temp_samples[bit32.band(m, (MAX_TERM - 1))]
                m = m + 1
			end	
		end
	end
				
    dpp.weight_A =  weight_A
    dpp.weight_B =  weight_B
end


function decorr_stereo_pass_cont(dpp, mybuffer, sample_count, buf_idx) 
    local delta = dpp.delta
    local weight_A = dpp.weight_A
    local weight_B = dpp.weight_B
    local tptr = 0
    local sam_A = 0
    local sam_B = 0
    local k = 0
    local i = 0
    local buffer_index = buf_idx
    local end_index = (buf_idx + sample_count * 2)-1

    if(dpp.term == 17) then
        for buffer_index = buf_idx, end_index, 2 do
            sam_A = 2 * mybuffer[buffer_index - 2] - mybuffer[buffer_index - 4]

            sam_B = mybuffer[buffer_index]
            --mybuffer[buffer_index] = signed_rshift((weight_A *  sam_A + 512), 10) + sam_B
			mybuffer[buffer_index] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_A), 9) + ( apply_weight_helper(sam_A) * weight_A) + 1), 1) + sam_B

            if (sam_A ~= 0 and sam_B ~= 0) then
                if signed_xor(sam_A, sam_B) < 0 then
                    weight_A = weight_A - delta 
                else
                    weight_A = weight_A + delta
				end
			end

            sam_A = 2 * mybuffer[buffer_index - 1] - mybuffer[buffer_index - 3]
            sam_B = mybuffer[buffer_index + 1]
            --mybuffer[buffer_index + 1] = signed_rshift((weight_B * sam_A + 512), 10) + sam_B
			mybuffer[buffer_index + 1] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_B), 9) + ( apply_weight_helper(sam_A) * weight_B) + 1), 1) + sam_B

            if (sam_A ~= 0 and sam_B ~= 0) then 
                if signed_xor(sam_A, sam_B) < 0 then
                    weight_B = weight_B - delta 
                else
                    weight_B = weight_B + delta
				end
			end	
            
		end
		
        buffer_index = end_index + 1
        
        dpp.samples_B[0] = mybuffer[buffer_index - 1]
        dpp.samples_A[0] = mybuffer[buffer_index - 2]
        dpp.samples_B[1] = mybuffer[buffer_index - 3]
        dpp.samples_A[1] = mybuffer[buffer_index - 4]

	elseif(dpp.term == 18) then
        for buffer_index = buf_idx, end_index, 2 do
            sam_A = signed_rshift((3 * mybuffer[buffer_index - 2] - mybuffer[buffer_index - 4]), 1)
            sam_B = mybuffer[buffer_index]
            --mybuffer[buffer_index] = signed_rshift((weight_A * sam_A + 512), 10) + sam_B
			mybuffer[buffer_index] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_A), 9) + ( apply_weight_helper(sam_A) * weight_A) + 1), 1) + sam_B

            if (sam_A ~= 0 and sam_B ~= 0) then 
                if signed_xor(sam_A, sam_B) < 0 then
                    weight_A = weight_A - delta 
                else
                    weight_A = weight_A + delta
				end
			end


            sam_A = signed_rshift((3 * mybuffer[buffer_index - 1] - mybuffer[buffer_index - 3]), 1)
            sam_B = mybuffer[buffer_index + 1]
            --mybuffer[buffer_index + 1] = signed_rshift((weight_B * sam_A + 512), 10) + sam_B
			mybuffer[buffer_index + 1] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_B), 9) + ( apply_weight_helper(sam_A) * weight_B) + 1), 1) + sam_B

            if (sam_A ~= 0 and sam_B ~= 0) then 
                if signed_xor(sam_A, sam_B) < 0 then
                    weight_B = weight_B - delta 
                else 
                    weight_B = weight_B + delta
				end
			end
		end	

        buffer_index = end_index + 1

        dpp.samples_B[0] = mybuffer[buffer_index - 1]
        dpp.samples_A[0] = mybuffer[buffer_index - 2]
        dpp.samples_B[1] = mybuffer[buffer_index - 3]
        dpp.samples_A[1] = mybuffer[buffer_index - 4]

	elseif(dpp.term == -1) then
        for buffer_index = buf_idx, end_index, 2 do
            sam_A = mybuffer[buffer_index]

            --mybuffer[buffer_index] = signed_rshift((weight_A * mybuffer[buffer_index - 1] + 512), 10) + sam_A
			mybuffer[buffer_index] = signed_rshift(( signed_rshift((bit32.band(mybuffer[buffer_index - 1], 0xffff) * weight_A), 9) + ( apply_weight_helper(mybuffer[buffer_index - 1]) * weight_A) + 1), 1) + sam_A

            if (signed_xor(mybuffer[buffer_index - 1], sam_A) < 0) then
                if (mybuffer[buffer_index - 1] ~= 0 and sam_A ~= 0 ) then
                    weight_A = weight_A - delta
                    if weight_A < -1024 then
                        weight_A = -1024
					end
				end	
            else
                if (mybuffer[buffer_index - 1] ~= 0 and sam_A ~= 0 ) then
                    weight_A = weight_A + delta
                    if (weight_A > 1024) then
                        weight_A = 1024
					end
				end
			end
			
            sam_A = mybuffer[buffer_index + 1]
			--mybuffer[buffer_index + 1] = signed_rshift((weight_B *  mybuffer[buffer_index] + 512), 10) + sam_A
			mybuffer[buffer_index + 1] = signed_rshift(( signed_rshift((bit32.band(mybuffer[buffer_index], 0xffff) * weight_B), 9) + ( apply_weight_helper(mybuffer[buffer_index]) * weight_B) + 1), 1) + sam_A

            if (signed_xor(mybuffer[buffer_index], sam_A) < 0) then
                if (mybuffer[buffer_index] ~= 0 and sam_A ~= 0 ) then
                    weight_B = weight_B - delta
                    if weight_B < -1024 then
                        weight_B = -1024
					end
				end
            else
                if (mybuffer[buffer_index] ~= 0 and sam_A ~= 0 ) then
                    weight_B = weight_B + delta
                    if weight_B > 1024 then
                        weight_B = 1024
					end
				end
			end
		end
		
        buffer_index = end_index + 1
        
        dpp.samples_A[0] = mybuffer[buffer_index - 1]

	elseif(dpp.term == -2) then
        sam_A = 0
        sam_B = 0

        for buffer_index = buf_idx, end_index, 2 do
            sam_A = mybuffer[buffer_index + 1]
            --mybuffer[buffer_index + 1] = signed_rshift((weight_B * mybuffer[buffer_index - 2] + 512), 10) + sam_A
			mybuffer[buffer_index + 1] = signed_rshift(( signed_rshift((bit32.band(mybuffer[buffer_index - 2], 0xffff) * weight_B), 9) + ( apply_weight_helper(mybuffer[buffer_index - 2]) * weight_B) + 1), 1) + sam_A

            if (signed_xor(mybuffer[buffer_index - 2], sam_A) < 0) then
                if (mybuffer[buffer_index - 2] ~= 0 and sam_A ~= 0 ) then
                    weight_B = weight_B - delta
                    if weight_B < -1024 then
                        weight_B = -1024
					end
				end
            else
                if (mybuffer[buffer_index - 2] ~= 0 and sam_A ~= 0 ) then
                    weight_B = weight_B + delta
                    if weight_B > 1024 then
                        weight_B = 1024
					end
				end
			end

            sam_A = mybuffer[buffer_index]
            --mybuffer[buffer_index] = signed_rshift((weight_A * mybuffer[buffer_index + 1] + 512), 10) + sam_A
			mybuffer[buffer_index] = signed_rshift(( signed_rshift((bit32.band(mybuffer[buffer_index + 1], 0xffff) * weight_A), 9) + ( apply_weight_helper(mybuffer[buffer_index + 1]) * weight_A) + 1), 1) + sam_A

            if (signed_xor(mybuffer[buffer_index + 1], sam_A) < 0) then
                if (mybuffer[buffer_index + 1] ~= 0 and sam_A ~= 0) then
                    weight_A = weight_A - delta
                    if weight_A < -1024 then
                        weight_A = -1024
					end
				end
            else
                if (mybuffer[buffer_index + 1] ~= 0 and sam_A ~= 0) then
                    weight_A = weight_A + delta
                    if (weight_A > 1024) then
                        weight_A = 1024
					end
				end
			end
		end

        buffer_index = end_index + 1
        
        dpp.samples_B[0] = mybuffer[buffer_index - 2]

	elseif(dpp.term == -3) then
        for buffer_index = buf_idx, end_index, 2 do
            sam_A = mybuffer[buffer_index]

            --mybuffer[buffer_index] = signed_rshift((weight_A * mybuffer[buffer_index - 1] + 512), 10) + sam_A
			mybuffer[buffer_index] = signed_rshift(( signed_rshift((bit32.band(mybuffer[buffer_index - 1], 0xffff) * weight_A), 9) + ( apply_weight_helper(mybuffer[buffer_index - 1]) * weight_A) + 1), 1) + sam_A

            if (signed_xor(mybuffer[buffer_index - 1], sam_A) < 0) then
                if (mybuffer[buffer_index - 1] ~= 0 and sam_A ~= 0 ) then
                    weight_A = weight_A - delta
                    if weight_A < -1024 then
                        weight_A = -1024
					end
				end
            else 
                if (mybuffer[buffer_index - 1] ~= 0 and sam_A ~= 0 ) then
                    weight_A = weight_A + delta
                    if weight_A > 1024 then
                        weight_A = 1024
					end
				end
			end

            sam_A = mybuffer[buffer_index + 1]
            --mybuffer[buffer_index + 1] = signed_rshift((weight_B * mybuffer[buffer_index - 2] + 512), 10) + sam_A
			mybuffer[buffer_index + 1] = signed_rshift(( signed_rshift((bit32.band(mybuffer[buffer_index - 2], 0xffff) * weight_B), 9) + ( apply_weight_helper(mybuffer[buffer_index - 2]) * weight_B) + 1), 1) + sam_A

            if (signed_xor(mybuffer[buffer_index - 2], sam_A) < 0) then
                if (mybuffer[buffer_index - 2] ~= 0 and sam_A ~= 0 ) then
                    weight_B = weight_B - delta
                    if weight_B < -1024 then
                        weight_B = -1024
					end
				end
            else 
                if (mybuffer[buffer_index - 2] ~= 0 and sam_A ~= 0 ) then
                    weight_B = weight_B + delta
                    if weight_B > 1024 then
                        weight_B = 1024
					end
				end
			end
		end	

        buffer_index = end_index + 1
        
        dpp.samples_A[0] = mybuffer[buffer_index - 1]
        dpp.samples_B[0] = mybuffer[buffer_index - 2]

    else
        tptr = buf_idx - (dpp.term * 2)

        for buffer_index = buf_idx, end_index, 2 do
            sam_A = mybuffer[buffer_index]
            
            --mybuffer[buffer_index] = signed_rshift((weight_A * mybuffer[tptr] + 512), 10) + sam_A
			mybuffer[buffer_index] = signed_rshift(( signed_rshift((bit32.band(mybuffer[tptr], 0xffff) * weight_A), 9) + ( apply_weight_helper(mybuffer[tptr]) * weight_A) + 1), 1) + sam_A

            if (mybuffer[tptr] ~= 0 and sam_A ~= 0) then 
                if signed_xor(mybuffer[tptr], sam_A) < 0 then
                    weight_A = weight_A - delta
                else 
                    weight_A = weight_A + delta
				end
			end

            sam_A = mybuffer[buffer_index + 1]
            --mybuffer[buffer_index + 1] = signed_rshift((weight_B * mybuffer[tptr + 1] + 512), 10) + sam_A
			mybuffer[buffer_index + 1] = signed_rshift(( signed_rshift((bit32.band(mybuffer[tptr + 1], 0xffff) * weight_B), 9) + ( apply_weight_helper(mybuffer[tptr + 1]) * weight_B) + 1), 1) + sam_A

            if (mybuffer[tptr + 1] ~= 0 and sam_A ~= 0) then 
                if signed_xor(mybuffer[tptr + 1], sam_A) < 0 then
                    weight_B = weight_B - delta 
                else 
                    weight_B = weight_B + delta
				end
			end


            tptr = tptr + 2
		end	

        buffer_index = end_index

        k = dpp.term - 1
        i = 8
        while i > 0 do
            i = i - 1
            dpp.samples_B[bit32.band(k, (MAX_TERM - 1))] = mybuffer[buffer_index]
            buffer_index = buffer_index - 1
            dpp.samples_A[bit32.band(k, (MAX_TERM - 1))] = mybuffer[buffer_index]
            buffer_index = buffer_index - 1
            k = k - 1
		end	
	end
			
    dpp.weight_A =  weight_A
    dpp.weight_B =  weight_B
end


function decorr_mono_pass(dpp, mybuffer, sample_count,  buf_idx) 
    local delta = dpp.delta
    local weight_A = dpp.weight_A
    local sam_A = 0
    local m = 0
    local k = 0
    local bptr_counter = 0
    local end_index = buf_idx + sample_count - 1

	if(dpp.term == 17) then
        for bptr_counter = buf_idx, end_index, 1 do
            sam_A = 2 * dpp.samples_A[0] - dpp.samples_A[1]
            dpp.samples_A[1] = dpp.samples_A[0]
            --dpp.samples_A[0] =  signed_rshift((weight_A *sam_A + 512), 10) + mybuffer[bptr_counter]
			dpp.samples_A[0] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_A), 9) + ( apply_weight_helper(sam_A) * weight_A) + 1), 1) + mybuffer[bptr_counter]

            if (sam_A ~= 0 and mybuffer[bptr_counter] ~= 0) then
                if (signed_xor(sam_A, mybuffer[bptr_counter]) < 0) then
                    weight_A = weight_A - delta
                else
                    weight_A = weight_A + delta
				end	
			end
                    
            mybuffer[bptr_counter] = dpp.samples_A[0]
		end
	elseif (dpp.term == 18) then
        for bptr_counter = buf_idx, end_index, 1 do	
            sam_A = signed_rshift((3 * dpp.samples_A[0] - dpp.samples_A[1]), 1)
            dpp.samples_A[1] = dpp.samples_A[0]
            --dpp.samples_A[0] = signed_rshift(((weight_A * sam_A + 512), 10) + mybuffer[bptr_counter]
			dpp.samples_A[0] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_A), 9) + ( apply_weight_helper(sam_A) * weight_A) + 1), 1) + mybuffer[bptr_counter]
			--dpp.samples_A[0] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_A), 9) + ( signed_rshift(bit32.band(sam_A, bit32.bnot(0xFFFF)), 9) * weight_A) + 1), 1) + mybuffer[bptr_counter]

            if (sam_A ~= 0 and mybuffer[bptr_counter] ~= 0) then
                if (signed_xor(sam_A, mybuffer[bptr_counter]) < 0) then
                    weight_A = weight_A - delta
                else
                    weight_A = weight_A + delta
				end
			end

            mybuffer[bptr_counter] = dpp.samples_A[0]		
		end
    else
        m = 0
        k = bit32.band(dpp.term, (MAX_TERM - 1))
        
        for bptr_counter = buf_idx, end_index, 1 do		
            sam_A = dpp.samples_A[m]
            --dpp.samples_A[k] = signed_rshift((weight_A * sam_A + 512), 10) + mybuffer[bptr_counter]
			dpp.samples_A[k] = signed_rshift(( signed_rshift((bit32.band(sam_A, 0xffff) * weight_A), 9) + ( apply_weight_helper(sam_A) * weight_A) + 1), 1) + mybuffer[bptr_counter]

            if (sam_A ~= 0 and mybuffer[bptr_counter] ~= 0) then
                if (signed_xor(sam_A, mybuffer[bptr_counter]) < 0) then
                    weight_A = weight_A - delta
                else
                    weight_A = weight_A + delta
				end
			end
			
            mybuffer[bptr_counter] = dpp.samples_A[k]
            m = bit32.band((m + 1), (MAX_TERM - 1))
            k = bit32.band((k + 1), (MAX_TERM - 1))			
		end	

        if (m ~= 0) then		
            temp_samples = {}

            for tmpiter = 0,MAX_TERM-1,1 do
                temp_samples[tmpiter] = dpp.samples_A[tmpiter]
			end	

            for k = 0,MAX_TERM-1, 1 do
                dpp.samples_A[k] = temp_samples[bit32.band(m, (MAX_TERM - 1))]
                m = m + 1
			end					
		end		
	end
	
    dpp.weight_A =  weight_A
end

-- This is a helper function for unpack_samples() that applies several final
-- operations. First, if the data is 32-bit float data, then that conversion
-- is done by float_values() (whether lossy or lossless) and we return.
-- Otherwise, if the extended integer data applies, then that operation is
-- executed first. If the unpacked data is lossy (and not corrected) then
-- it is clipped and shifted in a single operation. Otherwise, if it's
-- lossless then the last step is to apply the final shift (if any).

function fixup_samples( wps, mybuffer, sample_count) 
    flags = wps.wphdr.flags
    shift = bit32.rshift(bit32.band(flags, SHIFT_MASK), SHIFT_LSB)

    if (bit32.band(flags, FLOAT_DATA) ~= 0) then	
        sc = 0

        if (bit32.band(flags, MONO_FLAG) ~= 0) then
            sc = sample_count
        else
            sc = sample_count * 2
		end	

        mybuffer = float_values(wps, mybuffer, sc)
	end	

    if (bit32.band(flags, INT32_DATA) ~= 0) then

        sent_bits = wps.int32_sent_bits
        zeros = wps.int32_zeros
        ones = wps.int32_ones
        dups = wps.int32_dups
        local buffer_counter = 0
        count = 0

        if (bit32.band(flags, MONO_FLAG) ~= 0) then
            count = sample_count
        else
            count = sample_count * 2
		end	

        if (bit32.band(flags, HYBRID_FLAG) == 0 and sent_bits == 0 and (zeros + ones + dups) ~= 0) then
            while (count > 0) do
                if (zeros ~= 0) then
                    mybuffer[buffer_counter] = bit32.lshift(mybuffer[buffer_counter],zeros)

                elseif (ones ~= 0) then
                    mybuffer[buffer_counter] = bit32.lshift((mybuffer[buffer_counter] + 1), ones) - 1

                elseif (dups ~= 0) then
                    mybuffer[buffer_counter] =  bit32.lshift((mybuffer[buffer_counter] + bit32.band(mybuffer[buffer_counter], 1)), dups) - bit32.band(mybuffer[buffer_counter], 1)
				end
				
                buffer_counter = buffer_counter + 1
                count = count - 1
			end	
        else
            shift = shift + zeros + sent_bits + ones + dups
		end	
	end

    if (bit32.band(flags, HYBRID_FLAG) ~= 0) then
        min_value = 0
        max_value = 0
        min_shifted = 0
        max_shifted = 0
        local buffer_counter = 0
		
		switch_value = bit32.band(flags, BYTES_STORED)

        if(switch_value == 0) then
            min_value = -128
            min_shifted = bit32.lshift(bit32.rshift(min_value, shift), shift)
            max_value = 127
            max_shifted = bit32.lshift(bit32.rshift(max_value, shift), shift)

        elseif(switch_value == 1) then
            min_value = -32768
            min_shifted = bit32.lshift(bit32.rshift(min_value, shift), shift)
            max_value = 32767
            max_shifted = bit32.lshift(bit32.rshift(max_value, shift), shift)

        elseif(switch_value == 2) then
            min_value = -8388608
            min_shifted = bit32.lshift(bit32.rshift(min_value, shift), shift)
            max_value = 8388607
            max_shifted = bit32.lshift(bit32.rshift(max_value, shift), shift)
            
        else
			-- when switch_value is 3 or other value
            min_value = 0x80000000
            min_shifted = bit32.lshift(bit32.rshift(min_value, shift), shift)
            max_value = 0x7FFFFFFF
            max_shifted = bit32.lshift(bit32.rshift(max_value, shift), shift)
		end	

        if (bit32.band(flags, MONO_FLAG) == 0) then
            sample_count = sample_count * 2
		end	

        while (sample_count > 0) do
            if (mybuffer[buffer_counter] < min_value) then
                mybuffer[buffer_counter] = min_shifted

            elseif (mybuffer[buffer_counter] > max_value) then
                mybuffer[buffer_counter] = max_shifted

            else
                mybuffer[buffer_counter] = bit32.lshift(mybuffer[buffer_counter],shift)
			end	

            buffer_counter = buffer_counter + 1
            sample_count = sample_count - 1
		end	

    elseif (shift ~= 0) then
	
		local buffer_counter = 0

        if (bit32.band(flags, MONO_FLAG) == 0) then
            sample_count = sample_count * 2
		end	

        while (sample_count > 0) do
            mybuffer[buffer_counter] = signed_lshift(mybuffer[buffer_counter], shift)		
            buffer_counter = buffer_counter + 1
            sample_count = sample_count - 1
		end	

	end
	
    return mybuffer
end

-- This function checks the crc value(s) for an unpacked block, returning the
-- number of actual crc errors detected for the block. The block must be
-- completely unpacked before this test is valid. For losslessly unpacked
-- blocks of float or extended integer data the extended crc is also checked.
-- Note that WavPack's crc is not a CCITT approved polynomial algorithm, but
-- is a much simpler method that is virtually as robust for real world data.

function check_crc_error(wpc)
    wps = wpc.stream
    result = 0

    if (wps.crc ~= wps.wphdr.crc) then
        result = result + 1
	end	

    return result
end

-- Read the median log2 values from the specifed metadata structure, convert
-- them back to 32-bit unsigned values and store them. If length is not
-- exactly correct then we flag and return an error.

function read_entropy_vars(wps, wpmd)
    byteptr = wpmd.data -- byteptr needs to be unsigned chars, so convert to int array
    b_array = {}
    local i = 0
    w = words_data:new()
	
	-- first lets clear down the values
	w.c[0].median[0] = 0
	w.c[0].median[1] = 0
	w.c[0].median[2] = 0	
	w.c[1].median[0] = 0
	w.c[1].median[1] = 0
	w.c[1].median[2] = 0

    for i = 0,5,1 do
        b_array[i] = bit32.band(string.byte(byteptr,(i+1)), 0xff)
	end
	
    w.holding_one = 0
    w.holding_zero = 0

    if (wpmd.byte_length ~= 12) then
		if (bit32.band(wps.wphdr.flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then
            return false
		end
	end
	
    w.c[0].median[0] = exp2s(b_array[0] + bit32.lshift(b_array[1], 8))
    w.c[0].median[1] = exp2s(b_array[2] + bit32.lshift(b_array[3], 8))
    w.c[0].median[2] = exp2s(b_array[4] + bit32.lshift(b_array[5], 8))

	if (bit32.band(wps.wphdr.flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then
        for i = 6,11,1 do
            b_array[i] = bit32.band(string.byte(byteptr,(i+1)), 0xff)
		end	

        w.c[1].median[0] = exp2s(b_array[6] + bit32.lshift(b_array[7], 8))
        w.c[1].median[1] = exp2s(b_array[8] + bit32.lshift(b_array[9], 8))
        w.c[1].median[2] = exp2s(b_array[10] + bit32.lshift(b_array[11], 8))
	end
	
    wps.w = w

    return true
end

-- Read the hybrid related values from the specifed metadata structure, convert
-- them back to their internal formats and store them. The extended profile
-- stuff is not implemented yet, so return an error if we get more data than
-- we know what to do with.

function read_hybrid_profile(wps, wpmd)
    local byteptr = wpmd.data
    local bytecnt = wpmd.byte_length
    local buffer_counter = 1	-- arrays start at 1
    local uns_buf = 0
    local uns_buf_plusone = 0

    if (bit32.band(wps.wphdr.flags, HYBRID_BITRATE) ~= 0) then
        uns_buf = bit32.band(string.byte(byteptr,buffer_counter), 0xff)
        uns_buf_plusone =  bit32.band(string.byte(byteptr,(buffer_counter + 1)), 0xff)

        wps.w.c[0].slow_level = exp2s(uns_buf + bit32.lshift(uns_buf_plusone, 8))
        buffer_counter = buffer_counter + 2

        if (bit32.band(wps.wphdr.flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then
            uns_buf = bit32.band(string.byte(byteptr,buffer_counter), 0xff)
            uns_buf_plusone = bit32.band(string.byte(byteptr,(buffer_counter + 1)), 0xff)
            wps.w.c[1].slow_level = exp2s(uns_buf + bit32.lshift(uns_buf_plusone, 8))
            buffer_counter = buffer_counter + 2
		end	
	end

    uns_buf = bit32.band(string.byte(byteptr,buffer_counter), 0xff)
    uns_buf_plusone = bit32.band(string.byte(byteptr,(buffer_counter + 1)), 0xff)

    wps.w.bitrate_acc[0] = bit32.lshift((uns_buf + bit32.lshift(uns_buf_plusone, 8)), 16)
    buffer_counter = buffer_counter + 2

	if (bit32.band(wps.wphdr.flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then
        uns_buf = bit32.band(string.byte(byteptr,buffer_counter), 0xff)
        uns_buf_plusone = bit32.band(string.byte(byteptr,(buffer_counter + 1)), 0xff)

        wps.w.bitrate_acc[1] = bit32.lshift((uns_buf + bit32.lshift(uns_buf_plusone, 8)), 16)
        buffer_counter = buffer_counter + 2
	end	

    if (buffer_counter < bytecnt) then
        uns_buf = bit32.band(string.byte(byteptr,buffer_counter), 0xff)
        uns_buf_plusone = bit32.band(string.byte(byteptr,(buffer_counter + 1)), 0xff)

        wps.w.bitrate_delta[0] = exp2s((uns_buf + bit32.lshift(uns_buf_plusone, 8)))
        buffer_counter = buffer_counter + 2

		if (bit32.band(wps.wphdr.flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then
            uns_buf = bit32.band(string.byte(byteptr,buffer_counter), 0xff)
            uns_buf_plusone = bit32.band(string.byte(byteptr,(buffer_counter + 1)), 0xff)
            wps.w.bitrate_delta[1] = exp2s((uns_buf + bit32.lshift(uns_buf_plusone, 8)))
            buffer_counter = buffer_counter + 2
		end	

        if (buffer_counter < bytecnt) then
            return false
		end	

    else
		wps.w.bitrate_delta[1] = 0
        wps.w.bitrate_delta[0] = 0
	end	

    return true
end

-- This function is called during both encoding and decoding of hybrid data to
-- update the "error_limit" variable which determines the maximum sample error
-- allowed in the main bitstream. In the HYBRID_BITRATE mode (which is the only
-- currently implemented) this is calculated from the slow_level values and the
-- bitrate accumulators. Note that the bitrate accumulators can be changing.

function update_error_limit(w, flags)

	local slow_log_0 = 0
	local slow_log_1 = 0
    w.bitrate_acc[0] = w.bitrate_acc[0] + w.bitrate_delta[0] 
    local bitrate_0 = bit32.rshift(w.bitrate_acc[0], 16)
	
	local bitrate_1 = 0
	local balance = 0

	if (bit32.band(flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) ~= 0) then
        if (bit32.band(flags, HYBRID_BITRATE) ~= 0) then
            slow_log_0 = bit32.rshift((w.c[0].slow_level + SLO), SLS)

            if (slow_log_0 - bitrate_0 > -0x100) then
                w.c[0].error_limit = exp2s(slow_log_0 - bitrate_0 + 0x100)				
            else 
                w.c[0].error_limit = 0					
			end	
        else
            w.c[0].error_limit = exp2s(bitrate_0)			
		end	
    else
        w.bitrate_acc[1] = w.bitrate_acc[1] + w.bitrate_delta[1]
        bitrate_1 = bit32.rshift(w.bitrate_acc[1], 16)

        if (bit32.band(flags, HYBRID_BITRATE) ~= 0) then
            slow_log_0 = bit32.rshift((w.c[0].slow_level + SLO), SLS)
            slow_log_1 = bit32.rshift((w.c[1].slow_level + SLO), SLS)

            if (bit32.band(flags, HYBRID_BALANCE) ~= 0) then
                balance = signed_rshift((slow_log_1 - slow_log_0 + bitrate_1 + 1), 1)

                if (balance > bitrate_0) then
                    bitrate_1 = bitrate_0 * 2
                    bitrate_0 = 0
                elseif (-balance > bitrate_0) then
                    bitrate_0 = bitrate_0 * 2
                    bitrate_1 = 0
                else
                    bitrate_1 = bitrate_0 + balance
                    bitrate_0 = bitrate_0 - balance
				end	
			end

            if (slow_log_0 - bitrate_0 > -0x100) then
                w.c[0].error_limit = exp2s(slow_log_0 - bitrate_0 + 0x100)					
            else
                w.c[0].error_limit = 0					
			end	

            if (slow_log_1 - bitrate_1 > -0x100) then
                w.c[1].error_limit = exp2s(slow_log_1 - bitrate_1 + 0x100)
            else 
                w.c[1].error_limit = 0
			end	
            
        else
            w.c[0].error_limit = exp2s(bitrate_0)				
            w.c[1].error_limit = exp2s(bitrate_1)
		end	
	end

    return w
end

-- Read the next word from the bitstream "wvbits" and return the value. This
-- function can be used for hybrid or lossless streams, but since an
-- optimized version is available for lossless this function would normally
-- be used for hybrid only. If a hybrid lossless stream is being read then
-- the "correction" offset is written at the specified pointer. A return value
-- of WORD_EOF indicates that the end of the bitstream was reached (all 1s) or
-- some other error occurred.

function get_words(nsamples, flags, w, bs, buffer)
    c = w.c
    csamples = 0
    local buffer_counter = 0
    local entidx = 1
	local next8 = 0
	local uns_buf = 0
	local ones_count = 0
	local low = 0
	local mid = 0
	local high = 0
	local mask = 0
	local cbits = 0

	if (bit32.band(flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then  -- if not mono
        nsamples = nsamples * 2
    else
        -- it is mono
        entidx = 0
	end	

    for gw_counter = 0, nsamples-1,1 do

        ones_count = 0
        low = 0
        mid = 0
        high = 0

        if (bit32.band(flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) == 0) then -- if not mono
            entidx = 1 - entidx
		end	

        if (bit32.band(w.c[0].median[0], bit32.bnot(1)) == 0 and w.holding_zero == 0 and w.holding_one == 0
            and bit32.band(w.c[1].median[0], bit32.bnot(1)) == 0) then

            mask = 0
            cbits = 0

            if (w.zeros_acc > 0) then
                w.zeros_acc = w.zeros_acc - 1

                if (w.zeros_acc > 0) then				
                    c[entidx].slow_level = c[entidx].slow_level - bit32.rshift((c[entidx].slow_level + SLO), SLS)
                    buffer[buffer_counter] = 0
                    buffer_counter = buffer_counter + 1
                    goto continue1
				end
            else 
                -- section called by mono code
                cbits = 0
                bs = getbit(bs)

                while (cbits < 33 and bs.bitval > 0) do
                    cbits = cbits + 1
                    bs = getbit(bs)
				end	

                if (cbits == 33) then
                    break
				end	

                if (cbits < 2) then
                    w.zeros_acc = cbits
                else

                    cbits = cbits - 1
                    
                    mask = 1
                    w.zeros_acc = 0
                    
                    while cbits > 0 do
                        bs = getbit(bs)

                        if (bs.bitval > 0) then
                            w.zeros_acc = bit32.bor(w.zeros_acc, mask)
						end
						
                        mask = bit32.lshift(mask,1)
                        cbits = cbits - 1
					end
                    w.zeros_acc = bit32.bor(w.zeros_acc, mask)
				end	

                if (w.zeros_acc > 0) then			
                    c[entidx].slow_level = c[entidx].slow_level - bit32.rshift((c[entidx].slow_level + SLO), SLS)
				
                    w.c[0].median[0] = 0
                    w.c[0].median[1] = 0
                    w.c[0].median[2] = 0
                    w.c[1].median[0] = 0
                    w.c[1].median[1] = 0
                    w.c[1].median[2] = 0

                    buffer[buffer_counter] = 0
                    buffer_counter = buffer_counter + 1
				
                    goto continue1
				end	
			end
		end
		
        if (w.holding_zero > 0) then
            ones_count = 0
			w.holding_zero = 0
        else
            next8 = 0
            uns_buf = 0

            if (bs.bc < 8) then
                bs.ptr = bs.ptr + 1
                bs.buf_index = bs.buf_index + 1

                if (bs.ptr == bs.bs_end) then			
                    bs = bs_read(bs)
				end	

                uns_buf = bit32.band(bs.buf[bs.buf_index], 0xff)

                bs.sr = bit32.bor(bs.sr, bit32.lshift(uns_buf, bs.bc)) -- values in buffer must be unsigned

                next8 =  bit32.band(bs.sr, 0xff)

                bs.bc = bs.bc + 8
            else				
                next8 =  bit32.band(bs.sr, 0xff)					
			end	

            if (next8 == 0xff) then							
                bs.bc = bs.bc - 8
                bs.sr = bit32.rshift(bs.sr,8)

                ones_count = 8
                bs = getbit(bs)

                while (ones_count < (LIMIT_ONES + 1) and bs.bitval > 0) do
                    ones_count = ones_count + 1
                    bs = getbit(bs)
				end	
                
                if (ones_count == (LIMIT_ONES + 1)) then			
                    break
				end	

                if (ones_count == LIMIT_ONES) then
                    mask = 0

                    cbits = 0
                    bs = getbit(bs)

                    while (cbits < 33 and bs.bitval > 0) do
                        cbits = cbits + 1
                        bs = getbit(bs)
					end	
                    
                    if (cbits == 33) then
                        break
					end	

                    if (cbits < 2) then
                        ones_count = cbits
                    else
                        mask = 1
                        ones_count = 0
                        
                        -- We decrement cbits before entering while condition. This is to reflect the preincrement that is used
                        -- in the Java version of the code

                        cbits = cbits - 1
                        
                        while cbits > 0 do
                            bs = getbit(bs)

                            if (bs.bitval > 0) then							
                                ones_count = bit32.bor(ones_count,mask)
							end	

                            mask = bit32.lshift(mask,1)
                            cbits = cbits - 1
						end	
                        
                        ones_count = bit32.bor(ones_count,mask)
					end
					
                    ones_count = ones_count + LIMIT_ONES
				end
            else			
                ones_count = ones_count_table[next8+1]
                bs.bc = bs.bc - (ones_count + 1)
                bs.sr = bit32.rshift(bs.sr, (ones_count + 1)) -- needs to be unsigned					
			end	

            if (w.holding_one > 0) then
                w.holding_one = bit32.band(ones_count, 1)
                ones_count = bit32.rshift(ones_count, 1) + 1
            else
                w.holding_one = bit32.band(ones_count, 1)
                ones_count = bit32.rshift(ones_count,1)
			end	

            w.holding_zero =  bit32.band(bit32.bnot(w.holding_one), 1)
		end
		
        if (bit32.band(flags, HYBRID_FLAG) ~= 0 and (bit32.band(flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) ~= 0 or entidx == 0)) then		
            w = update_error_limit(w, flags)
		end

        if (ones_count == 0) then
            low = 0
            high = ( bit32.rshift(c[entidx].median[0], 4) + 1) - 1
            c[entidx].median[0] = c[entidx].median[0] - (math.floor((c[entidx].median[0] + (DIV0 - 2)) / DIV0) * 2)
        else
            low = (bit32.rshift(c[entidx].median[0], 4) + 1)

            c[entidx].median[0] = c[entidx].median[0] + math.floor((c[entidx].median[0] + DIV0) / DIV0) * 5

            if (ones_count == 1) then
                high = low + ( bit32.rshift(c[entidx].median[1], 4) + 1) - 1
                c[entidx].median[1] = c[entidx].median[1] - math.floor((c[entidx].median[1] + (DIV1 - 2)) / DIV1) * 2
            else
                low = low + ( bit32.rshift(c[entidx].median[1], 4) + 1)
                c[entidx].median[1] = c[entidx].median[1] + math.floor((c[entidx].median[1] + DIV1) / DIV1) * 5

                if (ones_count == 2) then
                    high = low + (bit32.rshift(c[entidx].median[2], 4) + 1) - 1
                    c[entidx].median[2] = c[entidx].median[2] - math.floor((c[entidx].median[2] + (DIV2 - 2)) / DIV2) * 2
                else 
                    low = low + (ones_count - 2) * ( bit32.rshift(c[entidx].median[2], 4) + 1)
                    high = low + ( bit32.rshift(c[entidx].median[2], 4) + 1) - 1
                    c[entidx].median[2] = c[entidx].median[2] + math.floor((c[entidx].median[2] + DIV2) / DIV2) * 5
				end
			end
		end

        mid = bit32.rshift((high + low + 1), 1)

        if (c[entidx].error_limit == 0) then
            mid = read_code(bs, high - low)

            mid = mid + low		
        else
            while (high - low > c[entidx].error_limit) do

                bs = getbit(bs)

                if (bs.bitval > 0) then
                    low = mid
                    mid = bit32.rshift((high + low + 1), 1)
                else
                    high = mid -1
                    mid = bit32.rshift((high + low + 1), 1)
				end
			end
		end

        bs = getbit(bs)

        if (bs.bitval ~= 0) then		
            buffer[buffer_counter] = (-1-mid) -- this was a complement
        else	
            buffer[buffer_counter] = mid
		end	

        buffer_counter = buffer_counter + 1

        if (bit32.band(flags, HYBRID_BITRATE) ~= 0) then
            c[entidx].slow_level = c[entidx].slow_level - bit32.rshift((c[entidx].slow_level + SLO), SLS) + mylog2(mid)
		end	

	::continue1::
		csamples = csamples + 1
	end
    w.c = c

    if (bit32.band(flags, bit32.bor(MONO_FLAG, FALSE_STEREO)) ~= 0) then
        return csamples
    else
        return (csamples / 2)
	end
end

function count_bits(av)
    if (av < bit32.lshift(1, 8)) then
        return nbits_table[av+1]
    else
        if (av < bit32.lshift(1, 16)) then
            return nbits_table[ bit32.rshift(av, 8) + 1] + 8
        else
            if (av < bit32.lshift(1, 24)) then
                return nbits_table[ bit32.rshift(av, 16) + 1] + 16
            else
                return nbits_table[ bit32.rshift(av, 24) + 1] + 24
			end	
		end		
	end			
end

-- Read a single unsigned value from the specified bitstream with a value
-- from 0 to maxcode. If there are exactly a power of two number of possible
-- codes then this will read a fixed number of bits; otherwise it reads the
-- minimum number of bits and then determines whether another bit is needed
-- to define the code.

function read_code( bs, maxcode)
    bitcount = count_bits(maxcode)
    extras = bit32.lshift(1, bitcount) - maxcode - 1
    code = 0

    if (bitcount == 0) then
        return (0)
	end	

    code = getbits(bitcount - 1, bs)
	   
    code = bit32.band(code,bit32.lshift(1, (bitcount - 1)) - 1)

    if (code >= extras) then 	
        code = (code + code) - extras

        bs = getbit(bs)

        if (bs.bitval > 0) then
            code = code + 1
		end	
	end

    return (code)
end

-- The concept of a base 2 logarithm is used in many parts of WavPack. It is
-- a way of sufficiently accurately representing 32-bit signed and unsigned
-- values storing only 16 bits (actually fewer). It is also used in the hybrid
-- mode for quickly comparing the relative magnitude of large values (i.e.
-- division) and providing smooth exponentials using only addition.

-- These are not strict logarithms in that they become linear around zero and
-- can therefore represent both zero and negative values. They have 8 bits
-- of precision and in "roundtrip" conversions the total error never exceeds 1
-- part in 225 except for the cases of +/-115 and +/-195 (which error by 1).


-- This function returns the log2 for the specified 32-bit unsigned value.
-- The maximum value allowed is about 0xff800000 and returns 8447.

function mylog2(avalue)
    dbits = 0

	avalue = avalue + (bit32.rshift(avalue,9))
	
    if (avalue  < bit32.lshift(1, 8)) then
        dbits = nbits_table[avalue+1]		-- add 1 as array starts at 1 usually in Lua
        return bit32.lshift(dbits, 8) + log2_table[bit32.band(bit32.lshift(avalue, (9 - dbits)), 0xff) + 1]
    else
        if (avalue < bit32.lshift(1, 16)) then
            dbits = nbits_table[bit32.rshift(avalue, 8) + 1] + 8

        elseif (avalue < bit32.lshift(1, 24)) then
            dbits = nbits_table[bit32.rshift(avalue, 16) + 1] + 16

        else
            dbits = nbits_table[bit32.rshift(avalue, 24) + 1] + 24
		end
			
        return bit32.lshift(dbits, 8) + log2_table[bit32.band(bit32.rshift(avalue, (dbits - 9)), 0xff ) + 1]
	end	
end

-- This function returns the log2 for the specified 32-bit signed value.
-- All input values are valid and the return values are in the range of
-- +/- 8192.

function log2s(value)
    if (value < 0) then
        return -mylog2(-value)
    else
        return mylog2(value)
	end	
end

-- This function returns the original integer represented by the supplied
-- logarithm (at least within the provided accuracy). The log is signed,
-- but since a full 32-bit value is returned this can be used for unsigned
-- conversions as well (i.e. the input range is -8192 to +8447).

function exp2s(log)
    value = 0

    if (log < 0) then
        return -exp2s(-log)
	end	
    
    value = bit32.bor(exp2_table[bit32.band(log, 0xff)+1], 0x100)

    log = bit32.rshift(log, 8)
    if ( log <= 9) then
        return bit32.band(bit32.rshift(value, (9 - log)), 0xffffffff)
    else
        return bit32.lshift(value, (log - 9))
	end	
end

-- These two functions convert internal weights (which are normally +/-1024)
-- to and from an 8-bit signed character version for storage in metadata. The
-- weights are clipped here in the case that they are outside that range.

function restore_weight(weight)
    result = 0

	if(weight<0) then
		result = -bit32.lshift(-weight,3)
	else	
		result = bit32.lshift(weight,3)
	end	
   
    if ( result > 0) then
        result = result + bit32.rshift((result + 64), 7)
	end
	
    return result
end
