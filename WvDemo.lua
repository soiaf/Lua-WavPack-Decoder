--[[
** WvDemo.lua
**
** Sample program for use with WavPack.lua
**
** Copyright (c) 2013 Peter McQuillan
**
** All Rights Reserved.
**                       
** Distributed under the BSD Software License (see license.txt)  
**
--]]

require("WavPack")


RiffChunkHeader = {
	ckID = {},
	ckSize = 0,
	formType = {}
}	
function RiffChunkHeader:new()
	o = {}
	setmetatable(o,self)
	self.__index = self
	return o
end

FmtChunkHeader = {
	ckID = {},
	ckSize = 0
}
function FmtChunkHeader:new()
	o = {}
	setmetatable(o,self)
	self.__index = self
	return o
end

DtChunkHeader = {
	ckID = {},
	ckSize = 0
}
function DtChunkHeader:new()
	o = {}
	setmetatable(o,self)
	self.__index = self
	return o
end

WaveHeader = {
	FormatTa = 0,
	NumChannels = 0,
	SampleRate = 0,
	BytesPerSecond = 0,
	BlockAlign = 0,
	BitsPerSample = 0
}
function WaveHeader:new()
	o = {}
	setmetatable(o,self)
	self.__index = self
	return o
end

-- Reformat samples from longs in processor's native endian mode to
-- little-endian data with (possibly) less than 4 bytes / sample.

function format_samples( bps, src,  samcnt)
	local temp = 0
	local counter = 1	-- so our array starts at 1 (Lua preference)
	local counter2 = 0
	local dst = {}

	if bps == 1 then
		while (samcnt > 0) do
			dst[counter] = bit32.band(0x00FF, (src[counter2] + 128))
			counter = counter + 1
			counter2 = counter2 + 1
			samcnt = samcnt - 1
		end	
			
	elseif bps == 2 then
		while (samcnt > 0) do
			temp = src[counter2]
			dst[counter] = bit32.band(temp , 0xFF)
			counter = counter + 1
			dst[counter] = bit32.rshift(bit32.band(temp, 0xff00), 8)
			counter = counter + 1
			counter2 = counter2 + 1
			samcnt = samcnt - 1
		end    
	elseif bps == 3 then
		while (samcnt > 0) do
			temp = src[counter2]
			dst[counter] = bit32.band(temp, 0xff)
			counter = counter + 1
			dst[counter] = bit32.rshift(bit32.band(temp, 0xff00), 8)
			counter = counter + 1
			dst[counter] = bit32.rshift(bit32.band(temp, 0xff0000), 16)
			counter = counter + 1
			counter2 = counter2 + 1
			samcnt = samcnt - 1
		end
	elseif bps == 4 then
		while (samcnt > 0) do
			temp = src[counter2]
			dst[counter] = bit32.band(temp, 0xff)
			counter = counter + 1
			dst[counter] = bit32.rshift(bit32.band(temp, 0xff00), 8)
			counter = counter + 1
			dst[counter] = bit32.rshift(bit32.band(temp, 0xff0000), 16)
			counter = counter + 1
			dst[counter] = bit32.rshift(bit32.band(temp, 0xff000000), 24)
			counter = counter + 1
			counter2 = counter2 + 1
			samcnt = samcnt - 1
		end
	end

	return dst
end


-- Start of main routine

local temp_buffer = {}
local pcm_buffer =  {}

FormatChunkHeader = FmtChunkHeader:new()
DataChunkHeader = DtChunkHeader:new()
myRiffChunkHeader = RiffChunkHeader:new()
WaveHeader = WaveHeader:new()
myRiffChunkHeaderAsByteArray = {}
myFormatChunkHeaderAsByteArray = {}
myWaveHeaderAsByteArray = {}
myDataChunkHeaderAsByteArray = {}


local total_unpacked_samples = 0
local total_samples = 0
local num_channels = 0
local bps = 0

if arg[1] then
	inputWVFile = arg[1]
else
	inputWVFile = "input.wv"
end

print("Input file: ", inputWVFile)

fistream = assert(io.open(inputWVFile, "rb"))

if(nil == fistream) then
	print("Sorry, error opening file")
	os.exit()
end

wpc = WavpackOpenFileInput(fistream)

if (wpc.error) then
	print ("Sorry an error has occured")
	print (wpc.error_message)
	os.exit()
end	


num_channels = WavpackGetReducedChannels(wpc)

print ("The WavPack file has " ,num_channels, " channels")

total_samples = WavpackGetNumSamples(wpc)

print ("The WavPack file has " , total_samples , " samples")

bps = WavpackGetBytesPerSample(wpc)

print ("The WavPack file has " , bps , " bytes per sample")

myRiffChunkHeader.ckID[0] = 82;    -- R
myRiffChunkHeader.ckID[1] = 73;    -- I
myRiffChunkHeader.ckID[2] = 70;    -- F
myRiffChunkHeader.ckID[3] = 70;    -- F


myRiffChunkHeader.ckSize = total_samples * num_channels * bps + 8 * 2 + 16 + 4
myRiffChunkHeader.formType[0] = 87;    -- W
myRiffChunkHeader.formType[1] = 65;    -- A
myRiffChunkHeader.formType[2] = 86;    -- V
myRiffChunkHeader.formType[3] = 69;    -- E

FormatChunkHeader.ckID[0] = 102;    -- f
FormatChunkHeader.ckID[1] = 109;    -- m
FormatChunkHeader.ckID[2] = 116;    -- t
FormatChunkHeader.ckID[3] = 32;     -- ' ' (space)

FormatChunkHeader.ckSize = 16;

WaveHeader.FormatTag = 1;
WaveHeader.NumChannels = num_channels;
WaveHeader.SampleRate = WavpackGetSampleRate(wpc);
WaveHeader.BlockAlign = num_channels * bps;
WaveHeader.BytesPerSecond = WaveHeader.SampleRate * WaveHeader.BlockAlign;
WaveHeader.BitsPerSample = WavpackGetBitsPerSample(wpc);

DataChunkHeader.ckID[0] = 100;  -- d
DataChunkHeader.ckID[1] = 97;   -- a
DataChunkHeader.ckID[2] = 116;  -- t
DataChunkHeader.ckID[3] = 97;   -- a
DataChunkHeader.ckSize = total_samples * num_channels * bps;

myRiffChunkHeaderAsByteArray[0] = myRiffChunkHeader.ckID[0];
myRiffChunkHeaderAsByteArray[1] = myRiffChunkHeader.ckID[1];
myRiffChunkHeaderAsByteArray[2] = myRiffChunkHeader.ckID[2];
myRiffChunkHeaderAsByteArray[3] = myRiffChunkHeader.ckID[3];

-- swap endians here

myRiffChunkHeaderAsByteArray[7] = bit32.band(bit32.rshift(myRiffChunkHeader.ckSize, 24) , 0xFF)
myRiffChunkHeaderAsByteArray[6] = bit32.band(bit32.rshift(myRiffChunkHeader.ckSize, 16) , 0xFF)
myRiffChunkHeaderAsByteArray[5] = bit32.band(bit32.rshift(myRiffChunkHeader.ckSize, 8) , 0xFF)
myRiffChunkHeaderAsByteArray[4] = bit32.band(myRiffChunkHeader.ckSize , 0xFF)

myRiffChunkHeaderAsByteArray[8] = (myRiffChunkHeader.formType[0])
myRiffChunkHeaderAsByteArray[9] = (myRiffChunkHeader.formType[1])
myRiffChunkHeaderAsByteArray[10] = (myRiffChunkHeader.formType[2])
myRiffChunkHeaderAsByteArray[11] = (myRiffChunkHeader.formType[3])

myFormatChunkHeaderAsByteArray[0] = FormatChunkHeader.ckID[0]
myFormatChunkHeaderAsByteArray[1] = FormatChunkHeader.ckID[1]
myFormatChunkHeaderAsByteArray[2] = FormatChunkHeader.ckID[2]
myFormatChunkHeaderAsByteArray[3] = FormatChunkHeader.ckID[3]

-- swap endians here
myFormatChunkHeaderAsByteArray[7] = bit32.band(bit32.rshift(FormatChunkHeader.ckSize, 24) , 0xFF)
myFormatChunkHeaderAsByteArray[6] = bit32.band(bit32.rshift(FormatChunkHeader.ckSize, 16) , 0xFF)
myFormatChunkHeaderAsByteArray[5] = bit32.band(bit32.rshift(FormatChunkHeader.ckSize, 8) , 0xFF)
myFormatChunkHeaderAsByteArray[4] = bit32.band(FormatChunkHeader.ckSize , 0xFF)

-- swap endians
myWaveHeaderAsByteArray[1] = bit32.band(bit32.rshift(WaveHeader.FormatTag, 8) , 0xFF)
myWaveHeaderAsByteArray[0] = bit32.band(WaveHeader.FormatTag , 0xFF)

-- swap endians
myWaveHeaderAsByteArray[3] = bit32.band(bit32.rshift(WaveHeader.NumChannels, 8) , 0xFF)
myWaveHeaderAsByteArray[2] = bit32.band(WaveHeader.NumChannels , 0xFF)


-- swap endians
myWaveHeaderAsByteArray[7] = bit32.band(bit32.rshift(WaveHeader.SampleRate, 24) , 0xFF)
myWaveHeaderAsByteArray[6] = bit32.band(bit32.rshift(WaveHeader.SampleRate, 16) , 0xFF)
myWaveHeaderAsByteArray[5] = bit32.band(bit32.rshift(WaveHeader.SampleRate, 8) , 0xFF)
myWaveHeaderAsByteArray[4] = bit32.band(WaveHeader.SampleRate , 0xFF)

-- swap endians

myWaveHeaderAsByteArray[11] = bit32.band(bit32.rshift(WaveHeader.BytesPerSecond, 24) , 0xFF)
myWaveHeaderAsByteArray[10] = bit32.band(bit32.rshift(WaveHeader.BytesPerSecond, 16) , 0xFF)
myWaveHeaderAsByteArray[9] = bit32.band(bit32.rshift(WaveHeader.BytesPerSecond, 8) , 0xFF)
myWaveHeaderAsByteArray[8] = bit32.band(WaveHeader.BytesPerSecond , 0xFF)

-- swap endians
myWaveHeaderAsByteArray[13] = bit32.band(bit32.rshift(WaveHeader.BlockAlign, 8) , 0xFF)
myWaveHeaderAsByteArray[12] = bit32.band(WaveHeader.BlockAlign , 0xFF)

-- swap endians
myWaveHeaderAsByteArray[15] = bit32.band(bit32.rshift(WaveHeader.BitsPerSample, 8) , 0xFF)
myWaveHeaderAsByteArray[14] = bit32.band(WaveHeader.BitsPerSample , 0xFF)

myDataChunkHeaderAsByteArray[0] = DataChunkHeader.ckID[0];
myDataChunkHeaderAsByteArray[1] = DataChunkHeader.ckID[1];
myDataChunkHeaderAsByteArray[2] = DataChunkHeader.ckID[2];
myDataChunkHeaderAsByteArray[3] = DataChunkHeader.ckID[3];

-- swap endians

myDataChunkHeaderAsByteArray[7] = bit32.band(bit32.rshift(DataChunkHeader.ckSize, 24) , 0xFF)
myDataChunkHeaderAsByteArray[6] = bit32.band(bit32.rshift(DataChunkHeader.ckSize, 16) , 0xFF)
myDataChunkHeaderAsByteArray[5] = bit32.band(bit32.rshift(DataChunkHeader.ckSize, 8) , 0xFF)
myDataChunkHeaderAsByteArray[4] = bit32.band(DataChunkHeader.ckSize , 0xFF)

fostream = assert(io.open("output.wav", "wb"))

if(nil == fostream) then
	print("Sorry, error opening output file")
	os.exit()
end

local start_time = os.clock()

for i=0,11,1 do
	fostream:write(string.char(myRiffChunkHeaderAsByteArray[i]))
end

for i=0,7,1 do
	fostream:write(string.char(myFormatChunkHeaderAsByteArray[i]))
end

for i=0,15,1 do
	fostream:write(string.char(myWaveHeaderAsByteArray[i]))
end	

for i=0,7,1 do
	fostream:write(string.char(myDataChunkHeaderAsByteArray[i]))
end	


local binarydata={}
local t = {}

--newday = 0
--while newday < 300 :
while (true) do
--print ("ITERATION ",newday)
--newday = newday + 1
	local samples_unpacked = 0
	t = {}	-- reset

	samples_unpacked = WavpackUnpackSamples(wpc, temp_buffer, SAMPLE_BUFFER_SIZE / num_channels);

	total_unpacked_samples = total_unpacked_samples + samples_unpacked

	if (samples_unpacked > 0) then
		samples_unpacked = samples_unpacked * num_channels

		pcm_buffer = format_samples(bps, temp_buffer, samples_unpacked)

		for i = 1, (samples_unpacked * bps), 1 do
			t[i] = string.char(pcm_buffer[i])
		end
		
		binarydata = table.concat(t,"")
		
		fostream:write(binarydata)
	end	
			
	if (samples_unpacked == 0) then	
		break
	end	
end		

if ((WavpackGetNumSamples(wpc) ~= -1) and (total_unpacked_samples ~= WavpackGetNumSamples(wpc))) then
	print "Incorrect number of samples" 
	fostream:close()
	os.exit()
end

if (WavpackGetNumErrors(wpc) > 0) then
	print "CRC errors detected"
	fostream:close()
	os.exit()
end	

fostream:close()

print(string.format("Time to process file: %.2f secs\n", os.clock() - start_time))


